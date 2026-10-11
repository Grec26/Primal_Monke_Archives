extends "res://scripts/lobby_menu.gd"

# Root owns the room, its roster, and the lobby/loading/playing transition.
# This menu only forwards actions; joining a room never starts a local round.
const LOBBY_CREAM := Color("f0edda")
const LOBBY_ORANGE := Color("eaa35b")
const LOBBY_DARK := Color("102a24")
const LOBBY_GREEN := Color("315647")
const LOBBY_MUTED := Color("a2bbac")
const ROOM_CAPACITY := 8

var _desktop_count: Label
var _desktop_heading: Label
var _desktop_hint: Label
var _desktop_members: Array[Label] = []
var _world_count: Label3D
var _world_heading: Label3D
var _world_hint: Label3D
var _world_members: Array[Label3D] = []

func _init() -> void:
	panel_size = Vector2(1.78, 2.38)
	_status_text = "Host a lobby or join a friend on the same Wi-Fi."

func _is_staging() -> bool:
	return is_instance_valid(game) and game.get("lobby_is_staging") == true

func _is_host() -> bool:
	return is_instance_valid(game) and game.has_method("is_session_host") and bool(game.call("is_session_host"))

func _toggle_available() -> bool:
	if not is_instance_valid(game):
		return false
	var state := _game_text("frontend_state", "")
	return state == "lobby" or (_game_text("network_mode", "offline") != "offline" and state != "loading" and state != "main_menu")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event.physical_keycode == toggle_key or event.keycode == toggle_key) and not _toggle_available():
		return
	super._input(event)

func toggle() -> void:
	if not _toggle_available():
		return
	if is_open:
		if not _is_staging():
			_close_overlay()
	elif is_instance_valid(game) and game.has_method("open_multiplayer_lobby"):
		game.call("open_multiplayer_lobby")
	else:
		set_open(true)

func set_open(value: bool) -> void:
	if value:
		if is_instance_valid(game) and game.has_method("can_open_lobby_menu"):
			if not bool(game.call("can_open_lobby_menu")):
				return
		elif not _toggle_available():
			return
	super.set_open(value)

func _close_overlay() -> void:
	set_open(false)
	if is_instance_valid(game) and game.has_method("on_lobby_menu_closed"):
		game.call("on_lobby_menu_closed")

func _members() -> Array:
	if not is_instance_valid(game):
		return []
	var members: Variant = game.get("lobby_members")
	return members if members is Array else []

func _member_text(member: Dictionary) -> String:
	# Room labels are public display names, never PlayFab IDs or credentials.
	var label := str(member.get("label", "Player")).replace("\n", " ").replace("\r", " ").left(24)
	var tags: Array[String] = []
	if member.get("is_host", false) == true:
		tags.append("HOST")
	if member.get("is_self", false) == true:
		tags.append("YOU")
	return label + ("  ·  " + " / ".join(tags) if not tags.is_empty() else "")

func _start_hint() -> String:
	if not _is_staging():
		return "The shared round is running."
	match _game_text("network_mode", "offline"):
		"hosting": return "Invite friends using your IP, then start together."
		"joining", "connected": return "Waiting for the host to start the match."
	return "Choose Host or enter your friend's host IP."

func refresh_status() -> void:
	if not is_instance_valid(game):
		return
	var status := _game_text("network_status", _status_text)
	var notice := _game_text("play_mode_notice", "")
	if not notice.is_empty():
		status += "\n" + notice
	var members := _members()
	var snapshot := "%s|%s|%s|%s|%s|%s|%s" % [status, _game_text("session_address", "Not available"), _game_text("network_mode", "offline"), _is_staging(), _action_enabled("start"), _is_xr(), JSON.stringify(members)]
	if snapshot == _state_snapshot:
		return
	_state_snapshot = snapshot
	_status_text = status
	_update_labels()
	for action in _desktop_buttons:
		var button: Button = _desktop_buttons[action]
		button.disabled = not _action_enabled(action)
	if _address_edit != null:
		_address_edit.editable = _action_enabled("join")
	_update_button_colors()

func _action_enabled(action: String) -> bool:
	var mode := _game_text("network_mode", "offline")
	if action == "start":
		return _is_staging() and _is_host() and is_instance_valid(game) and game.get("lobby_can_start") == true and game.has_method("start_multiplayer_round")
	if action == "main":
		return is_instance_valid(game) and game.has_method("return_to_main_menu")
	if action == "close":
		return not _is_staging()
	if action.begins_with("key:") or action in ["backspace", "clear"]:
		return mode == "offline"
	return super._action_enabled(action)

func _dispatch(action: String) -> void:
	if not _action_enabled(action):
		return
	match action:
		"start":
			game.call("start_multiplayer_round")
		"main":
			game.call("return_to_main_menu")
		"close":
			_close_overlay()
		_:
			super._dispatch(action)
	refresh_status()

