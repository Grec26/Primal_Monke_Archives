extends SceneTree

# Real forest and menus, mocked account proof, isolated profile storage.
# No provider traffic, network listener, headset, or microphone is used here.
const DEV_ID := "481C2D175D5672D9"
const LOCAL_ACTIONS := ["teleport_hub", "teleport_treehouse", "teleport_lookout", "teleport_cave", "place_marker", "clear_markers", "map_bounds"]
const SHARED_ACTIONS := ["restart", "add_time", "freeze_bots", "tag_all", "pause_round", "bot_speed", "end_round"]
var checks := 0
var failures := 0
var scratch_prefix := ""

class MockAccount:
	extends "res://scripts/playfab_account.gd"
	var provider_id := DEV_ID
	var title_data := {"PrimalMonkeDeveloperIds": JSON.stringify([DEV_ID])}
	func _device_identity() -> String: return "PM-" + "1234567890abcdef".repeat(4)
	func _request(api: String, _payload: Dictionary, _ticket := "") -> Dictionary:
		await get_tree().process_frame
		match api:
			"LoginWithCustomID": return {"ok": true, "data": {"PlayFabId": provider_id, "SessionTicket": "test-only-session-ticket"}}
			"GetAccountInfo": return {"ok": true, "data": {"AccountInfo": {"PlayFabId": provider_id}}}
			"GetTitleData": return {"ok": true, "data": {"Data": title_data.duplicate(true)}}
			"GetUserData": return {"ok": true, "data": {"Data": {}}}
			"UpdateUserData": return {"ok": true, "data": {"DataVersion": 1}}
		return {"ok": false}

class ScratchProfile:
	extends "res://scripts/profile_state.gd"
	var storage_prefix := ""
	func _storage_path(identity: String) -> String:
		return storage_prefix + "_" + ("guest" if identity.is_empty() else identity.sha256_text().left(16)) + ".json"

func _initialize() -> void: call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func settle(frames := 4) -> void:
	for index in range(frames): await process_frame

func replace_isolated_state(game: Node3D) -> MockAccount:
	var old_account: Node = game.account
	var old_profile: Node = game.profile
	old_account.state_changed.disconnect(game._account_changed)
	old_profile.public_profile_changed.disconnect(game._profile_changed)
	game.onboarding.queue_free()
	game.onboarding = null
	var account := MockAccount.new()
	game.account = account
	game.add_child(account)
	account.state_changed.connect(game._account_changed)
	account.set_process(false)
	var profile := ScratchProfile.new()
	profile.storage_prefix = scratch_prefix
	profile.game = game
	game.profile = profile
	game.add_child(profile)
	profile.public_profile_changed.connect(game._profile_changed)
	profile.account_changed()
	old_account.queue_free()
	old_profile.queue_free()
	return account

func collider_snapshot(map: Node) -> Array:
	var snapshot: Array = []
	for body in map.solids:
		for child in body.get_children():
			if child is CollisionShape3D:
				snapshot.append([body.get_instance_id(), body.global_transform, body.collision_layer, body.collision_mask, child.disabled, child.shape.size])
	return snapshot

