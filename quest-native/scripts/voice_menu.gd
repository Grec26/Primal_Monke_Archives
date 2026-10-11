extends "res://scripts/lobby_menu.gd"

const MenuTheme = preload("res://scripts/menu_theme.gd")
var _roster: Array = []
var _desktop_frame: Dictionary = {}
var _desktop_controls: GridContainer
var _desktop_peers: GridContainer
var _desktop_empty: Label
var _volume_slider: HSlider
var _desktop_hint: Label
var _world_hint: Label3D
var _world_volume: Label3D

func _init() -> void:
	toggle_key = KEY_F6
	toggle_hand = -1 # Open from the main menu in VR; do not reuse locomotion buttons.
	panel_size = Vector2(1.9, 2.05)

func _voice() -> Node:
	return game.get("voice") as Node if is_instance_valid(game) else null

func set_open(value: bool) -> void:
	if value and _game_text("frontend_state", "") == "loading": return
	var was_open := is_open
	if value and not was_open and is_instance_valid(game) and game.has_method("on_feature_menu_open"):
		game.call("on_feature_menu_open", self)
	super.set_open(value)
	if not value and was_open and is_instance_valid(game) and game.has_method("close_feature_menu"):
		game.call("close_feature_menu", self)
	elif value and not _is_xr() and _desktop_buttons.has("enable"):
		_desktop_buttons.enable.grab_focus()

func refresh_status() -> void:
	var voice := _voice()
	if voice == null: return
	_roster = []
	var session: Node = game.get("session")
	if session != null and session.has_method("room_roster"):
		for member in session.call("room_roster"):
			if not member.get("local", false): _roster.append(member)
	var snapshot := "%s|%s|%s|%s|%s|%s" % [voice.get("status"), voice.get("enabled"), voice.get("mic_muted"), voice.get("volume"), _roster, voice.get("muted_peers")]
	if snapshot == _state_snapshot: return
	_state_snapshot = snapshot
	_status_text = str(voice.get("status"))
	_update_labels()
	for action in _desktop_buttons:
		_desktop_buttons[action].disabled = not _action_enabled(action)
	_update_button_colors()

func _action_enabled(action: String) -> bool:
	var voice := _voice()
	if voice == null: return false
	if action == "mic": return bool(voice.get("enabled"))
	if action.begins_with("peer:"):
		var index := action.trim_prefix("peer:").to_int()
		return index >= 0 and index < _roster.size()
	return action in ["enable", "quieter", "louder", "close"]

func _dispatch(action: String) -> void:
	if not _action_enabled(action): return
	var voice := _voice()
	match action:
		"enable": voice.call("set_enabled", not bool(voice.get("enabled")))
		"mic": voice.call("set_mic_muted", not bool(voice.get("mic_muted")))
		"quieter": voice.call("set_volume", float(voice.get("volume")) - 0.1)
		"louder": voice.call("set_volume", float(voice.get("volume")) + 0.1)
		"close": set_open(false)
		_:
			if action.begins_with("peer:"):
				var id := int(_roster[action.trim_prefix("peer:").to_int()].get("id", 0))
				voice.call("set_peer_muted", id, not voice.get("muted_peers").has(id))
	refresh_status()

func _peer_text(index: int) -> String:
	if index >= _roster.size(): return "No player"
	var member: Dictionary = _roster[index]
	var muted: bool = _voice().get("muted_peers").has(int(member.get("id", 0)))
	return ("Unmute " if muted else "Mute ") + str(member.get("label", "Player")).left(18)

func _update_labels() -> void:
	var voice := _voice()
	if voice == null: return
	var enable_text := "Disable voice" if voice.get("enabled") else "Enable voice"
	var mic_text := "Unmute microphone" if voice.get("mic_muted") else "Mute microphone"
	if _desktop_status != null:
		_desktop_status.text = _status_text
		_desktop_buttons.enable.text = enable_text
		_desktop_buttons.mic.text = mic_text
		_desktop_hint.text = "Microphone is off until you unmute. PC: hold V to talk.\nLobby: room voice · Playing: nearby players within 14 m."
		_volume_slider.set_value_no_signal(float(voice.get("volume")) * 100.0)
		_desktop_empty.visible = _roster.is_empty()
		for index in range(7):
			_desktop_buttons["peer:%s" % index].text = _peer_text(index)
			_desktop_buttons["peer:%s" % index].visible = index < _roster.size()
	if _world_status != null:
		_world_status.text = _status_text
		_world_hint.text = "Unmute only when you want to speak.\nRoom voice in lobby · 14 m proximity in game"
		_world_volume.text = "VOICE VOLUME %s%%" % int(float(voice.get("volume")) * 100)
		for button in _world_buttons:
			var action: String = button.action
			if action == "enable": button.label.text = enable_text
			elif action == "mic": button.label.text = mic_text
			elif action.begins_with("peer:"): button.label.text = _peer_text(action.trim_prefix("peer:").to_int())

