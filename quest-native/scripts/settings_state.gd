extends Node

# Local preferences deliberately contain no account identity or credentials.
signal state_changed
const PREFERENCE_PATH := "user://primal_monke_settings.cfg"
const DEFAULTS := {
	"effects_volume": 1.0, "ambience_volume": 1.0, "muted": false,
	"mouse_sensitivity": 1.0, "invert_y": false, "look_fov": 75.0,
	"hud_visible": true, "fullscreen": false,
}
var game: Node3D
var effects_volume := 1.0
var ambience_volume := 1.0
var muted := false
var mouse_sensitivity := 1.0
var invert_y := false
var look_fov := 75.0
var hud_visible := true
var fullscreen := false
var status := "Your preferences are saved on this device."
var _was_xr := false

func _preference_path() -> String:
	return PREFERENCE_PATH

func _ready() -> void:
	_load_preferences()
	apply()
	_save_preferences()

func _number(value: Variant, fallback: float, minimum: float, maximum: float) -> float:
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), minimum, maximum)

func _boolean(value: Variant, fallback: bool) -> bool:
	return value if value is bool else fallback

func _load_preferences() -> void:
	# Carry forward the former audio controls before adding independent sliders.
	var sounds: Node = game.get("sounds") if is_instance_valid(game) else null
	if sounds != null:
		effects_volume = _number(sounds.get("gain"), 1.0, 0.0, 1.0)
		ambience_volume = _number(sounds.get("ambience_gain"), effects_volume, 0.0, 1.0)
		muted = _boolean(sounds.get("muted"), false)
	var preferences := ConfigFile.new()
	if preferences.load(_preference_path()) != OK:
		return
	effects_volume = _number(preferences.get_value("settings", "effects_volume", effects_volume), effects_volume, 0.0, 1.0)
	ambience_volume = _number(preferences.get_value("settings", "ambience_volume", ambience_volume), ambience_volume, 0.0, 1.0)
	muted = _boolean(preferences.get_value("settings", "muted", muted), muted)
	mouse_sensitivity = _number(preferences.get_value("settings", "mouse_sensitivity", 1.0), 1.0, 0.5, 2.0)
	look_fov = _number(preferences.get_value("settings", "look_fov", 75.0), 75.0, 70.0, 100.0)
	for key in ["invert_y", "hud_visible", "fullscreen"]:
		set(key, _boolean(preferences.get_value("settings", key, DEFAULTS[key]), DEFAULTS[key]))

func _save_preferences() -> void:
	var preferences := ConfigFile.new()
	for key in DEFAULTS:
		preferences.set_value("settings", key, get(key))
	status = "Your preferences are saved on this device." if preferences.save(_preference_path()) == OK else "Changes apply now, but could not be saved."

func set_value(key: String, value: Variant) -> bool:
	if not DEFAULTS.has(key):
		return false
	var validated: Variant
	match key:
		"effects_volume", "ambience_volume": validated = _number(value, float(get(key)), 0.0, 1.0)
		"mouse_sensitivity": validated = _number(value, mouse_sensitivity, 0.5, 2.0)
		"look_fov": validated = _number(value, look_fov, 70.0, 100.0)
		_: validated = _boolean(value, bool(get(key)))
	set(key, validated)
	apply()
	_save_preferences()
	state_changed.emit()
	return true

func reset_defaults() -> void:
	for key in DEFAULTS: set(key, DEFAULTS[key])
	apply()
	_save_preferences()
	state_changed.emit()

func _is_xr() -> bool:
	var player: Node = game.get("player") if is_instance_valid(game) else null
	return player != null and bool(player.get("xr_running"))

func can_set_fullscreen() -> bool:
	return OS.get_name() != "Android" and DisplayServer.get_name() != "headless" and not _is_xr()

func apply() -> void:
	if not is_instance_valid(game): return
	var sounds: Node = game.get("sounds")
	if sounds != null:
		sounds.call("set_gain", effects_volume)
		sounds.call("set_ambience_gain", ambience_volume)
		if bool(sounds.get("muted")) != muted: sounds.call("set_muted", muted)
	var player: Node = game.get("player")
	if player != null:
		player.set("mouse_sensitivity", mouse_sensitivity)
		player.set("invert_y", invert_y)
		player.set("look_fov", look_fov)
	if can_set_fullscreen():
		var current_mode := DisplayServer.window_get_mode()
		if fullscreen and current_mode not in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not fullscreen and current_mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_was_xr = _is_xr()

func _process(_delta: float) -> void:
	# Apply PC projection/window preferences after returning from a headset mode.
	if _was_xr != _is_xr(): apply()
