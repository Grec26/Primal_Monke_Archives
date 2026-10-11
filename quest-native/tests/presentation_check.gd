extends SceneTree

# Exercise state transitions and real desktop/world controls without network
# access, account requests, player movement or persistent preference writes.
var checks := 0
var failures := 0

class FakeGame:
	extends Node3D
	var forest_map: Node3D
	var player: Node3D
	var frontend_state := "main_menu"
	var frontend_status := "Ready to explore."
	var account_status := "Signed out"
	var account_is_developer := false
	var profile_summary := "Test Monke · Level 3"
	var network_mode := "offline"
	var play_mode_notice := ""
	var creator_calls := 0
	func can_open_map_creator() -> bool:
		return frontend_state != "loading" and network_mode == "offline"
	func open_map_creator() -> void:
		creator_calls += 1
	func can_open_developer_menu() -> bool:
		return account_is_developer and frontend_state != "loading"
	func open_developer_menu() -> void:
		pass
	func can_switch_play_mode(_mode: String) -> bool:
		return frontend_state != "loading"
	func switch_play_mode(_mode: String) -> void:
		pass
	func can_resume_play() -> bool:
		return false
	func resume_play() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func collision_count(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children(): count += collision_count(child)
	return count

func run() -> void:
	var game := FakeGame.new()
	game.forest_map = Node3D.new()
	game.add_child(game.forest_map)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	game.add_child(world)
	var sun := DirectionalLight3D.new()
	game.add_child(sun)
	root.add_child(game)
	var initial_collisions := collision_count(game)
	var presentation = load("res://scripts/game_presentation.gd").new()
	presentation.game = game
	game.add_child(presentation)
	await process_frame
	check(world.environment.background_mode == Environment.BG_SKY and world.environment.sky.sky_material is ProceduralSkyMaterial, "presentation creates an original forest sky")
	check(not sun.shadow_enabled and world.environment.fog_density <= 0.01, "forest atmosphere keeps shadows disabled and fog light for headset rendering")
	var plants := game.forest_map.get_node("ForestGroundPlants") as MultiMeshInstance3D
	check(plants != null and plants.multimesh.instance_count == 48, "boundary vegetation uses a bounded instanced draw")
	check(collision_count(game) == initial_collisions, "presentation never changes map collision or physics")
	check(not presentation._canvas.visible and presentation._root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD begins hidden and cannot capture gameplay input")
	presentation.update_hud({"visible": true, "remaining": 90.0, "score": 2, "profile": "Test Monke · Level 3", "title": "FOREST CHASE"})
	check(presentation._canvas.visible and presentation._timer.text == "1:30", "solo HUD shows the live round clock")
	check(presentation._objective.text.begins_with("2 / 5") and is_equal_approx(presentation._progress.value, 40.0), "solo objective and progress reflect actual tagged monkeys")
	check(presentation._profile.text == "Test Monke · Level 3", "HUD displays the current player's profile")
	presentation.update_hud({"visible": true, "remaining": 0.1, "score": 999, "title": "ROUND COMPLETE"})
	check(presentation._timer.text == "0:01" and presentation._objective.text.begins_with("5 / 5"), "clock rounds remaining fractions up and display values are bounded")
	presentation.update_hud({"visible": true, "remaining": -10.0, "mode": "tag", "network": "client", "tag_summary": "Player 2 is it"})
	check(presentation._timer.text == "0:00" and presentation._objective.text == "Player 2 is it", "Player Tag uses the authoritative tag summary and a nonnegative clock")
	check(presentation._badge.text == "MULTIPLAYER · CLIENT", "multiplayer HUD distinguishes the client connection")
	presentation.update_hud({"visible": true, "remaining": 45.0, "mode": "tag", "tag_summary": "You are it", "status": "Round paused by developer"})
	check(is_equal_approx(presentation._progress.value, 50.0) and presentation._status.text == "Round paused by developer", "tag timer and pause notices follow the forest snapshot")
	presentation.update_hud({"visible": true, "mode": "map_playtest", "map_name": "My Canopy", "diagnostics": "Position (0, 1, 0)"})
	check(presentation._title.text == "MAP PLAYTEST" and presentation._timer.text.is_empty() and not presentation._progress.visible, "custom-map playtesting has an untimed HUD")
	check(presentation._objective.text.contains("My Canopy") and presentation._objective.text.contains("No timer or XP"), "map playtest names the local map and explains its free-exploration behavior")
	check(not presentation._footer.visible and presentation._diagnostics.visible, "playtest uses the creator's return notice while keeping developer diagnostics")
	presentation.update_hud({"visible": true, "mode": "co_op"})
	check(presentation._footer.visible and presentation._footer.text.contains("F1: menu"), "returning to a regular round restores the desktop control footer")
	presentation.update_hud({"visible": false})
	check(not presentation._canvas.visible, "frontend and settings can suppress the presentation HUD")
	var menu = load("res://scripts/main_menu.gd").new()
	menu.game = game
	game.add_child(menu)
	await process_frame
	check(menu._desktop_buttons.has("map_creator") and menu._action_enabled("map_creator"), "Main offers an enabled desktop map creator while offline")
	menu._desktop_buttons.map_creator.pressed.emit()
	check(game.creator_calls == 1, "desktop map creator forwards to the forest's guarded entry point")
	game.network_mode = "client"
	menu.refresh_status()
	menu._dispatch("map_creator")
	check(menu._desktop_buttons.map_creator.disabled and game.creator_calls == 1, "map creation cannot modify a connected multiplayer map")
	game.network_mode = "offline"
	game.frontend_state = "loading"
	menu.refresh_status()
	menu._dispatch("map_creator")
	check(not menu._action_enabled("map_creator") and game.creator_calls == 1, "loading blocks map creator dispatch")
	game.frontend_state = "main_menu"
	game.account_is_developer = true
	menu.refresh_status()
	var bounds := Rect2(-menu.panel_size * 0.5, menu.panel_size)
	var fit := true
	var separate := true
	var creator_index := -1
	var developer_visible := false
	for index in range(menu._world_buttons.size()):
		var button: Dictionary = menu._world_buttons[index]
		if button.action == "map_creator": creator_index = index
		if button.action == "developer": developer_visible = button.mesh.visible
		if not button.mesh.visible: continue
		fit = fit and bounds.encloses(button.rect)
		for other in range(index):
			var previous: Dictionary = menu._world_buttons[other]
			if previous.mesh.visible: separate = separate and not button.rect.intersects(previous.rect)
	check(fit and separate and developer_visible, "updated Main VR controls retain private developer access and fit without overlapping")
	check(creator_index >= 0, "VR Main includes the same local map creator destination")
	if creator_index >= 0:
		var center: Vector2 = menu._world_buttons[creator_index].rect.get_center()
		var target: Vector3 = menu._world_panel.to_global(Vector3(center.x, center.y, 0))
		var normal: Vector3 = menu._world_panel.global_basis.z
		var hit: Dictionary = menu._intersect_panel(target + normal, -normal)
		check(hit.get("button", -1) == creator_index, "controller ray reaches the map creator's visible target")
	var loading = load("res://scripts/loading_screen.gd").new()
	game.add_child(loading)
	loading.show_loading("Preparing map", 0.4)
	check(is_equal_approx(loading._desktop_progress.value, 40.0) and loading._desktop_tip.text.contains("hands"), "loading screen reports actual preparation progress and a useful movement tip")
	loading.show_error("Connection interrupted")
	check(loading._retry.visible and not loading._desktop_progress.visible and loading._desktop_tip.text.contains("connection"), "loading failure replaces progress with a concrete retry hint")
	game.queue_free()
	await process_frame
	print("Presentation checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)