func _update_labels() -> void:
	var members := _members()
	var count := "PLAYERS  %d / %d" % [mini(members.size(), ROOM_CAPACITY), ROOM_CAPACITY]
	var heading := "THE LOBBY" if _is_staging() else "YOUR ROOM"
	var address := "Your IP: " + _game_text("session_address", "Not available")
	var hint := _start_hint()
	if _desktop_heading != null:
		_desktop_heading.text = heading
		_desktop_count.text = count
		_desktop_status.text = _status_text
		_desktop_address.text = address
		_desktop_hint.text = hint
	if _world_heading != null:
		_world_heading.text = heading
		_world_count.text = count
		_world_status.text = _status_text
		_world_address.text = address
		_world_hint.text = hint
		_world_ip.text = _address if not _address.is_empty() else "Enter host IP"
	for index in range(ROOM_CAPACITY):
		var occupied := index < members.size() and members[index] is Dictionary
		var text := _member_text(members[index]) if occupied else "Open spot"
		if index < _desktop_members.size():
			_desktop_members[index].text = text
			_desktop_members[index].modulate = LOBBY_CREAM if occupied else LOBBY_MUTED
		if index < _world_members.size():
			_world_members[index].text = text
			_world_members[index].modulate = LOBBY_CREAM if occupied else LOBBY_MUTED

func _panel_style(color: Color, border := false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(16)
	if border:
		style.border_color = Color("486f59")
		style.set_border_width_all(1)
	return style

func _lobby_button(parent: HBoxContainer, caption: String, action: String, accent := false) -> void:
	_desktop_button(parent, caption, action)
	var button: Button = _desktop_buttons[action]
	button.custom_minimum_size.y = 42
	var color := LOBBY_ORANGE if accent else LOBBY_GREEN
	button.add_theme_stylebox_override("normal", _panel_style(color))
	button.add_theme_stylebox_override("hover", _panel_style(color.lightened(0.13)))
	button.add_theme_stylebox_override("pressed", _panel_style(color.darkened(0.14)))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("213b32")))
	button.add_theme_color_override("font_color", LOBBY_DARK if accent else LOBBY_CREAM)
	button.add_theme_color_override("font_hover_color", LOBBY_DARK if accent else LOBBY_CREAM)
	button.add_theme_color_override("font_pressed_color", LOBBY_DARK if accent else LOBBY_CREAM)
	button.add_theme_color_override("font_disabled_color", Color("789281"))
	button.add_theme_font_size_override("font_size", 16)

