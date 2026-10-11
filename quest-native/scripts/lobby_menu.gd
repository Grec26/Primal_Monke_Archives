extends Node3D

# The forest assigns game before adding this menu. It owns networking, movement,
# and round state; this node only displays the lobby and forwards user actions.
var game: Node3D
var is_open := false
var toggle_key := KEY_TAB
var toggle_hand := 1
var toggle_button := "by_button"

const PANEL_SIZE := Vector2(1.36, 1.82)
const NORMAL_COLOR := Color("24483e")
const TEXT_COLOR := Color("ecf4df")

var panel_size := PANEL_SIZE
var _address := "127.0.0.1"
var _status_text := "Offline. Host a game or enter the host's IPv4 address."
var _state_snapshot := ""
var _canvas: CanvasLayer
var _address_edit: LineEdit
var _desktop_status: Label
var _desktop_address: Label
var _desktop_buttons: Dictionary = {}
var _world_panel: Node3D
var _world_status: Label3D
var _world_address: Label3D
var _world_ip: Label3D
var _world_buttons: Array[Dictionary] = []
var _aim: XRController3D
var _pointer: MeshInstance3D
var _hovered := -1
var _toggle_held := false
var _trigger_held := false
var _mode_button_index := -1
var _awaiting_head_pose := false
var _placement_frames := 0

func _ready() -> void:
	_create_desktop_menu()
	_create_world_menu()
	var player := _player()
	if player != null:
		var origin := player.get_node_or_null("XROrigin3D") as XROrigin3D
		if origin != null:
			_aim = XRController3D.new()
			_aim.name = "LobbyAim"
			_aim.tracker = "right_hand"
			_aim.pose = "aim"
			origin.add_child(_aim)
	refresh_status()
	_update_visibility()

func _exit_tree() -> void:
	if is_instance_valid(_aim):
		_aim.queue_free()

func _player() -> Node3D:
	return game.get("player") as Node3D if is_instance_valid(game) else null

func _is_xr() -> bool:
	var player := _player()
	return player != null and bool(player.get("xr_running"))

func _right_hand() -> XRController3D:
	return _controller(1)

func _controller(index: int) -> XRController3D:
	var player := _player()
	if player == null:
		return null
	var hands: Variant = player.get("hands")
	if hands is Array and index >= 0 and hands.size() > index:
		return hands[index] as XRController3D
	return null

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event.physical_keycode == toggle_key or event.keycode == toggle_key):
		if event.pressed and not event.echo:
			toggle()
		get_viewport().set_input_as_handled()
	elif is_open and not _is_xr() and event is InputEventMouseButton:
		# GUI still receives left clicks. Right clicks must not capture the mouse.
		if event.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()

func toggle() -> void:
	set_open(not is_open)

func set_open(value: bool) -> void:
	if is_open == value:
		return
	is_open = value
	_awaiting_head_pose = value and _is_xr()
	_placement_frames = 0
	var player := _player()
	if player != null and player.has_method("reset_tracking_history"):
		player.call("reset_tracking_history")
	_hovered = -1
	if is_open:
		refresh_status()
		if _is_xr():
			_place_world_panel()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if _address_edit != null:
				_address_edit.grab_focus()
				_address_edit.select_all()
	elif _address_edit != null:
		_address_edit.release_focus()
	var right := _right_hand()
	_trigger_held = right != null and _trigger_pressed(right)
	_update_visibility()
	_update_button_colors()

func set_status(status: String) -> void:
	_status_text = status
	_update_labels()

func refresh_status() -> void:
	if not is_instance_valid(game):
		return
	var status := _game_text("network_status", _status_text)
	var mode_notice := _game_text("play_mode_notice", "")
	if not mode_notice.is_empty():
		status += "\n" + mode_notice
	var address := _game_text("session_address", "Not available")
	var mode := _game_text("network_mode", "offline")
	var host := game.has_method("is_session_host") and bool(game.call("is_session_host"))
	var snapshot := "%s|%s|%s|%s|%s|%s|%s" % [status, address, mode, host, _is_xr(), _action_enabled("pcvr"), _action_enabled("desktop")]
	if snapshot != _state_snapshot:
		_state_snapshot = snapshot
		_status_text = status
		_update_labels()
		for action in _desktop_buttons:
			var button: Button = _desktop_buttons[action]
			button.disabled = not _action_enabled(action)
		_update_button_colors()

