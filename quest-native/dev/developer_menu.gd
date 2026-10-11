extends "res://scripts/lobby_menu.gd"

const MenuTheme = preload("res://scripts/menu_theme.gd")
const ACTIONS := ["restart", "add_time", "freeze_bots", "tag_all", "respawn", "diagnostics", "pause_round", "bot_speed", "end_round", "teleport_hub", "teleport_treehouse", "teleport_lookout", "teleport_cave", "place_marker", "clear_markers", "map_bounds", "close"]
const ROUND_PAGE := ["restart", "add_time", "pause_round", "end_round", "freeze_bots", "bot_speed", "tag_all", "respawn"]
const MAP_PAGE := ["teleport_hub", "teleport_treehouse", "teleport_lookout", "teleport_cave", "place_marker", "clear_markers", "map_bounds", "diagnostics"]
const CAPTIONS := {
	"restart": "Restart round", "add_time": "Add 30 seconds", "pause_round": "Pause round", "end_round": "End round",
	"freeze_bots": "Freeze bots", "bot_speed": "Bot pace: Normal", "tag_all": "Tag all bots", "respawn": "Respawn me",
	"teleport_hub": "Go to hub", "teleport_treehouse": "Go to treehouse", "teleport_lookout": "Go to lookout", "teleport_cave": "Go to cave",
	"place_marker": "Place map pin", "clear_markers": "Clear map pins", "map_bounds": "Show collision bounds", "diagnostics": "Show diagnostics"
}
const WORLD_CAPTIONS := {
	"restart": "RESTART ROUND", "add_time": "ADD 30 SEC", "pause_round": "PAUSE ROUND", "end_round": "END ROUND",
	"freeze_bots": "FREEZE BOTS", "bot_speed": "BOT PACE: NORMAL", "tag_all": "TAG ALL BOTS", "respawn": "RESPAWN ME",
	"teleport_hub": "HUB", "teleport_treehouse": "TREEHOUSE", "teleport_lookout": "LOOKOUT", "teleport_cave": "CAVE",
	"place_marker": "PLACE PIN", "clear_markers": "CLEAR PINS", "map_bounds": "SHOW BOUNDS", "diagnostics": "DIAGNOSTICS: OFF"
}

var _desktop_readout: Label
var _world_readout: Label3D
var _world_page: Label3D
var _page := 0
var _grids: Array[GridContainer] = []

func _init() -> void:
	toggle_key = KEY_F2
	toggle_hand = 0
	toggle_button = "by_button"
	panel_size = Vector2(1.8, 2.2)
	_status_text = "Developer tools ready."

func set_open(value: bool) -> void:
	var was_open := is_open
	if value and not _action_enabled("diagnostics"): return
	if value and not is_open and is_instance_valid(game) and game.has_method("on_developer_menu_open"):
		game.call("on_developer_menu_open")
	super.set_open(value)
	if was_open and not value and is_instance_valid(game) and game.has_method("on_developer_menu_closed"):
		game.call("on_developer_menu_closed")
	if value and not _is_xr() and _desktop_buttons.has("close"):
		_desktop_buttons.close.grab_focus()

func _action_enabled(action: String) -> bool:
	if action == "close": return true
	if action not in ACTIONS and action not in ["page_previous", "page_next"]: return false
	if not is_instance_valid(game) or not game.has_method("developer_action_allowed"): return false
	var allowed: Variant = game.call("developer_action_allowed", "diagnostics" if action.begins_with("page_") else action)
	return allowed is bool and allowed

func _dispatch(action: String) -> void:
	if action == "close":
		set_open(false)
		return
	if not _action_enabled(action): return
	if action in ["page_previous", "page_next"]:
		_page = 1 - _page
		_hovered = -1
		_refresh_world_page()
	elif game.has_method("developer_action"):
		game.call("developer_action", action)
	refresh_status()

