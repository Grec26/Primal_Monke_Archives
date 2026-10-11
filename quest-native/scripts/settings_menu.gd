extends "res://scripts/lobby_menu.gd"

const MenuTheme = preload("res://scripts/menu_theme.gd")
var _desktop_frame: Dictionary = {}
var _desktop_cards: GridContainer
var _desktop_values: Dictionary = {}
var _world_values: Dictionary = {}
var _desktop_actions: GridContainer
var _world_pc_hint: Label3D

func _init() -> void:
	toggle_key = KEY_F7
	toggle_hand = -1
	panel_size = Vector2(2.15, 2.05)

func _settings() -> Node:
	return game.get("settings") as Node if is_instance_valid(game) else null

func set_open(value: bool) -> void:
	if value and _game_text("frontend_state", "") == "loading": return
	var was_open := is_open
	if value and not was_open and is_instance_valid(game) and game.has_method("on_feature_menu_open"):
		game.call("on_feature_menu_open", self)
	super.set_open(value)
	if not value and was_open and is_instance_valid(game) and game.has_method("close_feature_menu"):
		game.call("close_feature_menu", self)
	elif value and not _is_xr() and _desktop_buttons.has("mute"):
		_desktop_buttons.mute.grab_focus()

func refresh_status() -> void:
	var settings := _settings()
	if settings == null: return
	var snapshot := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [settings.effects_volume,
		settings.ambience_volume, settings.muted, settings.mouse_sensitivity, settings.invert_y,
		settings.look_fov, settings.hud_visible, settings.fullscreen, settings.status, _is_xr(),
		_game_text("frontend_state", "")]
	if snapshot == _state_snapshot: return
	_state_snapshot = snapshot
	_status_text = settings.status
	_update_labels()
	for action in _desktop_buttons: _desktop_buttons[action].disabled = not _action_enabled(action)
	_update_button_colors()

func _action_enabled(action: String) -> bool:
	if _settings() == null or _game_text("frontend_state", "") == "loading": return false
	if action in ["sensitivity_down", "sensitivity_up", "invert", "fov_down", "fov_up"]:
		return not _is_xr() and OS.get_name() != "Android"
	if action == "fullscreen": return bool(_settings().call("can_set_fullscreen"))
	if action == "voice": return is_instance_valid(game) and game.has_method("open_voice_menu")
	return action in ["effects_down", "effects_up", "ambience_down", "ambience_up", "mute", "hud", "reset", "close"]

func _dispatch(action: String) -> void:
	if not _action_enabled(action): return
	var settings := _settings()
	match action:
		"effects_down": settings.call("set_value", "effects_volume", settings.effects_volume - 0.1)
		"effects_up": settings.call("set_value", "effects_volume", settings.effects_volume + 0.1)
		"ambience_down": settings.call("set_value", "ambience_volume", settings.ambience_volume - 0.1)
		"ambience_up": settings.call("set_value", "ambience_volume", settings.ambience_volume + 0.1)
		"mute": settings.call("set_value", "muted", not settings.muted)
		"sensitivity_down": settings.call("set_value", "mouse_sensitivity", snappedf(settings.mouse_sensitivity - 0.1, 0.1))
		"sensitivity_up": settings.call("set_value", "mouse_sensitivity", snappedf(settings.mouse_sensitivity + 0.1, 0.1))
		"invert": settings.call("set_value", "invert_y", not settings.invert_y)
		"fov_down": settings.call("set_value", "look_fov", settings.look_fov - 5.0)
		"fov_up": settings.call("set_value", "look_fov", settings.look_fov + 5.0)
		"hud": settings.call("set_value", "hud_visible", not settings.hud_visible)
		"fullscreen": settings.call("set_value", "fullscreen", not settings.fullscreen)
		"reset": settings.call("reset_defaults")
		"voice": game.call("open_voice_menu")
		"close": set_open(false)
	refresh_status()

func _captions() -> Dictionary:
	var settings := _settings()
	return {
		"effects": "Effects %d%%" % roundi(settings.effects_volume * 100.0),
		"ambience": "Forest ambience %d%%" % roundi(settings.ambience_volume * 100.0),
		"sensitivity": "Mouse sensitivity %.1fx" % settings.mouse_sensitivity,
		"fov": "Field of view %d°" % int(settings.look_fov),
		"mute": "Game sounds: MUTED" if settings.muted else "Game sounds: ON",
		"invert": "Invert mouse Y: ON" if settings.invert_y else "Invert mouse Y: OFF",
		"hud": "Game HUD: ON" if settings.hud_visible else "Game HUD: OFF",
		"fullscreen": "Fullscreen: ON" if settings.fullscreen else "Fullscreen: OFF",
	}

func _update_labels() -> void:
	if _settings() == null: return
	var captions := _captions()
	if _desktop_status != null: _desktop_status.text = _status_text
	for key in _desktop_values: _desktop_values[key].text = captions[key]
	for key in _world_values: _world_values[key].text = captions[key]
	for key in ["mute", "invert", "hud", "fullscreen"]:
		if _desktop_buttons.has(key): _desktop_buttons[key].text = captions[key]
		for button in _world_buttons:
			if button.action == key: button.label.text = captions[key]
	if _world_pc_hint != null:
		_world_pc_hint.text = "PC controls · Available in desktop mode" if _is_xr() or OS.get_name() == "Android" else "PC controls · Hold right mouse to look"