func _game_text(property_name: String, fallback: String) -> String:
	if not is_instance_valid(game):
		return fallback
	var value: Variant = game.get(property_name)
	return fallback if value == null or str(value).is_empty() else str(value)

func _action_enabled(action: String) -> bool:
	if action in ["pcvr", "desktop"]:
		return is_instance_valid(game) and game.has_method("can_switch_play_mode") and bool(game.call("can_switch_play_mode", action))
	if action == "account":
		return is_instance_valid(game) and game.has_method("open_account_menu")
	var mode := _game_text("network_mode", "offline")
	match action:
		"host", "join":
			return mode == "offline"
		"leave":
			return mode != "offline"
		"restart":
			return mode == "offline" or (is_instance_valid(game) and game.has_method("is_session_host") and bool(game.call("is_session_host")))
	return true

func _dispatch(action: String) -> void:
	if not _action_enabled(action):
		return
	if action.begins_with("key:"):
		_set_address(_address + action.trim_prefix("key:"))
	elif action == "backspace":
		_set_address(_address.substr(0, maxi(0, _address.length() - 1)))
	elif action == "clear":
		_set_address("")
	elif action == "close":
		set_open(false)
	elif is_instance_valid(game):
		match action:
			"host": game.call("host_session")
			"join": game.call("join_session", _address.strip_edges())
			"leave": game.call("leave_session")
			"restart": game.call("request_restart")
			"pcvr", "desktop": game.call("switch_play_mode", action)
			"account": game.call("open_account_menu")
		refresh_status()

func _set_address(value: String) -> void:
	var filtered := ""
	for character in value:
		if character in "0123456789.":
			filtered += character
	_address = filtered.left(15)
	if _address_edit != null and _address_edit.text != _address:
		_address_edit.text = _address
		_address_edit.caret_column = _address.length()
	_update_labels()

func _update_labels() -> void:
	var local_address := "This device: %s" % _game_text("session_address", "Not available")
	if _desktop_status != null:
		_desktop_status.text = _status_text
		_desktop_address.text = local_address
	if _world_status != null:
		_world_status.text = _status_text
		_world_address.text = local_address
		_world_ip.text = _address if not _address.is_empty() else "Enter host IP"
	if _mode_button_index >= 0:
		var mode_button := _world_buttons[_mode_button_index]
		mode_button["action"] = "desktop" if _is_xr() else "pcvr"
		var label: Label3D = mode_button["label"]
		label.text = "DESKTOP" if _is_xr() else "PC VR"

func _update_visibility() -> void:
	var xr := _is_xr()
	_canvas.visible = is_open and not xr
	_world_panel.visible = is_open and xr
	_pointer.visible = false

func _process(_delta: float) -> void:
	refresh_status()
	if is_open and _world_panel.visible != _is_xr():
		if _is_xr():
			_awaiting_head_pose = true
			_placement_frames = 0
			_place_world_panel()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_update_visibility()
	if not _is_xr():
		return
	if is_open and _awaiting_head_pose:
		_placement_frames += 1
		var tracker := XRServer.get_tracker("head") as XRPositionalTracker
		var pose: XRPose = tracker.get_pose("default") if tracker != null else null
		# Startup menus can open before the new camera receives its first pose.
		# Use tracking availability directly: locomotion is paused in the menu.
		if _placement_frames >= 2 and pose != null and pose.has_tracking_data:
			_place_world_panel()
			_awaiting_head_pose = false
	if game.get("xr_focused") == false:
		# Require a release after tracking/focus returns before accepting a click.
		_toggle_held = true
		_trigger_held = true
		_pointer.visible = false
		return
	var toggle_controller := _controller(toggle_hand)
	if toggle_controller != null and toggle_controller.get_has_tracking_data():
		var toggle_pressed := toggle_controller.is_button_pressed(toggle_button)
		if toggle_pressed and not _toggle_held:
			toggle()
		_toggle_held = toggle_pressed
	else:
		_toggle_held = true
	var right := _right_hand()
	if right == null or not right.get_has_tracking_data():
		_trigger_held = true
		_pointer.visible = false
		return
	var trigger := _trigger_pressed(right)
	if is_open:
		var ray := _aim if is_instance_valid(_aim) and _aim.get_has_tracking_data() else right
		var hit := _intersect_panel(ray.global_position, -ray.global_basis.z.normalized())
		var next_hover := -1
		_pointer.visible = not hit.is_empty()
		if not hit.is_empty():
			_pointer.global_position = hit["point"] + _world_panel.global_basis.z * 0.035
			next_hover = hit["button"]
		if next_hover != _hovered:
			_hovered = next_hover
			_update_button_colors()
		if trigger and not _trigger_held and _hovered >= 0:
			var action: String = _world_buttons[_hovered]["action"]
			if _action_enabled(action) and is_instance_valid(game) and game.has_method("play_ui_sound") and game.get("tutorial") != self:
				game.call("play_ui_sound", "click")
			_dispatch(action)
	_trigger_held = trigger