func refresh_status() -> void:
	if not is_instance_valid(game): return
	_status_text = _game_text("developer_status", "Developer tools ready.")
	_update_labels()
	for action in _desktop_buttons:
		var button: Button = _desktop_buttons[action]
		button.disabled = not _action_enabled(action)
		if action in CAPTIONS: button.text = _caption(action, false)
	for entry in _world_buttons:
		if entry.action in WORLD_CAPTIONS: entry.label.text = _caption(entry.action, true)
	_update_button_colors()

func _caption(action: String, world: bool) -> String:
	var caption: String = WORLD_CAPTIONS.get(action, action) if world else CAPTIONS.get(action, action)
	match action:
		"pause_round": caption = "Resume round" if bool(game.get("developer_round_paused")) else "Pause round"
		"freeze_bots": caption = "Resume bots" if bool(game.get("developer_bots_frozen")) else "Freeze bots"
		"bot_speed":
			var speed: Variant = game.get("developer_bot_speed")
			var pace := "Slow" if speed != null and float(speed) < 0.9 else ("Fast" if speed != null and float(speed) > 1.1 else "Normal")
			caption = "Bot pace: " + pace
		"map_bounds":
			var tools: Node = game.get("developer_tools") as Node
			var shown := is_instance_valid(tools) and bool(tools.get("bounds_visible"))
			caption = ("Hide bounds" if shown else "Show bounds") if world else ("Hide collision bounds" if shown else "Show collision bounds")
		"diagnostics":
			var shown := bool(game.get("diagnostics_enabled"))
			caption = ("Diagnostics: ON" if shown else "Diagnostics: OFF") if world else ("Hide diagnostics" if shown else "Show diagnostics")
	return caption.to_upper() if world else caption

func _update_labels() -> void:
	var mode := "Quest VR" if OS.get_name() == "Android" else "PCVR"
	if not _is_xr(): mode = "Desktop"
	var network_mode := _game_text("network_mode", "offline")
	var role := "Offline"
	if network_mode != "offline": role = "Host" if game.has_method("is_session_host") and bool(game.call("is_session_host")) else "Client"
	var player := _player()
	var tracking := "Ready" if player != null and bool(player.get("tracked")) else "Paused"
	var position_text := str(player.global_position.snapped(Vector3.ONE * 0.1)) if player != null else "Unavailable"
	var remaining: Variant = game.get("remaining")
	var score: Variant = game.get("score")
	var time_text := "%ss" % ceili(float(remaining)) if remaining != null else "—"
	var score_text := str(score) if score != null else "—"
	var tools: Node = game.get("developer_tools") as Node
	var map: Node = game.get("forest_map") as Node
	var map_text := str(map.get("map_summary")) if is_instance_valid(map) else "Forest map"
	var tools_text := str(tools.get("summary")) if is_instance_valid(tools) else "Pins 0 / 8 · Bounds OFF"
	var round_text := "Paused" if bool(game.get("developer_round_paused")) else "Running"
	if bool(game.get("finished")): round_text = "Finished"
	var readout := "Verified developer · %s · %s · %s FPS\nTracking: %s · Position %s\nRound: %s remaining · %s / 5 tagged · %s\n%s\n%s" % [mode, role, Engine.get_frames_per_second(), tracking, position_text, time_text, score_text, round_text, map_text, tools_text]
	if _desktop_status != null:
		_desktop_status.text = _status_text
		_desktop_readout.text = readout
	if _world_status != null:
		_world_status.text = _status_text
		_world_readout.text = "%s · %s · %s FPS · Tracking %s\nPosition %s · Round %s\n%s" % [mode, role, Engine.get_frames_per_second(), tracking, position_text, time_text, tools_text]

func _section(parent: VBoxContainer, heading: String, help: String, actions: Array) -> void:
	MenuTheme.label(parent, heading, 22, MenuTheme.CREAM)
	MenuTheme.label(parent, help, 14, MenuTheme.MUTED, true)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	_grids.append(grid)
	for action in actions: MenuTheme.button(self, grid, CAPTIONS[action], action)