func _create_desktop_menu() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "MultiplayerLobbyOverlay"
	_canvas.layer = 30
	add_child(_canvas)
	var root := Control.new()
	_canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.045, 0.035, 0.90)
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(790, 480)
	panel.add_theme_stylebox_override("panel", _panel_style(LOBBY_DARK, true))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	content.add_child(header)
	_desktop_heading = Label.new()
	_desktop_heading.add_theme_font_size_override("font_size", 34)
	_desktop_heading.modulate = LOBBY_CREAM
	_desktop_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_desktop_heading)
	_desktop_count = Label.new()
	_desktop_count.modulate = LOBBY_ORANGE
	_desktop_count.add_theme_font_size_override("font_size", 16)
	header.add_child(_desktop_count)
	var subtitle := Label.new()
	subtitle.text = "Bring your monkes. PC, PC VR and Quest play together on the same Wi-Fi."
	subtitle.modulate = LOBBY_MUTED
	subtitle.add_theme_font_size_override("font_size", 16)
	content.add_child(subtitle)
	content.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	content.add_child(body)
	var roster := VBoxContainer.new()
	roster.custom_minimum_size.x = 332
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.add_theme_constant_override("separation", 8)
	body.add_child(roster)
	var roster_title := Label.new()
	roster_title.text = "ROOM MEMBERS"
	roster_title.modulate = LOBBY_ORANGE
	roster_title.add_theme_font_size_override("font_size", 14)
	roster.add_child(roster_title)
	for index in range(ROOM_CAPACITY):
		var member := Label.new()
		member.custom_minimum_size.y = 22
		member.add_theme_font_size_override("font_size", 16)
		member.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		member.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		roster.add_child(member)
		_desktop_members.append(member)
	var connection := VBoxContainer.new()
	connection.custom_minimum_size.x = 350
	connection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connection.add_theme_constant_override("separation", 10)
	body.add_child(connection)
	_desktop_status = Label.new()
	_desktop_status.custom_minimum_size.y = 54
	_desktop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_status.modulate = LOBBY_CREAM
	connection.add_child(_desktop_status)
	_desktop_address = Label.new()
	_desktop_address.modulate = LOBBY_MUTED
	connection.add_child(_desktop_address)
	var caption := Label.new()
	caption.text = "HOST IPv4 ADDRESS"
	caption.modulate = LOBBY_ORANGE
	caption.add_theme_font_size_override("font_size", 13)
	connection.add_child(caption)
	_address_edit = LineEdit.new()
	_address_edit.text = _address
	_address_edit.placeholder_text = "192.168.1.25"
	_address_edit.max_length = 15
	_address_edit.custom_minimum_size.y = 40
	_address_edit.text_changed.connect(_set_address)
	_address_edit.text_submitted.connect(func(_value: String): _dispatch("join"))
	connection.add_child(_address_edit)
	var room_actions := HBoxContainer.new()
	room_actions.add_theme_constant_override("separation", 8)
	connection.add_child(room_actions)
	_lobby_button(room_actions, "Host", "host")
	_lobby_button(room_actions, "Join", "join")
	_lobby_button(room_actions, "Leave", "leave")
	var start_row := HBoxContainer.new()
	connection.add_child(start_row)
	_lobby_button(start_row, "Start match", "start", true)
	_desktop_hint = Label.new()
	_desktop_hint.custom_minimum_size.y = 38
	_desktop_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_hint.modulate = LOBBY_MUTED
	connection.add_child(_desktop_hint)
	content.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	content.add_child(footer)
	_lobby_button(footer, "Main menu", "main")
	_lobby_button(footer, "Account", "account")
	_lobby_button(footer, "Back to game", "close")
	var controls := Label.new()
	controls.text = "Tab / right B: room menu    ·    Headset: aim with your right hand, then press trigger"
	controls.add_theme_font_size_override("font_size", 13)
	controls.modulate = LOBBY_MUTED
	content.add_child(controls)

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldMultiplayerLobby"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, panel_size, -0.035, LOBBY_DARK)
	_world_heading = _world_label("THE LOBBY", Vector2(0, 1.02), 49)
	_world_count = _world_label("", Vector2(0, 0.93), 26)
	_world_count.modulate = LOBBY_ORANGE
	_world_status = _world_label("", Vector2(0, 0.81), 26)
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_status.width = 1500
	_world_address = _world_label("", Vector2(0, 0.65), 25)
	_world_label("HOST IPv4 ADDRESS", Vector2(0, 0.53), 24).modulate = LOBBY_ORANGE
	_world_box(Vector2(0, 0.44), Vector2(1.49, 0.085), -0.005, LOBBY_GREEN)
	_world_ip = _world_label(_address, Vector2(0, 0.44), 36)
	_world_button("HOST", "host", Vector2(-0.52, 0.29), Vector2(0.45, 0.10), LOBBY_GREEN)
	_world_button("JOIN", "join", Vector2(0, 0.29), Vector2(0.45, 0.10), LOBBY_GREEN)
	_world_button("LEAVE", "leave", Vector2(0.52, 0.29), Vector2(0.45, 0.10), LOBBY_GREEN)
	var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", ".", "⌫"]
	for index in range(keys.size()):
		var column := index % 4
		var row := index / 4
		var action: String = "backspace" if keys[index] == "⌫" else "key:" + keys[index]
		_world_button(keys[index], action, Vector2(-0.57 + column * 0.38, 0.15 - row * 0.12), Vector2(0.33, 0.10), LOBBY_GREEN)
	_world_button("CLEAR IP", "clear", Vector2(0, -0.22), Vector2(1.47, 0.09), LOBBY_GREEN)
	_world_label("ROOM MEMBERS", Vector2(0, -0.35), 24).modulate = LOBBY_ORANGE
	for index in range(ROOM_CAPACITY):
		var column := index % 2
		var row := index / 2
		var label := _world_label("Open spot", Vector2(-0.42 + column * 0.84, -0.45 - row * 0.078), 21)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_world_members.append(label)
	_world_hint = _world_label("", Vector2(0, -0.79), 21)
	_world_button("START MATCH", "start", Vector2(-0.39, -0.90), Vector2(0.72, 0.11), Color("956535"))
	_world_button("MAIN MENU", "main", Vector2(0.39, -0.90), Vector2(0.72, 0.11), LOBBY_GREEN)
	_world_button("ACCOUNT", "account", Vector2(-0.39, -1.04), Vector2(0.72, 0.10), LOBBY_GREEN)
	_world_button("BACK TO GAME", "close", Vector2(0.39, -1.04), Vector2(0.72, 0.10), LOBBY_GREEN)
	_world_label("Right hand aim + trigger to select", Vector2(0, -1.14), 21)
	_pointer = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.009
	dot.height = 0.018
	_pointer.mesh = dot
	_pointer.material_override = _material(LOBBY_ORANGE)
	_pointer.material_override.render_priority = 3
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pointer)