func _card(title: String, hint: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", MenuTheme.style(MenuTheme.FOREST, Color("375940"), 12))
	_desktop_cards.add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	card.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	MenuTheme.label(body, title, 19, MenuTheme.CREAM, true)
	MenuTheme.label(body, hint, 13, MenuTheme.MUTED, true)
	return body

func _number_controls(parent: VBoxContainer, key: String, down: String, up: String) -> void:
	_desktop_values[key] = MenuTheme.label(parent, "", 18, MenuTheme.GREEN, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	MenuTheme.button(self, row, "−", down)
	MenuTheme.button(self, row, "+", up)

func _adapt_desktop_layout() -> void:
	var wide := get_viewport().get_visible_rect().size.x >= 720
	if _desktop_cards != null: _desktop_cards.columns = 2 if wide else 1
	if _desktop_actions != null: _desktop_actions.columns = 3 if wide else 1

func _create_desktop_menu() -> void:
	_desktop_frame = MenuTheme.desktop_frame(self, "SettingsOverlay", 38, 820)
	_canvas = _desktop_frame.canvas
	var content: VBoxContainer = _desktop_frame.content
	MenuTheme.label(content, "PRIMAL MONKE  /  MAKE IT YOURS", 12, MenuTheme.ORANGE, true)
	MenuTheme.label(content, "Settings", 32)
	MenuTheme.label(content, "Tune your sound, PC controls, and display. Changes apply immediately.", 15, MenuTheme.MUTED, true)
	_desktop_cards = GridContainer.new()
	_desktop_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desktop_cards.add_theme_constant_override("h_separation", 12)
	_desktop_cards.add_theme_constant_override("v_separation", 12)
	content.add_child(_desktop_cards)
	var audio := _card("Sound", "Game sounds and forest ambience have separate volumes.")
	_number_controls(audio, "effects", "effects_down", "effects_up")
	_number_controls(audio, "ambience", "ambience_down", "ambience_up")
	MenuTheme.button(self, audio, "", "mute")
	var controls := _card("PC controls", "Mouse settings apply in desktop mode. Headset movement stays natural.")
	_number_controls(controls, "sensitivity", "sensitivity_down", "sensitivity_up")
	MenuTheme.button(self, controls, "", "invert")
	_number_controls(controls, "fov", "fov_down", "fov_up")
	var display := _card("Display", "Hide the round HUD for a cleaner view. Fullscreen is available on PC.")
	MenuTheme.button(self, display, "", "hud")
	MenuTheme.button(self, display, "", "fullscreen")
	var voice := _card("Voice chat", "Voice stays off until you enable it. Choose microphone and player mutes in Voice controls.")
	MenuTheme.button(self, voice, "Voice controls", "voice")
	_desktop_status = MenuTheme.label(content, "", 13, MenuTheme.MUTED, true)
	_desktop_actions = GridContainer.new()
	_desktop_actions.add_theme_constant_override("h_separation", 8)
	_desktop_actions.add_theme_constant_override("v_separation", 8)
	content.add_child(_desktop_actions)
	MenuTheme.button(self, _desktop_actions, "Restore defaults", "reset")
	MenuTheme.button(self, _desktop_actions, "Back · F7", "close", true)
	var viewport := get_viewport()
	viewport.size_changed.connect(_adapt_desktop_layout)
	tree_exiting.connect(func():
		if viewport.size_changed.is_connected(_adapt_desktop_layout): viewport.size_changed.disconnect(_adapt_desktop_layout))
	_adapt_desktop_layout()

func _world_number(key: String, y: float, down: String, up: String) -> void:
	_world_values[key] = _world_label("", Vector2(-0.28, y), 29)
	_world_button("−", down, Vector2(0.53, y), Vector2(0.26, 0.13))
	_world_button("+", up, Vector2(0.86, y), Vector2(0.26, 0.13))

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldSettings"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, panel_size, -0.035, MenuTheme.FOREST)
	_world_label("SETTINGS", Vector2(0, 0.88), 50)
	_world_label("Your preferences · Saved on this device", Vector2(0, 0.72), 25)
	_world_number("effects", 0.51, "effects_down", "effects_up")
	_world_number("ambience", 0.30, "ambience_down", "ambience_up")
	_world_button("", "mute", Vector2(0, 0.08), Vector2(1.93, 0.13))
	_world_button("", "hud", Vector2(0, -0.14), Vector2(1.93, 0.13))
	_world_pc_hint = _world_label("", Vector2(0, -0.34), 23)
	_world_button("RESTORE DEFAULTS", "reset", Vector2(0, -0.52), Vector2(1.93, 0.13))
	_world_button("VOICE", "voice", Vector2(-0.5, -0.73), Vector2(0.93, 0.13))
	_world_button("BACK", "close", Vector2(0.5, -0.73), Vector2(0.93, 0.13), Color("386d4b"))
	_world_label("Aim + trigger · Sound mute does not change voice", Vector2(0, -0.91), 21)
	MenuTheme.world_text(_world_panel)
	_pointer = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.009
	dot.height = 0.018
	_pointer.mesh = dot
	_pointer.material_override = _material(MenuTheme.GREEN)
	_pointer.material_override.render_priority = 3
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pointer)