func collision_nodes(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children(): count += collision_nodes(child)
	return count

func visible_world_tools(menu: Node) -> Array[String]:
	var result: Array[String] = []
	for button in menu._world_buttons:
		if button.mesh.visible and button.action in menu.ACTIONS and button.action != "close": result.append(button.action)
	return result

func test_world_page(menu: Node, expected: Array, label: String) -> void:
	check(visible_world_tools(menu) == expected, label + " displays exactly eight tools")
	var fits := true
	var distinct := true
	var bounds := Rect2(-menu.panel_size * 0.5, menu.panel_size)
	for index in range(menu._world_buttons.size()):
		var button: Dictionary = menu._world_buttons[index]
		if not button.mesh.visible: continue
		fits = fits and bounds.encloses(button.rect)
		for previous in range(index):
			var other: Dictionary = menu._world_buttons[previous]
			if other.mesh.visible: distinct = distinct and not button.rect.intersects(other.rect)
		var center: Vector2 = button.rect.get_center()
		var target: Vector3 = menu._world_panel.to_global(Vector3(center.x, center.y, 0))
		var normal: Vector3 = menu._world_panel.global_basis.z
		var hit: Dictionary = menu._intersect_panel(target + normal, -normal)
		check(hit.get("button", -1) == index, label + " ray hits visible control " + button.action + " without selecting the hidden page")
	check(fits and distinct, label + " targets fit inside the panel and remain separate")

func run() -> void:
	scratch_prefix = "/tmp/primal-monke-developer-tools-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var game = load("res://forest.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.session.set_physics_process(false)
	for bot in game.bots: bot.set_physics_process(false)
	var account := replace_isolated_state(game)
	await settle()
	var tools: Node3D = game.developer_tools
	check(is_instance_valid(tools) and is_instance_valid(game.forest_map), "real forest creates local inspection helper and updated map")
	var start_position: Vector3 = game.player.global_position
	for action in LOCAL_ACTIONS + SHARED_ACTIONS + ["respawn", "diagnostics", "undefined"]:
		check(not game.developer_action_allowed(action), "unsigned root rejects " + action)
		game.developer_action(action)
		if action in LOCAL_ACTIONS:
			check(tools.perform(action) == "Developer access required.", "unsigned direct helper rejects " + action)
	check(tools.marker_count == 0 and not tools.bounds_visible and game.player.global_position == start_position and not game.diagnostics_enabled, "unsigned dispatch leaves gameplay and private visuals unchanged")

	await account.login_device()
	await settle()
	check(account.is_developer() and is_instance_valid(game.dev_menu), "mocked provider ownership and server list unlock the real developer menu")
	check(not game.developer_action_allowed("undefined") and tools.perform("undefined") == "Developer access required.", "verified developers cannot dispatch undefined tools")
	for action in SHARED_ACTIONS: check(not game.developer_action_allowed(action), "main frontend blocks shared action " + action)
	game._set_frontend_state("playing")
	game.player.tracked = true
	game.player.input_allowed = true

	for action in tools.TELEPORTS:
		var landmark: String = tools.TELEPORTS[action]
		game.player.velocity = Vector3(5, 6, 7)
		game.player.push_velocity = Vector3(1, 2, 3)
		game.player.initialized = true
		game.player.contacts = true
		game.developer_action(action)
		check(game.player.global_position.is_equal_approx(game.forest_map.landmarks[landmark]), "local teleport reaches the map's safe " + landmark + " destination")
		check(game.player.velocity == Vector3.ZERO and game.player.push_velocity == Vector3.ZERO and not game.player.initialized and not game.player.contacts, "local " + landmark + " teleport clears movement and tracking history")
	check(game.developer_status == "Moved to Cave.", "root preserves local helper feedback")
	var original_head: Vector3 = game.player.head.position
	var original_capsule: Vector3 = game.player.capsule_node.position
	game.player.xr_running = true
	game.player.head.position = Vector3(1.5, 1.65, 2.0)
	# A menu may pause locomotion before its collider catches up to a new pose.
	game.player.capsule_node.position = Vector3(0, 0.845, 0)
	for action in tools.TELEPORTS:
		var landmark: String = tools.TELEPORTS[action]
		game.developer_action(action)
		await physics_frame
		var destination: Vector3 = game.forest_map.landmarks[landmark]
		var body_position: Vector3 = game.player.capsule_node.global_position
		check(is_equal_approx(body_position.x, destination.x) and is_equal_approx(body_position.z, destination.z) and is_equal_approx(game.player.head.position.y, 1.65), "room-scale " + landmark + " teleport centers the actual body and preserves headset height")
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = game.player.capsule_node.shape
		query.transform = game.player.capsule_node.global_transform
		query.collision_mask = 1
		query.margin = 0.002
		check(game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "room-scale " + landmark + " teleport leaves the actual VR capsule clear of map geometry")
	game.developer_action("place_marker")
	var forward: Vector3 = -game.player.head.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var expected_pin: Vector3 = game.player.head.global_position + forward * 0.75
	expected_pin.y = game.player.global_position.y
	check(tools._markers.back().global_position.is_equal_approx(expected_pin), "room-scale map pins appear forward of the current body instead of the offset rig")
	tools.reset()
	game.player.xr_running = false
	game.player.head.position = original_head
	game.player.capsule_node.position = original_capsule
	game.player.reset_player()

	var before := collider_snapshot(game.forest_map)
	game.developer_action("map_bounds")
	check(tools.bounds_visible and tools.bound_shape_count > 0 and tools.bound_shape_count <= tools.MAX_BOUND_SHAPES, "bounds visualize actual map box colliders within the cost cap")
	check(tools.get_child_count() == 1 and tools._bounds.mesh is ImmediateMesh and tools._bounds.mesh.get_surface_count() == 1, "all bounds share one line mesh")
	check(collision_nodes(tools) == 0 and collider_snapshot(game.forest_map) == before, "bounds add no collision nodes and do not mutate map physics")
	game.developer_action("map_bounds")
	check(not tools.bounds_visible and tools.bound_shape_count == 0 and tools.get_child_count() == 0, "second bounds action removes the visualization")

	var fixture_bodies: Array[StaticBody3D] = []
	for index in range(tools.MAX_BOUND_SHAPES + 1):
		var body := StaticBody3D.new()
		body.collision_layer = 0
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		body.add_child(shape)
		game.forest_map.add_child(body)
		game.forest_map.solids.append(body)
		fixture_bodies.append(body)
	game.developer_action("map_bounds")
	check(tools.bound_shape_count == tools.MAX_BOUND_SHAPES and tools.get_child_count() == 1, "large map inspection caps boxes without increasing render-node count")
	tools.reset()
	for body in fixture_bodies:
		game.forest_map.solids.erase(body)
		game.forest_map.remove_child(body)
		body.queue_free()
	for index in range(12): game.developer_action("place_marker")
	check(tools.marker_count == tools.MAX_MARKERS and tools.get_child_count() == tools.MAX_MARKERS, "repeated pin placement retains only the eight most recent markers")
	check(collision_nodes(tools) == 0 and collider_snapshot(game.forest_map) == before, "pins remain local visual nodes and leave collision shapes unchanged")
	game.developer_action("clear_markers")
	check(tools.marker_count == 0 and tools.get_child_count() == 0, "clear pins immediately removes every map pin")

	game.restart()
	game.player.tracked = true
	game.player.input_allowed = true
	game.developer_action("pause_round")
	var paused_time: float = game.remaining
	game._physics_process(1.0)
	game.tag_bot(game.bots[0])
	check(game.developer_round_paused and game.remaining == paused_time and game.score == 0, "pausing a live round suppresses timer and accepted bot tags")
	var all_stopped := true
	for bot in game.bots: all_stopped = all_stopped and not bot.active
	check(all_stopped and not game.developer_action_allowed("tag_all"), "round pause stops bot simulation and disables tag-all")
	game.developer_action("pause_round")
	game._physics_process(0.5)
	check(not game.developer_round_paused and game.remaining < paused_time, "resume restarts the authoritative round timer")
	for pace in [0.65, 1.4, 1.0]:
		game.developer_action("bot_speed")
		game._physics_process(0)
		var applied := true
		for bot in game.bots: applied = applied and is_equal_approx(bot.speed_multiplier, pace)
		check(is_equal_approx(game.developer_bot_speed, pace) and applied, "bot pace cycles and applies multiplier " + str(pace))
	game.developer_action("end_round")
	check(game.finished and game.remaining == 0 and not game.developer_round_paused, "end round finishes the authoritative session and clears pause")

	game.restart()
	game.session.mode = "joining"
	game.session.phase = "playing"
	var client_state := [game.remaining, game.score, game.finished, game.developer_round_paused, game.developer_bot_speed]
	for action in SHARED_ACTIONS:
		check(not game.developer_action_allowed(action), "verified network client cannot run shared " + action)
		game.developer_action(action)
	check(client_state == [game.remaining, game.score, game.finished, game.developer_round_paused, game.developer_bot_speed], "network-client attempts cannot modify the host's round")
	game.developer_action("place_marker")
	check(tools.marker_count == 1 and game.developer_action_allowed("teleport_hub"), "developer clients retain their local map-inspection tools")
	game.session.mode = "hosting"
	game.session.phase = "lobby"
	for action in ["pause_round", "bot_speed", "end_round"]: check(not game.developer_action_allowed(action), "staging host cannot run " + action)
	game.session.phase = "playing"
	for action in ["pause_round", "bot_speed", "end_round"]: check(game.developer_action_allowed(action), "playing host is authorized for " + action)
	game.developer_action("pause_round")
	var snapshot: Dictionary = game.session.make_snapshot()
	check(snapshot.get("developer_paused") == true, "authoritative network snapshot publishes round pause")
	game.developer_round_paused = false
	game.session.mode = "joining"
	game.session.received_sequence = -1
	game.session.received_round = -1
	game.session.apply_snapshot(snapshot)
	check(game.developer_round_paused, "client snapshot applies the host's paused round state")
	game.session.mode = "offline"
	game.restart()

	game.session.mode = "hosting"
	game.session.phase = "playing"
	game.session.game_mode = "tag"
	for action in ["freeze_bots", "bot_speed", "tag_all"]: check(not game.developer_action_allowed(action), "Player Tag hides irrelevant bot control " + action)
	game.developer_action("pause_round")
	game.session.tagger_id = 1
	game.session.members = {1: tag_pose(Vector3.ZERO, true), 42: tag_pose(Vector3(0.3, 0, 0), false)}
	game.session.tag_scores = {1: 0, 42: 0}
	game.session.tag_transfers = 0
	game.session.tag_cooldown_until = 0
	game.session._advance_player_tags()
	check(game.session.tagger_id == 1 and game.session.tag_transfers == 0, "paused Player Tag cannot transfer tagger or award a score")
	game.session.mode = "offline"
	game.session.game_mode = "co_op"
	game.session.members.clear()
	game.restart()

	game.open_developer_menu()
	var menu: Node = game.dev_menu
	check(menu._desktop_buttons.size() == 17 and menu._desktop_readout.text.contains("Verified developer") and menu._desktop_readout.text.contains("Position"), "desktop workshop exposes all tools with verified-session diagnostics")
	game.developer_action("freeze_bots")
	game.developer_action("pause_round")
	game.developer_action("bot_speed")
	game.developer_action("diagnostics")
	game.developer_action("map_bounds")
	menu.refresh_status()
	check(menu._desktop_buttons.freeze_bots.text == "Resume bots" and menu._desktop_buttons.pause_round.text == "Resume round" and menu._desktop_buttons.bot_speed.text == "Bot pace: Slow" and menu._desktop_buttons.diagnostics.text == "Hide diagnostics" and menu._desktop_buttons.map_bounds.text == "Hide collision bounds", "workshop captions reflect current toggle and bot-pace states")
	game.player.xr_running = true
	menu._update_visibility()
	menu._place_world_panel()
	test_world_page(menu, menu.ROUND_PAGE, "Round VR page")
	menu._dispatch("page_next")
	test_world_page(menu, menu.MAP_PAGE, "Map VR page")
	menu._dispatch("page_previous")
	check(menu._page == 0 and menu.toggle_key == KEY_F2 and menu.toggle_hand == 0 and menu.toggle_button == "by_button", "page navigation preserves F2 and left-Y developer shortcuts")
	game.player.xr_running = false
	menu._dispatch("close")
	game._set_frontend_state("loading")
	var loading_state := [game.player.global_position, tools.marker_count, tools.bounds_visible, game.remaining, game.developer_round_paused, game.developer_bot_speed]
	for action in LOCAL_ACTIONS + SHARED_ACTIONS + ["diagnostics", "respawn", "page_next"]:
		check(not menu._action_enabled(action), "loading blocks workshop dispatch " + action)
		menu._dispatch(action)
		if action in LOCAL_ACTIONS: tools.perform(action)
	check(loading_state == [game.player.global_position, tools.marker_count, tools.bounds_visible, game.remaining, game.developer_round_paused, game.developer_bot_speed] and menu._page == 0, "loading rejects direct helper, page navigation, and all gameplay mutation")
	game._set_frontend_state("playing")
	game.restart()
	game.developer_action("place_marker")
	game.developer_action("map_bounds")
	game.developer_action("pause_round")
	game.developer_action("bot_speed")
	game.restart()
	check(tools.marker_count == 0 and not tools.bounds_visible and not game.developer_round_paused and game.developer_bot_speed == 1.0, "round restart clears local visual state and developer simulation toggles")

	game.developer_action("place_marker")
	game.developer_action("map_bounds")
	game.developer_action("pause_round")
	game.developer_action("bot_speed")
	account.title_data = {"PrimalMonkeDeveloperIds": "[]"}
	await account.refresh_permissions()
	await settle()
	check(not account.is_developer() and not is_instance_valid(game.dev_menu) and tools.marker_count == 0 and not tools.bounds_visible and not game.developer_round_paused and game.developer_bot_speed == 1.0, "server role revocation removes workshop, pins, bounds, pause, and bot pace")
	account.title_data = {"PrimalMonkeDeveloperIds": JSON.stringify([DEV_ID])}
	await account.refresh_permissions()
	game.developer_action("place_marker")
	game.developer_action("map_bounds")
	account._access_until_ms = Time.get_ticks_msec() - 1
	check(tools.perform("place_marker") == "Developer access required." and not game.developer_action_allowed("pause_round"), "expired current lease blocks direct helper and shared controls before account cleanup")
	tools._process(0)
	check(tools.marker_count == 0 and not tools.bounds_visible, "local helper independently removes private visuals immediately on lease expiry")
	account._process(0)
	await settle()
	check(not is_instance_valid(game.dev_menu), "expired account lease also removes the workshop UI")
	await account.refresh_permissions()
	game.developer_action("place_marker")
	game.developer_action("map_bounds")
	account.sign_out()
	await settle()
	check(tools.marker_count == 0 and not tools.bounds_visible and not is_instance_valid(game.dev_menu), "logout clears every local private visual and developer UI")

	game.voice.shutdown()
	game.queue_free()
	await settle()
	for name in DirAccess.get_files_at("/tmp"):
		if name.begins_with(scratch_prefix.get_file()): DirAccess.remove_absolute("/tmp/" + name)
	print("Developer tools checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)

func tag_pose(position: Vector3, pressed: bool) -> Dictionary:
	var head := position + Vector3.UP * 1.65
	return {"body": position, "head": head, "rotation": Vector3.ZERO, "left": head + Vector3(-0.3, -0.5, 0), "right": head + Vector3(0.3, -0.5, 0), "vr": false, "active": true, "tag": pressed, "seen": Time.get_ticks_msec()}
