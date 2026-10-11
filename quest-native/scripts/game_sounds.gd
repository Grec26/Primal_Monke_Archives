extends Node3D

# Original synthesized sounds, streamed through a small fixed voice pool. All
# audio settings are local preferences and do not contain account information.
const CUES := {
	"click": "res://assets/audio/ui_click.wav",
	"tag": "res://assets/audio/tag.wav",
	"success": "res://assets/audio/success.wav",
	"error": "res://assets/audio/error.wav",
	"level_up": "res://assets/audio/level_up.wav",
	"hand_push": "res://assets/audio/hand_push.wav",
	"landing": "res://assets/audio/landing.wav",
}
const AMBIENCE := "res://assets/audio/forest_ambience.wav"
const PREFERENCE_PATH := "user://primal_monke_audio.cfg"
const MAX_VOICES := 8
const MASTER_DB := -7.0
const EFFECTS_BUS := "Primal Effects"

var game: Node3D
var muted := false
var gain := 1.0
var _streams: Dictionary = {}
var _flat_voices: Array[AudioStreamPlayer] = []
var _spatial_voices: Array[AudioStreamPlayer3D] = []
var _ambience: AudioStreamPlayer
var _index := 0
var _previous_contact := false
var _previous_floor := true
var _previous_velocity := Vector3.ZERO
var _last_push_ms := -1000
var _observing := false

func _ready() -> void:
	var bus_index := AudioServer.get_bus_index(EFFECTS_BUS)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, EFFECTS_BUS)
		AudioServer.set_bus_send(bus_index, "Master")
		var limiter := AudioEffectLimiter.new()
		limiter.threshold_db = -4.0
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(bus_index, limiter)
	var preferences := ConfigFile.new()
	if preferences.load(PREFERENCE_PATH) == OK:
		muted = bool(preferences.get_value("audio", "muted", false))
		gain = clampf(float(preferences.get_value("audio", "gain", 1.0)), 0.0, 1.0)
	for cue in CUES:
		_streams[cue] = load(CUES[cue]) as AudioStreamWAV
	for index in range(MAX_VOICES):
		var flat := AudioStreamPlayer.new()
		flat.bus = EFFECTS_BUS
		add_child(flat)
		_flat_voices.append(flat)
		var spatial := AudioStreamPlayer3D.new()
		spatial.bus = EFFECTS_BUS
		spatial.max_distance = 22.0
		spatial.unit_size = 2.4
		spatial.max_db = 0.0
		add_child(spatial)
		_spatial_voices.append(spatial)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = EFFECTS_BUS
	_ambience.stream = load(AMBIENCE) as AudioStreamWAV
	if _ambience.stream is AudioStreamWAV:
		_ambience.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_ambience.stream.loop_begin = 0
		_ambience.stream.loop_end = _ambience.stream.data.size() / 2
	add_child(_ambience)
	_apply_volume()
	# Dummy audio on a test server never starts capture or playback.
	if DisplayServer.get_name() != "headless" and not muted:
		_ambience.play()

func _save_preferences() -> void:
	var preferences := ConfigFile.new()
	preferences.set_value("audio", "muted", muted)
	preferences.set_value("audio", "gain", gain)
	preferences.save(PREFERENCE_PATH)

func _apply_volume() -> void:
	var level := MASTER_DB + linear_to_db(maxf(gain, 0.0001))
	for voice in _flat_voices:
		voice.volume_db = level
	for voice in _spatial_voices:
		voice.volume_db = level
	if _ambience != null:
		_ambience.volume_db = level - 15.0

func set_muted(value: bool) -> void:
	muted = value
	_save_preferences()
	if muted:
		for voice in _flat_voices: voice.stop()
		for voice in _spatial_voices: voice.stop()
		if _ambience != null: _ambience.stop()
	elif _ambience != null and DisplayServer.get_name() != "headless":
		_ambience.play()

func set_gain(value: float) -> void:
	gain = clampf(value, 0.0, 1.0)
	_apply_volume()
	_save_preferences()

func play_cue(cue: String, at: Vector3 = Vector3.INF) -> void:
	if muted or gain <= 0.0 or DisplayServer.get_name() == "headless": return
	var stream: AudioStreamWAV = _streams.get(cue) as AudioStreamWAV
	if stream == null or _flat_voices.is_empty(): return
	var index := _index % MAX_VOICES
	_index += 1
	# Reuse one slot rather than allocating an unbounded number of players.
	_flat_voices[index].stop()
	_spatial_voices[index].stop()
	if at.is_finite():
		var voice := _spatial_voices[index]
		voice.global_position = at
		voice.stream = stream
		voice.play()
	else:
		_flat_voices[index].stream = stream
		_flat_voices[index].play()

func _process(_delta: float) -> void:
	if not is_instance_valid(game): return
	var player: Node3D = game.get("player") as Node3D
	if player == null or not bool(player.get("input_allowed")):
		_observing = false
		return
	var contact := bool(player.get("contacts"))
	var floor_contact: bool = player is CharacterBody3D and (player as CharacterBody3D).is_on_floor()
	var velocity: Vector3 = player.get("velocity")
	if _observing:
		var now := Time.get_ticks_msec()
		if contact and not _previous_contact and now - _last_push_ms > 180:
			_last_push_ms = now
			play_cue("hand_push", player.global_position)
		if floor_contact and not _previous_floor and _previous_velocity.y < -1.3:
			play_cue("landing", player.global_position)
	_previous_contact = contact
	_previous_floor = floor_contact
	_previous_velocity = velocity
	_observing = true
