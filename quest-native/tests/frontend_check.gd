extends SceneTree

# Exercise the real scene handoff and the player's menu routes. Headless mode
# keeps these checks offline: no account provider traffic or headset is needed.
const DEV_ID := "AABBCCDDEEFF0011"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func settle(frames := 4) -> void:
	for index in range(frames): await physics_frame

func wait_state(game: Node, expected: String) -> bool:
	for index in range(120):
		if not is_instance_valid(game): return false
		if game.get("frontend_state") == expected: return true
		await process_frame
	return false

func held_key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func run() -> void:
	await test_threaded_boot()
	var game = load("res://forest.tscn").instantiate()
	root.add_child(game)
	await settle()
	await test_menu_and_solo(game)
	await test_staging_lobby(game)
	await test_load_cancellation(game)
	await test_unsolicited_disconnect(game)
	await test_cold_vr_main_menu(game)
	await test_developer_and_vr_routes(game)
	game.session.leave()
	game.queue_free()
	await process_frame
	print("Frontend checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_threaded_boot() -> void:
	var boot = load("res://boot.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	check(boot.loading._shown and boot.loading._canvas.visible, "boot presents a desktop loading screen before loading the forest")
	var deadline := Time.get_ticks_msec() + 5000
	while current_scene == boot and Time.get_ticks_msec() < deadline:
		await process_frame
	var forest = current_scene
	var opened: bool = is_instance_valid(forest) and forest != boot and forest.get("main_menu") != null
	check(opened, "threaded resource loading hands off the actual boot scene to the forest")
	if opened:
		await settle()
		check(forest.frontend_state == "main_menu" and forest.main_menu.is_open and forest.remaining == 90.0 and forest.player.head.current, "boot arrives at the main menu with an untouched round and an active player camera")
		check(not forest.account.busy and forest.account_id.is_empty(), "headless boot leaves provider sign-in idle")
	current_scene = null
	if is_instance_valid(forest): forest.queue_free()
	if is_instance_valid(boot) and boot != forest: boot.queue_free()
	await process_frame

func test_menu_and_solo(game: Node3D) -> void:
	check(game.frontend_state == "main_menu" and game.main_menu.is_open, "new world opens the main menu rather than starting a round")
	var initial_position: Vector3 = game.player.global_position
	held_key(KEY_W, true)
	game.tag_bot(game.bots[0])
	await settle(8)
	held_key(KEY_W, false)
	check(not game.player.input_allowed and game.player.global_position.distance_to(initial_position) < 0.001, "main menu blocks keyboard locomotion")
	check(game.remaining == 90.0 and game.score == 0 and not game.bots[0].tagged, "main menu cannot advance the countdown or accept direct tag calls")
	game.main_menu._dispatch("account")
	check(game.account_menu.is_open and not game.main_menu.is_open, "main-menu account action gives input to one overlay")
	game.account_menu.set_open(false)
	check(game.frontend_state == "main_menu" and game.main_menu.is_open, "closing account returns to its underlying main menu")
	game.main_menu._dispatch("solo")
	check(game.frontend_state == "loading" and game.loading_screen._shown and not game.main_menu.is_open, "solo selection presents a loading screen before play")
	game.open_account_menu()
	game.main_menu._dispatch("multiplayer")
	game.lobby._dispatch("host")
	game.tag_bot(game.bots[0])
	check(not game.account_menu.is_open and game.network_mode == "offline" and game.score == 0, "loading blocks account, room actions, and tag calls")
	check(not game.can_switch_play_mode("pcvr") and not game.can_switch_play_mode("desktop"), "loading prevents a competing play-mode switch")
	check(await wait_state(game, "playing"), "solo world preparation completes and enters play")
	await settle(8)
	check(not game.loading_screen._shown and game.player.input_allowed and game.remaining < 90.0, "completed loading restores controls and starts one live countdown")
	game.tag_bot(game.bots[0])
	var paused_time: float = game.remaining
	var paused_score: int = game.score
	game.open_main_menu()
	await settle(8)
	check(game.main_menu.is_open and game.remaining == paused_time and game.score == paused_score, "opening the main menu pauses an existing solo round without resetting it")
	game.main_menu._dispatch("resume")
	await settle(8)
	check(game.frontend_state == "playing" and not game.main_menu.is_open and game.score == paused_score and game.remaining < paused_time, "resume retains progress and continues the existing round")
	game.return_to_main_menu()
	check(game.frontend_state == "main_menu" and not game.can_resume_play(), "returning to the main menu discards the prior play destination")

func test_staging_lobby(game: Node3D) -> void:
	game.main_menu._dispatch("multiplayer")
	check(game.frontend_state == "lobby" and game.lobby.is_open and not game.main_menu.is_open, "multiplayer selection opens a staging lobby before connecting")
	var staged_time: float = game.remaining
	var staged_score: int = game.score
	game.tag_bot(game.bots[0])
	await settle(8)
	check(not game.player.input_allowed and game.remaining == staged_time and game.score == staged_score, "unhosted staging lobby blocks countdown, movement, and tags")
	check(not game.session.start_round(), "offline players cannot start a shared room")
	game.open_account_menu()
	check(game.account_menu.is_open and not game.lobby.is_open, "staging lobby can open account without overlapping input")
	game.account_menu.set_open(false)
	check(game.frontend_state == "lobby" and game.lobby.is_open, "closing account restores the staging lobby")
	game.lobby._dispatch("host")
	check(game.session.is_host() and game.session.phase == "lobby" and game.lobby.is_open, "hosting retains the staging lobby until the host starts")
	var roster: Array = game.session.room_roster()
	check(roster.size() == 1 and roster[0].get("host", false) and roster[0].get("local", false) and game.session.MAX_PLAYERS == 8, "host appears in the authoritative eight-player room roster")
	staged_time = game.remaining
	game.tag_bot(game.bots[0])
	await settle(8)
	check(game.remaining == staged_time and game.score == 0 and game.session.participant_poses().is_empty(), "hosted staging round cannot count down or tag through authority helpers")
	check(game.lobby._action_enabled("start"), "host receives the lobby start action")
	game.lobby._dispatch("start")
	check(game.frontend_state == "loading" and game.session.phase == "loading" and game.loading_screen._shown, "host start prepares the shared round through loading")
	check(await wait_state(game, "playing"), "host preparation completes the shared round")
	await settle(8)
	check(game.session.phase == "playing" and not game.lobby.is_open and game.remaining < 90.0, "playing room closes staging controls and advances the shared countdown")
	game.leave_session()
	await settle()
	check(game.network_mode == "offline" and game.frontend_state == "lobby" and game.lobby.is_open, "leaving a room disconnects and returns to the offline lobby")
	game.return_to_main_menu()

func test_load_cancellation(game: Node3D) -> void:
	game.start_solo()
	check(game.frontend_state == "loading", "solo loading starts before cancellation")
	game.return_to_main_menu()
	await settle(10)
	check(game.frontend_state == "main_menu" and game.main_menu.is_open and not game.loading_screen._shown and not game.can_resume_play(), "return-to-main cancels pending solo work without resurrecting a round")
	game.open_multiplayer_lobby()
	game.host_session()
	game.lobby._dispatch("start")
	check(game.frontend_state == "loading" and game.session.is_host(), "room loading starts before leave cancellation")
	game.leave_session()
	await settle(10)
	check(game.network_mode == "offline" and game.frontend_state == "lobby" and game.lobby.is_open and game.session.members.is_empty() and not game.loading_screen._shown, "leaving during preparation cancels the old room and returns to the offline lobby")
	check(not game.session.complete_loading(), "disconnected host cannot complete a stale shared load")
	game.return_to_main_menu()

func test_unsolicited_disconnect(game: Node3D) -> void:
	game.open_multiplayer_lobby()
	game.host_session()
	game.lobby._dispatch("start")
	for index in range(120):
		if game.session.phase == "playing": break
		await process_frame
	check(game.session.phase == "playing" and game.frontend_state == "loading", "shared round reaches playing before local loading unlocks controls")
	# This follows connection_failed/server_disconnected rather than the menu's
	# leave wrapper. The session phase is already playing, so it will not change.
	game.session.leave("Disconnected")
	await settle(8)
	check(game.network_mode == "offline" and game.frontend_state == "lobby" and game.lobby.is_open and not game.loading_screen._shown, "unsolicited disconnect during local preparation clears loading and restores the offline lobby")
	game.lobby._dispatch("main")
	game.main_menu._dispatch("solo")
	var recovered := await wait_state(game, "playing")
	await settle()
	check(recovered and game.player.input_allowed and not game.loading_screen._shown, "recovered lobby can launch solo with working controls after the disconnect")
	game.return_to_main_menu()

func test_cold_vr_main_menu(game: Node3D) -> void:
	game.return_to_main_menu()
	var head: XRCamera3D = game.player.head
	var initial_transform := head.transform
	game.player.xr_running = true
	head.position = Vector3(0, 0.1, 0)
	head.rotation = Vector3.ZERO
	await settle()
	var initial_center: Vector3 = game.main_menu._world_panel.global_position
	check(game.main_menu._world_panel.visible and not game.player.tracked and is_equal_approx(initial_center.y, head.global_position.y - 0.08), "cold VR main menu opens before headset tracking while locomotion stays paused")
	# The player remains untracked because menus disable locomotion and there
	# are no hand trackers. Placement must use the headset pose itself.
	var tracker := XRPositionalTracker.new()
	tracker.name = "head"
	tracker.type = XRServer.TRACKER_HEAD
	var tracked_transform := Transform3D(Basis.from_euler(Vector3(0, 0.75, 0)), Vector3(0.15, 2.1, -0.2))
	head.transform = tracked_transform
	tracker.set_pose("default", tracked_transform, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(tracker)
	for index in range(4): await process_frame
	var forward := -head.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var expected := head.global_position + forward * 1.35 + Vector3.DOWN * 0.08
	var actual: Vector3 = game.main_menu._world_panel.global_position
	var facing_head := (Vector3(head.global_position.x, actual.y, head.global_position.z) - actual).normalized()
	check(not game.player.input_allowed and not game.player.tracked and actual.distance_to(expected) < 0.001 and game.main_menu._world_panel.global_basis.z.dot(facing_head) > 0.999, "first valid headset pose moves the paused main menu to the player's height and facing direction")
	XRServer.remove_tracker(tracker)
	head.transform = initial_transform
	game.player.xr_running = false
	await settle()

func test_developer_and_vr_routes(game: Node3D) -> void:
	check(game.account_menu.toggle_hand == 0 and game.account_menu.toggle_button == "ax_button", "account shortcut retains left X for VR")
	game.account._ticket = "test-only-session-ticket"
	game.account.account_id = DEV_ID
	game.account._developer = true
	game.account._access_until_ms = Time.get_ticks_msec() + 30000
	game._account_changed()
	check(is_instance_valid(game.dev_menu) and game.dev_menu.toggle_hand == 0 and game.dev_menu.toggle_button == "by_button", "verified developer menu retains left Y for VR")
	game.dev_menu.set_open(true)
	check(game.dev_menu.is_open and not game.main_menu.is_open, "developer overlay receives input independently of the main menu")
	game.dev_menu.set_open(false)
	check(game.frontend_state == "main_menu" and game.main_menu.is_open, "closing developer tools restores the underlying main screen")
	for menu in [game.main_menu, game.lobby, game.account_menu, game.dev_menu]:
		menu._place_world_panel()
		var bounds := Rect2(-menu.panel_size * 0.5, menu.panel_size)
		var all_inside := true
		var all_reachable := true
		for index in range(menu._world_buttons.size()):
			var rectangle: Rect2 = menu._world_buttons[index]["rect"]
			all_inside = all_inside and bounds.encloses(rectangle)
			var center := rectangle.get_center()
			var target: Vector3 = menu._world_panel.to_global(Vector3(center.x, center.y, 0))
			var normal: Vector3 = menu._world_panel.global_basis.z
			var hit: Dictionary = menu._intersect_panel(target + normal, -normal)
			all_reachable = all_reachable and hit.get("button", -1) == index
		check(all_inside and all_reachable, "%s VR buttons fit their panel and accept front-facing controller rays" % menu.name)
	game.account.sign_out()
	await process_frame
	check(not is_instance_valid(game.dev_menu), "sign-out removes developer tools from the frontend")
