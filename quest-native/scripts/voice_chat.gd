extends Node

# Voice is explicitly opt-in. No microphone is opened during startup, while
# offline, while muted, or in headless runs. Audio never goes to disk.
const SAMPLE_RATE := 16000
const SAMPLES_PER_FRAME := 320
const FRAME_BYTES := SAMPLES_PER_FRAME * 2
const CHANNEL := 3
const MAX_SEQUENCE := 2147483647
const MAX_QUEUE := 4
const MAX_DISTANCE := 14.0
const RATE_CAPACITY := 12.0
const RATE_PER_SECOND := 55.0
const STALE_POSE_MS := 3000
const MAX_PEERS := 8
var game: Node3D
var enabled := false
var mic_muted := true
var status := "Voice off — enable it to listen, then unmute to speak"
var volume := 0.8
var muted_peers: Dictionary = {}
var received_frames := 0
var relayed_frames := 0
var rejected_frames := 0
var _sequence := 0
var _senders: Dictionary = {}
var _receivers: Dictionary = {}
var _players: Dictionary = {}
var _queues: Dictionary = {}
var _capture: AudioEffectCapture
var _microphone: AudioStreamPlayer
var _capture_bus := -1
var _capture_bus_name := ""
var _sample_buffer := PackedFloat32Array()
var _resample_position := 0.0
var _permission_pending := false
var _ptt_active := false
var _online := false
var _capture_started_ms := 0
var _captured_samples := 0
var _clock_ms := -1 # Test seam; production always uses the monotonic clock.

func _ready() -> void:
	name = "VoiceChat"
	set_process(true)
	if not multiplayer.peer_disconnected.is_connected(remove_peer):
		multiplayer.peer_disconnected.connect(remove_peer)

func _now() -> int:
	return _clock_ms if _clock_ms >= 0 else Time.get_ticks_msec()

func _session() -> Node:
	return game.get("session") as Node if is_instance_valid(game) else null

func _is_online() -> bool:
	var session := _session()
	return session != null and session.get("mode") in ["hosting", "connected"]

func _is_host() -> bool:
	var session := _session()
	return session != null and session.get("mode") == "hosting"

func _members() -> Dictionary:
	var session := _session()
	return session.get("members") if session != null and session.get("members") is Dictionary else {}

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		mic_muted = true
		_permission_pending = false
		_ptt_active = false
		_stop_capture()
		_clear_playback()
	_update_status()

func set_mic_muted(value: bool) -> void:
	if not enabled and not value:
		return
	mic_muted = value
	if value:
		_permission_pending = false
		_stop_capture()
	elif OS.get_name() == "Android" and "android.permission.RECORD_AUDIO" not in OS.get_granted_permissions():
		# This is called only by an explicit unmute / push-to-talk action.
		_permission_pending = not OS.request_permission("android.permission.RECORD_AUDIO")
	_update_status()

func set_peer_muted(peer_id: int, value: bool) -> void:
	if peer_id <= 0 or peer_id == multiplayer.get_unique_id(): return
	if value:
		muted_peers[peer_id] = true
		_clear_peer_playback(peer_id)
	else:
		muted_peers.erase(peer_id)

func set_volume(value: float) -> void:
	if not is_finite(value): return
	volume = clampf(value, 0.0, 1.0)
	for player in _players.values(): player.volume_db = linear_to_db(maxf(volume, 0.0001))

func shutdown() -> void:
	# Leaving a room always stops capture and requires a new explicit unmute.
	mic_muted = true
	_permission_pending = false
	_ptt_active = false
	_sequence = 0
	_senders.clear()
	_receivers.clear()
	muted_peers.clear()
	_stop_capture()
	_clear_playback()
	_online = false
	_update_status()

func remove_peer(peer_id: int) -> void:
	_senders.erase(peer_id)
	_receivers.erase(peer_id)
	muted_peers.erase(peer_id)
	_clear_peer_playback(peer_id)

func _clear_peer_playback(peer_id: int) -> void:
	_queues.erase(peer_id)
	if _players.has(peer_id):
		var player: AudioStreamPlayer3D = _players[peer_id]
		player.stop()
		player.queue_free()
		_players.erase(peer_id)