func _trigger_pressed(controller: XRController3D) -> bool:
	return controller.is_button_pressed("trigger_click") or controller.get_float("trigger") > 0.65

func _place_world_panel() -> void:
	var player := _player()
	if player == null:
		return
	var head := player.get("head") as Node3D
	if head == null:
		return
	var forward := -head.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	_world_panel.global_position = head.global_position + forward * 1.35 + Vector3.DOWN * 0.08
	# Label3D's front is +Z; only yaw changes so the keypad stays upright.
	_world_panel.look_at(Vector3(head.global_position.x, _world_panel.global_position.y, head.global_position.z), Vector3.UP, true)

func _intersect_panel(ray_origin: Vector3, ray_direction: Vector3) -> Dictionary:
	var local_origin := _world_panel.to_local(ray_origin)
	var local_direction := _world_panel.global_basis.inverse() * ray_direction
	if local_origin.z <= 0.0 or local_direction.z >= -0.0001:
		return {}
	var distance := -local_origin.z / local_direction.z
	if distance <= 0.0 or distance > 5.0:
		return {}
	var local_hit := local_origin + local_direction * distance
	var point := Vector2(local_hit.x, local_hit.y)
	if not Rect2(-panel_size * 0.5, panel_size).has_point(point):
		return {}
	var button := -1
	for index in range(_world_buttons.size()):
		var bounds: Rect2 = _world_buttons[index]["rect"]
		if bounds.has_point(point):
			button = index
			break
	return {"point": _world_panel.to_global(local_hit), "button": button}

