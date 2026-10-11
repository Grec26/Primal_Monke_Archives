extends "res://scripts/lobby_menu.gd"

# The forest creates this menu only after developer access has been verified.
# Every action is also checked by the forest, including host/client authority.
const ACTIONS := ["restart", "add_time", "freeze_bots", "tag_all", "respawn", "diagnostics", "close"]

var _desktop_readout: Label
var _world_readout: Label3D

func _init() -> void:
	toggle_key = KEY_F2
	toggle_hand = 0
	toggle_button = "by_button"
	_status_text = "Developer tools ready."

func set_open(value: bool) -> void:
	var was_open := is_open
	if value and not _action_enabled("diagnostics"):
		return
	if value and not is_open and is_instance_valid(game) and game.has_method("on_developer_menu_open"):
		game.call("on_developer_menu_open")
	super.set_open(value)
	if was_open and not value and is_instance_valid(game) and game.has_method("on_developer_menu_closed"):
		game.call("on_developer_menu_closed")
	if value and not _is_xr() and _desktop_buttons.has("close"):
		var close_button: Button = _desktop_buttons["close"]
		close_button.grab_focus()

func _action_enabled(action: String) -> bool:
	if action not in ACTIONS:
		return false
	if action == "close":
		return true
	if not is_instance_valid(game) or not game.has_method("developer_action_allowed"):
		return false
	var allowed: Variant = game.call("developer_action_allowed", action)
	return allowed is bool and allowed

func _dispatch(action: String) -> void:
	if action == "close":
		set_open(false)
	elif _action_enabled(action) and game.has_method("developer_action"):
		game.call("developer_action", action)
		refresh_status()

func refresh_status() -> void:
	if not is_instance_valid(game):
		return
	_status_text = _game_text("developer_status", "Developer tools ready.")
	_update_labels()
	for action in _desktop_buttons:
		var button: Button = _desktop_buttons[action]
		button.disabled = not _action_enabled(action)
	_update_button_colors()

func _update_labels() -> void:
	var mode := "Quest VR" if OS.get_name() == "Android" else "PCVR"
	if not _is_xr():
		mode = "Desktop"
	var network_mode := _game_text("network_mode", "offline")
	var role := "Offline"
	if network_mode != "offline":
		role = "Host" if game.has_method("is_session_host") and bool(game.call("is_session_host")) else "Client"
	var player := _player()
	var tracking := "Ready" if player != null and bool(player.get("tracked")) else "Paused"
	var remaining: Variant = game.get("remaining") if is_instance_valid(game) else null
	var score: Variant = game.get("score") if is_instance_valid(game) else null
	var time_text := "%ss" % ceili(float(remaining)) if remaining != null else "—"
	var score_text := str(score) if score != null else "—"
	var readout := "%s · %s · %s FPS\nTracking: %s\nRound: %s remaining · %s / 5 tagged" % [mode, role, Engine.get_frames_per_second(), tracking, time_text, score_text]
	if _desktop_status != null:
		_desktop_status.text = _status_text
		_desktop_readout.text = readout
	if _world_status != null:
		_world_status.text = _status_text
		_world_readout.text = readout

func _create_desktop_menu() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "DeveloperOverlay"
	_canvas.layer = 31
	add_child(_canvas)
	var root := Control.new()
	_canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.045, 0.035, 0.86)
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 450)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var heading := Label.new()
	heading.text = "PRIMAL MONKE · DEVELOPER TOOLS"
	heading.add_theme_font_size_override("font_size", 24)
	content.add_child(heading)
	var access := Label.new()
	access.text = "Developer access · native Quest, desktop, and PCVR"
	content.add_child(access)
	_desktop_readout = Label.new()
	_desktop_readout.custom_minimum_size.y = 70
	content.add_child(_desktop_readout)
	_desktop_status = Label.new()
	_desktop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_status.custom_minimum_size.y = 44
	content.add_child(_desktop_status)
	var rows := [
		[["Restart round", "restart"], ["Add time", "add_time"]],
		[["Freeze / resume bots", "freeze_bots"], ["Tag all monkeys", "tag_all"]],
		[["Respawn me", "respawn"], ["Toggle diagnostics", "diagnostics"]]
	]
	for buttons in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		content.add_child(row)
		for details in buttons:
			_desktop_button(row, details[0], details[1])
	var close_row := HBoxContainer.new()
	content.add_child(close_row)
	_desktop_button(close_row, "Close", "close")
	var authority := Label.new()
	authority.text = "Round controls require host or offline authority.\nF2: open / close · Headset: left Y, right aim + trigger"
	content.add_child(authority)

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldDeveloperMenu"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, PANEL_SIZE, -0.035, Color("102a22"))
	_world_label("DEVELOPER TOOLS", Vector2(0, 0.65), 48)
	_world_label("Developer access · native testing controls", Vector2(0, 0.56), 25)
	_world_readout = _world_label("", Vector2(0, 0.43), 27)
	_world_status = _world_label("", Vector2(0, 0.285), 28)
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_status.width = 1150.0
	_world_button("RESTART ROUND", "restart", Vector2(-0.305, 0.13), Vector2(0.54, 0.11), Color("386d4b"))
	_world_button("ADD TIME", "add_time", Vector2(0.305, 0.13), Vector2(0.54, 0.11))
	_world_button("FREEZE / RESUME", "freeze_bots", Vector2(-0.305, -0.02), Vector2(0.54, 0.11))
	_world_button("TAG ALL", "tag_all", Vector2(0.305, -0.02), Vector2(0.54, 0.11))
	_world_button("RESPAWN ME", "respawn", Vector2(-0.305, -0.17), Vector2(0.54, 0.11))
	_world_button("DIAGNOSTICS", "diagnostics", Vector2(0.305, -0.17), Vector2(0.54, 0.11))
	_world_button("CLOSE", "close", Vector2(0, -0.37), Vector2(1.15, 0.11))
	var authority := _world_label("Round controls require\nhost or offline authority.", Vector2(0, -0.53), 26)
	authority.width = 1100.0
	_world_label("Left Y closes · Right aim + trigger to select", Vector2(0, -0.675), 24)
	_pointer = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.009
	dot.height = 0.018
	_pointer.mesh = dot
	_pointer.material_override = _material(Color("d9ff99"))
	_pointer.material_override.render_priority = 3
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pointer)