func _adapt_desktop_layout() -> void:
	var columns := 2 if get_viewport().get_visible_rect().size.x >= 640 else 1
	if _desktop_controls != null: _desktop_controls.columns = columns
	if _desktop_peers != null: _desktop_peers.columns = columns

func _create_desktop_menu() -> void:
	_desktop_frame = MenuTheme.desktop_frame(self, "VoiceOverlay", 35, 680)
	_canvas = _desktop_frame.canvas
	var content: VBoxContainer = _desktop_frame.content
	MenuTheme.label(content, "PRIMAL MONKE  /  TALK TO YOUR TRIBE", 12, MenuTheme.ORANGE, true)
	MenuTheme.label(content, "Voice chat", 32, MenuTheme.CREAM)
	_desktop_hint = MenuTheme.label(content, "", 15, MenuTheme.MUTED, true)
	var status_card := PanelContainer.new()
	status_card.add_theme_stylebox_override("panel", MenuTheme.style(Color("102c20"), Color("33523a"), 10))
	content.add_child(status_card)
	var status_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: status_margin.add_theme_constant_override("margin_" + side, 12)
	status_card.add_child(status_margin)
	_desktop_status = MenuTheme.label(status_margin, "", 15, MenuTheme.GREEN, true)
	_desktop_controls = GridContainer.new()
	_desktop_controls.add_theme_constant_override("h_separation", 8)
	_desktop_controls.add_theme_constant_override("v_separation", 8)
	content.add_child(_desktop_controls)
	MenuTheme.button(self, _desktop_controls, "Enable voice", "enable", true)
	MenuTheme.button(self, _desktop_controls, "Unmute microphone", "mic")
	var volume_row := HBoxContainer.new()
	content.add_child(volume_row)
	volume_row.add_theme_constant_override("separation", 14)
	var volume_label := MenuTheme.label(volume_row, "Voice volume", 15, MenuTheme.CREAM)
	volume_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.step = 5
	_volume_slider.custom_minimum_size.y = 34
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.add_theme_stylebox_override("slider", MenuTheme.style(Color("102c20"), Color("33523a"), 5))
	_volume_slider.add_theme_stylebox_override("grabber_area", MenuTheme.style(MenuTheme.GREEN, Color.TRANSPARENT, 5))
	_volume_slider.add_theme_stylebox_override("grabber_area_highlight", MenuTheme.style(MenuTheme.ORANGE, Color.TRANSPARENT, 5))
	_volume_slider.value_changed.connect(func(value: float):
		if _voice() != null: _voice().call("set_volume", value / 100.0))
	volume_row.add_child(_volume_slider)
	MenuTheme.label(content, "YOUR ROOM", 12, MenuTheme.ORANGE)
	_desktop_empty = MenuTheme.label(content, "Join a multiplayer room to see players here. You can mute each player separately.", 14, MenuTheme.MUTED, true)
	_desktop_peers = GridContainer.new()
	_desktop_peers.add_theme_constant_override("h_separation", 8)
	_desktop_peers.add_theme_constant_override("v_separation", 8)
	content.add_child(_desktop_peers)
	for index in range(7): MenuTheme.button(self, _desktop_peers, "No player", "peer:%s" % index, false, true)
	MenuTheme.button(self, content, "Back · F6", "close")
	MenuTheme.label(content, "Voice starts off. Leaving a room always mutes your microphone.", 12, MenuTheme.MUTED, true)
	get_viewport().size_changed.connect(_adapt_desktop_layout)
	tree_exiting.connect(func():
		if get_viewport().size_changed.is_connected(_adapt_desktop_layout):
			get_viewport().size_changed.disconnect(_adapt_desktop_layout))
	_adapt_desktop_layout()

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldVoice"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, panel_size, -0.035, Color("172633"))
	_world_label("VOICE CHAT", Vector2(0, 0.86), 54)
	_world_status = _world_label("", Vector2(0, 0.70), 26)
	_world_status.width = 1100
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_hint = _world_label("", Vector2(0, 0.54), 25)
	_world_button("Enable voice", "enable", Vector2(-0.43, 0.36), Vector2(0.80, 0.12), Color("285f59"))
	_world_button("Unmute microphone", "mic", Vector2(0.43, 0.36), Vector2(0.80, 0.12))
	_world_volume = _world_label("", Vector2(0, 0.20), 30)
	_world_button("QUIETER", "quieter", Vector2(-0.43, 0.07), Vector2(0.80, 0.11))
	_world_button("LOUDER", "louder", Vector2(0.43, 0.07), Vector2(0.80, 0.11))
	for index in range(7):
		var column := index % 2
		var row := index / 2
		_world_button("No player", "peer:%s" % index, Vector2(-0.43 + column * 0.86, -0.12 - row * 0.16), Vector2(0.80, 0.12))
	_world_button("BACK", "close", Vector2(0, -0.85), Vector2(1.65, 0.13), Color("285f59"))
	MenuTheme.world_text(_world_panel)
	_pointer = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.009
	dot.height = 0.018
	_pointer.mesh = dot
	_pointer.material_override = _material(Color("d9ff99"))
	_pointer.material_override.render_priority = 3
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pointer)