func _create_desktop_menu() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "LobbyOverlay"
	_canvas.layer = 30
	add_child(_canvas)
	var root := Control.new()
	_canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.06, 0.045, 0.82)
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 420)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var heading := Label.new()
	heading.text = "PRIMAL MONKE · LOCAL MULTIPLAYER"
	heading.add_theme_font_size_override("font_size", 23)
	content.add_child(heading)
	var help := Label.new()
	help.text = "Native Quest + desktop builds on the same Wi-Fi.\nHost a game, then share this device's IP with friends."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(help)
	_desktop_address = Label.new()
	content.add_child(_desktop_address)
	_desktop_status = Label.new()
	_desktop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_status.custom_minimum_size.y = 48
	content.add_child(_desktop_status)
	var caption := Label.new()
	caption.text = "Host IPv4 address"
	content.add_child(caption)
	_address_edit = LineEdit.new()
	_address_edit.text = _address
	_address_edit.placeholder_text = "192.168.1.25"
	_address_edit.max_length = 15
	_address_edit.custom_minimum_size.y = 42
	_address_edit.text_changed.connect(_set_address)
	_address_edit.text_submitted.connect(func(_value: String): _dispatch("join"))
	content.add_child(_address_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	_desktop_button(row, "Host", "host")
	_desktop_button(row, "Join", "join")
	_desktop_button(row, "Leave", "leave")
	var second_row := HBoxContainer.new()
	second_row.add_theme_constant_override("separation", 8)
	content.add_child(second_row)
	_desktop_button(second_row, "Restart round", "restart")
	_desktop_button(second_row, "Close", "close")
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	content.add_child(mode_row)
	if OS.get_name() != "Android":
		_desktop_button(mode_row, "PC VR", "pcvr")
		_desktop_button(mode_row, "Desktop", "desktop")
	_desktop_button(mode_row, "Account", "account")
	var hint := Label.new()
	hint.text = "Tab: open / close · Headset: right B, aim + trigger"
	content.add_child(hint)

func _desktop_button(parent: HBoxContainer, text: String, action: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func(): _dispatch(action))
	parent.add_child(button)
	_desktop_buttons[action] = button

func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# A transparent pass makes the explicit overlay drawing order reliable even
	# though panel, buttons, and text intentionally ignore world depth.
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.render_priority = 1
	result.no_depth_test = true
	return result

func _world_box(center: Vector2, size: Vector2, depth: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, 0.018)
	mesh.mesh = box
	mesh.position = Vector3(center.x, center.y, depth)
	mesh.material_override = _material(color)
	mesh.material_override.render_priority = 0 if depth < -0.01 else 1
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_panel.add_child(mesh)
	return mesh

func _world_label(text: String, center: Vector2, font_size: int = 32) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = Vector3(center.x, center.y, 0.028)
	label.font_size = font_size
	label.pixel_size = 0.001
	label.modulate = TEXT_COLOR
	label.outline_modulate = Color("102a22")
	label.outline_size = 5
	label.no_depth_test = true
	label.render_priority = 2
	_world_panel.add_child(label)
	return label

func _world_button(text: String, action: String, center: Vector2, size: Vector2, color: Color = NORMAL_COLOR) -> void:
	var mesh := _world_box(center, size, 0.0, color)
	var label := _world_label(text, center, 32)
	_world_buttons.append({"action": action, "rect": Rect2(center - size * 0.5, size), "material": mesh.material_override, "label": label, "color": color})

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldLobby"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, panel_size, -0.035, Color("102a22"))
	_world_label("LOCAL MULTIPLAYER", Vector2(0, 0.65), 48)
	_world_label("Native Quest + desktop · same Wi-Fi", Vector2(0, 0.565), 25)
	_world_address = _world_label("", Vector2(0, 0.48), 27)
	_world_status = _world_label("", Vector2(0, 0.39), 29)
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_status.width = 1150.0
	_world_label("HOST IPv4 ADDRESS", Vector2(0, 0.285), 24)
	_world_box(Vector2(0, 0.215), Vector2(1.15, 0.085), -0.005, Color("1c3930"))
	_world_ip = _world_label(_address, Vector2(0, 0.215), 40)
	_world_button("HOST", "host", Vector2(-0.4, 0.08), Vector2(0.35, 0.1), Color("386d4b"))
	_world_button("JOIN", "join", Vector2(0, 0.08), Vector2(0.35, 0.1), Color("71632f"))
	_world_button("LEAVE", "leave", Vector2(0.4, 0.08), Vector2(0.35, 0.1))
	var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", ".", "⌫"]
	for index in range(keys.size()):
		var column := index % 4
		var row := index / 4
		var action: String = "backspace" if keys[index] == "⌫" else "key:" + keys[index]
		_world_button(keys[index], action, Vector2(-0.45 + column * 0.3, -0.055 - row * 0.12), Vector2(0.255, 0.1))
	_world_button("CLEAR IP", "clear", Vector2(-0.305, -0.42), Vector2(0.54, 0.1))
	_world_button("RESTART", "restart", Vector2(0.305, -0.42), Vector2(0.54, 0.1))
	_world_button("CLOSE", "close", Vector2(-0.305, -0.55), Vector2(0.54, 0.1))
	_world_button("ACCOUNT", "account", Vector2(0.305, -0.55), Vector2(0.54, 0.1))
	if OS.get_name() != "Android":
		_world_button("DESKTOP" if _is_xr() else "PC VR", "desktop" if _is_xr() else "pcvr", Vector2(0, -0.69), Vector2(1.15, 0.1))
		_mode_button_index = _world_buttons.size() - 1
	_world_label("Right B closes · Aim + trigger to select", Vector2(0, -0.815), 24)
	_pointer = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.009
	dot.height = 0.018
	_pointer.mesh = dot
	_pointer.material_override = _material(Color("d9ff99"))
	_pointer.material_override.render_priority = 3
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pointer)

func _update_button_colors() -> void:
	for index in range(_world_buttons.size()):
		var button := _world_buttons[index]
		var enabled := _action_enabled(button["action"])
		var color: Color = button["color"]
		var material: StandardMaterial3D = button["material"]
		material.albedo_color = color.lightened(0.3) if enabled and index == _hovered else (color if enabled else color.darkened(0.65))
		var label: Label3D = button["label"]
		label.modulate = TEXT_COLOR if enabled else Color("779285")