func _create_desktop_menu() -> void:
	var frame := MenuTheme.desktop_frame(self, "DeveloperOverlay", 31, 800)
	_canvas = frame.canvas
	var content: VBoxContainer = frame.content
	MenuTheme.label(content, "VERIFIED DEVELOPER", 13, MenuTheme.GREEN)
	MenuTheme.label(content, "Forest workshop", 34, MenuTheme.CREAM, true)
	MenuTheme.label(content, "Test the round, explore the map, and inspect your session.", 16, MenuTheme.MUTED, true)
	_desktop_readout = MenuTheme.label(content, "", 15, MenuTheme.CREAM, true)
	_desktop_status = MenuTheme.label(content, "", 16, MenuTheme.ORANGE, true)
	_section(content, "Round controls", "Shared controls are available offline or to the session host during play.", ["restart", "add_time", "pause_round", "end_round", "freeze_bots", "bot_speed", "tag_all"])
	_section(content, "Map testing", "Travel and map pins affect your player and your view. Pins are limited to eight.", ["teleport_hub", "teleport_treehouse", "teleport_lookout", "teleport_cave", "place_marker", "clear_markers", "map_bounds"])
	_section(content, "Diagnostics", "Check tracking, frame rate, position, and collision geometry.", ["respawn", "diagnostics"])
	MenuTheme.button(self, content, "Back to game", "close", true)
	MenuTheme.label(content, "F2 opens or closes · Headset: left Y, right aim + trigger", 13, MenuTheme.MUTED, true)
	for button in _desktop_buttons.values():
		button.pressed.connect(func():
			if is_instance_valid(game) and game.has_method("play_ui_sound"): game.call("play_ui_sound", "click"))
	var viewport := get_viewport()
	var adapt := func():
		for grid in _grids:
			if is_instance_valid(grid): grid.columns = 1 if viewport.get_visible_rect().size.x < 660 else 2
	viewport.size_changed.connect(adapt)
	tree_exiting.connect(func():
		if viewport.size_changed.is_connected(adapt): viewport.size_changed.disconnect(adapt))
	adapt.call()

func _refresh_world_page() -> void:
	var visible_actions: Array = ROUND_PAGE if _page == 0 else MAP_PAGE
	for action in ROUND_PAGE + MAP_PAGE: _set_world_action_visible(action, action in visible_actions)
	if _world_page != null: _world_page.text = "ROUND CONTROLS · 1 / 2" if _page == 0 else "MAP TESTING · 2 / 2"

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldDeveloperMenu"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, panel_size, -0.035, MenuTheme.FOREST)
	_world_label("FOREST WORKSHOP", Vector2(0, 0.93), 38)
	_world_label("Verified developer · Local inspection + host tools", Vector2(0, 0.82), 22)
	_world_readout = _world_label("", Vector2(0, 0.67), 23)
	_world_readout.width = 1100
	_world_status = _world_label("", Vector2(0, 0.43), 22)
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_status.width = 1000
	_world_page = _world_label("", Vector2(0, 0.25), 23)
	for page in [ROUND_PAGE, MAP_PAGE]:
		for index in range(page.size()):
			var action: String = page[index]
			var center := Vector2(-0.375 if index % 2 == 0 else 0.375, 0.095 - floori(index / 2.0) * 0.19)
			_world_button(WORLD_CAPTIONS[action], action, center, Vector2(0.69, 0.14), Color("284d3b"))
			_world_buttons.back().label.font_size = 24
	_world_button("PREVIOUS", "page_previous", Vector2(-0.54, -0.72), Vector2(0.45, 0.13))
	_world_button("NEXT", "page_next", Vector2(0, -0.72), Vector2(0.45, 0.13))
	_world_button("CLOSE", "close", Vector2(0.54, -0.72), Vector2(0.45, 0.13), Color("386d4b"))
	_world_label("Round controls require host or offline authority.", Vector2(0, -0.89), 22)
	_world_label("Left Y closes · Right aim + trigger to select", Vector2(0, -1.0), 21)
	MenuTheme.world_text(_world_panel)
	_refresh_world_page()
	_pointer = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.009
	dot.height = 0.018
	_pointer.mesh = dot
	_pointer.material_override = _material(MenuTheme.GREEN)
	_pointer.material_override.render_priority = 3
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pointer)