func _clear_playback() -> void:
	for peer_id in _players.keys(): _clear_peer_playback(int(peer_id))
	_queues.clear()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo or event.physical_keycode != KEY_V: return
	# Typing credentials or chat/menu input must never turn on the microphone.
	if event.pressed:
		if enabled and _is_online() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_ptt_active = true
			set_mic_muted(false)
	elif _ptt_active:
		_ptt_active = false
		set_mic_muted(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _ptt_active:
		_ptt_active = false
		set_mic_muted(true)

func _process(_delta: float) -> void:
	var online := _is_online()
	if _online and not online: shutdown()
	_online = online
	for peer_id in _players.keys():
		if not _members().has(peer_id): remove_peer(int(peer_id))
	if not enabled or not online:
		_stop_capture()
		_update_status()
		return
	if _permission_pending and "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		_permission_pending = false
	var focused: bool = not is_instance_valid(game) or game.get("xr_focused") != false
	if not focused and _ptt_active:
		_ptt_active = false
		set_mic_muted(true)
	if not mic_muted and not _permission_pending and focused and DisplayServer.get_name() != "headless":
		_start_capture()
		_capture_frames()
	else:
		_stop_capture()
	_play_pending()
	_update_status()

func _update_status() -> void:
	if not enabled: status = "Voice off — enable it to listen, then unmute to speak"
	elif not _is_online(): status = "Voice ready — join a multiplayer room; microphone muted"
	elif _permission_pending: status = "PM-V003: Allow microphone access, or keep listening with mic muted"
	elif mic_muted: status = "Listening · microphone muted · hold V to talk on PC"
	elif _microphone != null and _captured_samples == 0 and _now() - _capture_started_ms > 4000: status = "PM-V004: No microphone input — check Windows / headset microphone permissions"
	else: status = "Microphone on · lobby: room voice · game: 14 m proximity"

func _start_capture() -> void:
	if _microphone != null or DisplayServer.get_name() == "headless": return
	if not enabled or mic_muted or not _is_online(): return
	if not _members().has(multiplayer.get_unique_id()): return
	if OS.get_name() == "Android" and "android.permission.RECORD_AUDIO" not in OS.get_granted_permissions(): return
	_capture_bus_name = "PMVoiceCapture_%s" % get_instance_id()
	AudioServer.add_bus()
	_capture_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_capture_bus, _capture_bus_name)
	AudioServer.set_bus_mute(_capture_bus, true) # No local microphone monitoring.
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.1
	AudioServer.add_bus_effect(_capture_bus, _capture)
	_microphone = AudioStreamPlayer.new()
	_microphone.stream = AudioStreamMicrophone.new()
	_microphone.bus = _capture_bus_name
	add_child(_microphone)
	_microphone.play()
	_capture_started_ms = _now()
	_captured_samples = 0

func _stop_capture() -> void:
	if _microphone != null:
		_microphone.stop()
		_microphone.queue_free()
		_microphone = null
	if _capture_bus >= 0:
		var current_bus := AudioServer.get_bus_index(_capture_bus_name)
		if current_bus >= 0: AudioServer.remove_bus(current_bus)
	_capture_bus = -1
	_capture = null
	_sample_buffer.clear()
	_resample_position = 0.0
	_captured_samples = 0

func _capture_frames() -> void:
	if _capture == null: return
	var available := _capture.get_frames_available()
	if available <= 0: return
	# At most 100 ms of stereo input and 80 ms of mono output are retained.
	var input := _capture.get_buffer(mini(available, 4800))
	if _capture.get_frames_available() > 0: _capture.clear_buffer()
	var source_rate := float(AudioServer.get_input_mix_rate())
	if source_rate < 8000.0 or source_rate > 192000.0: return
	_captured_samples += input.size()
	var stride := source_rate / SAMPLE_RATE
	while _resample_position + 1.0 < input.size():
		var index := int(_resample_position)
		var mix := input[index].lerp(input[index + 1], _resample_position - index)
		_sample_buffer.append(clampf((mix.x + mix.y) * 0.5, -1.0, 1.0))
		_resample_position += stride
	_resample_position = maxf(0.0, _resample_position - input.size())
	if _sample_buffer.size() > SAMPLES_PER_FRAME * MAX_QUEUE:
		_sample_buffer = _sample_buffer.slice(_sample_buffer.size() - SAMPLES_PER_FRAME * MAX_QUEUE)
	var sent := 0
	while _sample_buffer.size() >= SAMPLES_PER_FRAME and sent < MAX_QUEUE:
		var pcm := encode_pcm(_sample_buffer.slice(0, SAMPLES_PER_FRAME))
		_sample_buffer = _sample_buffer.slice(SAMPLES_PER_FRAME)
		submit_frame(pcm)
		sent += 1

static func encode_pcm(samples: PackedFloat32Array) -> PackedByteArray:
	if samples.size() != SAMPLES_PER_FRAME: return PackedByteArray()
	var pcm := PackedByteArray()
	pcm.resize(FRAME_BYTES)
	for index in range(SAMPLES_PER_FRAME):
		if not is_finite(samples[index]): return PackedByteArray()
		var value := int(round(clampf(samples[index], -1.0, 1.0) * 32767.0))
		pcm.encode_s16(index * 2, value)
	return pcm

static func decode_pcm(pcm: PackedByteArray) -> PackedVector2Array:
	if pcm.size() != FRAME_BYTES: return PackedVector2Array()
	var samples := PackedVector2Array()
	samples.resize(SAMPLES_PER_FRAME)
	for index in range(SAMPLES_PER_FRAME):
		var value := float(pcm.decode_s16(index * 2)) / 32768.0
		samples[index] = Vector2(value, value)
	return samples

func submit_frame(pcm: PackedByteArray) -> bool:
	if not enabled or mic_muted or not _is_online() or pcm.size() != FRAME_BYTES: return false
	var local_id := multiplayer.get_unique_id()
	if not _members().has(local_id) or _sequence >= MAX_SEQUENCE: return false
	_sequence += 1
	if _is_host(): return _ingest_submission(local_id, _sequence, pcm)
	_submit_voice.rpc_id(1, _sequence, pcm)
	return true

func _valid_frame(sender: int, sequence: int, pcm: PackedByteArray, records: Dictionary, rate_limit: bool) -> bool:
	if not _is_online() or sender <= 0 or not _members().has(sender): return false
	if sequence <= 0 or sequence > MAX_SEQUENCE or pcm.size() != FRAME_BYTES: return false
	if not records.has(sender) and records.size() >= MAX_PEERS: return false
	var now := _now()
	var record: Dictionary = records.get(sender, {"sequence": 0, "clock": now, "tokens": RATE_CAPACITY})
	if sequence <= int(record.sequence): return false
	if rate_limit:
		var elapsed := clampf(float(now - int(record.clock)) / 1000.0, 0.0, 1.0)
		var tokens := minf(RATE_CAPACITY, float(record.tokens) + elapsed * RATE_PER_SECOND)
		if tokens < 1.0: return false
		record.tokens = tokens - 1.0
	record.sequence = sequence
	record.clock = now
	records[sender] = record
	return true

@rpc("any_peer", "call_remote", "unreliable_ordered", 3)
func _submit_voice(sequence: int, pcm: PackedByteArray) -> void:
	if not _is_host(): return
	# Identity comes exclusively from ENet, never from a supplied player ID.
	_ingest_submission(multiplayer.get_remote_sender_id(), sequence, pcm)

func _ingest_submission(sender: int, sequence: int, pcm: PackedByteArray) -> bool:
	if not _is_host() or not _valid_frame(sender, sequence, pcm, _senders, true):
		rejected_frames += 1
		return false
	if sender != multiplayer.get_unique_id(): _accept_playback(sender, sequence, pcm)
	for recipient in multiplayer.get_peers():
		if recipient != sender and _members().has(recipient) and _audible_between(sender, recipient):
			_relay_voice.rpc_id(recipient, sender, sequence, pcm)
			relayed_frames += 1
	return true

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _relay_voice(sender: int, sequence: int, pcm: PackedByteArray) -> void:
	if _is_host() or multiplayer.get_remote_sender_id() != 1: return
	_accept_playback(sender, sequence, pcm)

func _head_position(peer_id: int) -> Variant:
	var local_id := multiplayer.get_unique_id()
	if peer_id == local_id and is_instance_valid(game):
		var player: Node = game.get("player")
		if player != null:
			var head: Node3D = player.get("head")
			if head != null and head.global_position.is_finite(): return head.global_position
	var pose: Variant = _members().get(peer_id)
	if not pose is Dictionary: return null
	var head: Variant = pose.get("head")
	if not head is Vector3 or not head.is_finite(): return null
	if _is_host() and _now() - int(pose.get("seen", 0)) > STALE_POSE_MS: return null
	return head

func _audible_between(sender: int, recipient: int) -> bool:
	var session := _session()
	if session == null: return false
	if session.get("phase") == "lobby": return true
	if session.get("phase") != "playing": return false
	var source: Variant = _head_position(sender)
	var listener: Variant = _head_position(recipient)
	return source is Vector3 and listener is Vector3 and source.distance_to(listener) <= MAX_DISTANCE

func _accept_playback(sender: int, sequence: int, pcm: PackedByteArray) -> bool:
	var local_id := multiplayer.get_unique_id()
	if not enabled or not _is_online() or sender == local_id or muted_peers.has(sender): return false
	if not _audible_between(sender, local_id): return false
	if not _valid_frame(sender, sequence, pcm, _receivers, true): return false
	if not _queues.has(sender) and _queues.size() >= MAX_PEERS - 1: return false
	var queue: Array = _queues.get(sender, [])
	if queue.size() >= MAX_QUEUE: queue.pop_front()
	queue.append(pcm.duplicate())
	_queues[sender] = queue
	received_frames += 1
	return true

func _play_pending() -> void:
	for peer_id in _queues.keys():
		if muted_peers.has(peer_id) or not _audible_between(int(peer_id), multiplayer.get_unique_id()):
			_clear_peer_playback(int(peer_id))
			continue
		var queue: Array = _queues[peer_id]
		if queue.is_empty(): continue
		if not _players.has(peer_id):
			var player := AudioStreamPlayer3D.new()
			var stream := AudioStreamGenerator.new()
			stream.mix_rate = SAMPLE_RATE
			stream.buffer_length = 0.1
			player.stream = stream
			player.max_distance = MAX_DISTANCE
			player.volume_db = linear_to_db(maxf(volume, 0.0001))
			add_child(player)
			player.play()
			_players[peer_id] = player
		var player: AudioStreamPlayer3D = _players[peer_id]
		var head: Variant = _head_position(int(peer_id))
		if head is Vector3: player.global_position = head
		# Room voice has no distance attenuation while players are in the lobby.
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED if _session().get("phase") == "lobby" else AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback == null: continue
		while not queue.is_empty() and playback.can_push_buffer(SAMPLES_PER_FRAME):
			playback.push_buffer(decode_pcm(queue.pop_front()))

func _exit_tree() -> void:
	_stop_capture()
	_clear_playback()
