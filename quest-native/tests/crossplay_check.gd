extends SceneTree

# Real ENet peers use files only to coordinate assertion stages, never game state.
var role := ""
var signals_dir := ""
var game: Node3D
var failures := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		if argument.begins_with("--signals="): signals_dir = argument.trim_prefix("--signals=")
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if condition: print("PASS [%s]: %s" % [role, description])
	else:
		push_error("FAIL [%s]: %s" % [role, description])
		failures += 1

func signal_path(label: String) -> String:
	return signals_dir.path_join(label + ".json")

func write_signal(label: String, values: Dictionary = {}) -> void:
	var file := FileAccess.open(signal_path(label), FileAccess.WRITE)
	if file == null:
		check(false, "write coordination file " + label)
		return
	file.store_string(JSON.stringify(values))
	file.close()

func read_signal(label: String) -> Dictionary:
	var value = JSON.parse_string(FileAccess.get_file_as_string(signal_path(label)))
	return value if value is Dictionary else {}

func wait_for(predicate: Callable, description: String, seconds := 6.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.025).timeout
	var passed: bool = predicate.call()
	check(passed, description)
	return passed

func wait_signal(label: String) -> bool:
	return await wait_for(func(): return FileAccess.file_exists(signal_path(label)), "stage " + label)

func pause(seconds: float) -> void:
	await create_timer(seconds).timeout

func e_key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = pressed
	Input.parse_input_event(event)

func park_player(position: Vector3) -> void:
	game.player.global_position = position
	game.player.head.position = Vector3(0, 1.65, 0)
	game.player.tracked = true
	game.player.velocity = Vector3.ZERO
	if game.player.xr_running:
		game.player.hand_visuals[0].global_position = game.player.head.global_position + Vector3(-0.3, -0.5, 0)
		game.player.hand_visuals[1].global_position = game.player.head.global_position + Vector3(0.3, -0.5, 0)

func freeze_bots() -> void:
	for bot in game.bots: bot.set_physics_process(false)

func run() -> void:
	if signals_dir.is_empty() or role not in ["host", "client1", "client2"]:
		push_error("Use --role=host/client1/client2 --signals=/absolute/temp/path")
		quit(2)
		return
	game = load("res://forest.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	if game.has_method("start_solo"):
		game.start_solo()
		if not await wait_for(func(): return game.frontend_state == "playing", "initial solo preparation completes before networking"):
			quit(1)
			return
	game.lobby.set_open(false)
	# Client local poses remain controllable; networking and game physics stay live.
	game.player.set_physics_process(false)
	if role == "client2": game.player.xr_running = true
	park_player(Vector3(-10, 0.1, -5))
	if role == "host": await run_host()
	else: await run_client()
	e_key(false)
	game.session.leave()
	game.queue_free()
	await process_frame
	print("Crossplay %s checks complete; failures: %s" % [role, failures])
	write_signal(role + "-result", {"failures": failures})
	quit(0 if failures == 0 else 1)

func run_host() -> void:
	game.host_session()
	check(game.session.is_host(), "ENet host starts on UDP 7777")
	check(game.session.phase == "lobby" and game.session.can_start_round(), "host opens a staging lobby with an explicit start control")
	freeze_bots()
	var positions: Array[Vector3] = [Vector3.ZERO, Vector3(9, 0, 9), Vector3(-9, 0, 9), Vector3(9, 0, -9), Vector3(-9, 0, -9)]
	for i in range(game.bots.size()): game.bots[i].global_position = positions[i]
	park_player(Vector3(0, 0.1, -5))
	write_signal("host-ready")
	if not await wait_for(func(): return game.session.members.size() == 3 and game.session.avatars.size() == 2, "host handshakes with two clients and creates both avatars"):
		return
	await wait_signal("client1-ready")
	await wait_signal("client2-ready")
	var first_id := int(read_signal("client1-ready").get("id", 0))
	check(first_id > 1, "client receives a distinct nonauthority peer ID")
	check(game.session.room_roster().size() == 3 and game.session.room_roster()[0].label == "Host", "authority creates a three-player lobby roster from peer IDs")
	var waiting_time: float = game.remaining
	await pause(0.4)
	check(is_equal_approx(game.remaining, waiting_time) and game.score == 0, "lobby pauses the authoritative countdown and tags")
	check(game.session.participant_poses().is_empty() and not game.session.make_snapshot().ready, "lobby keeps participant interactions and ready state disabled")
	write_signal("lobby-check", {"remaining": waiting_time})
	await wait_signal("client1-lobby-checked")
	await wait_signal("client2-lobby-checked")
	await pause(0.1)
	check(game.session.phase == "lobby" and game.score == 0, "nonhost start and forged phase RPCs cannot leave the lobby")
	check(game.session.start_round(), "host explicitly starts the shared loading phase")
	check(game.session.phase == "loading" and game.session.participant_poses().is_empty(), "loading keeps tags disabled until the round is prepared")
	var loading_generation: int = game.session.phase_generation
	write_signal("host-started")
	await wait_for(func(): return game.session.phase == "playing", "host loading completes before authoritative play")
	check(not game.session.complete_loading(loading_generation), "completed loading cannot start a duplicate round")
	freeze_bots()
	for i in range(game.bots.size()): game.bots[i].global_position = positions[i]
	park_player(Vector3(0, 0.1, -5))
	write_signal("baseline", {"remaining": game.remaining, "round": game.session.round_id})
	await wait_signal("client1-baseline")
	await wait_signal("client2-baseline")

	# Mock a current developer lease without invoking account/provider traffic.
	# The real developer handler, game physics and ENet snapshots remain live.
	game.account.set_process(false)
	game.profile.set_process(false)
	game.account._ticket = "test-only-session-ticket"
	game.account.account_id = "AABBCCDDEEFF0011"
	game.account._developer = true
	game.account._access_until_ms = Time.get_ticks_msec() + 30000
	game.developer_action("pause_round")
	check(game.developer_round_paused, "verified host pauses the shared round through the protected developer handler")
	var developer_paused_time: float = game.remaining
	write_signal("developer-paused")
	await wait_signal("client1-pause-observed")
	await wait_signal("client2-pause-observed")
	await pause(0.25)
	check(is_equal_approx(game.remaining, developer_paused_time) and game.score == 0, "host developer pause freezes countdown and rejects nearby client tags")
	game.developer_action("pause_round")
	check(not game.developer_round_paused, "verified host resumes the authoritative round")
	game.account._developer = false
	game.account._ticket = ""
	game.account.account_id = ""
	game.account._access_until_ms = 0
	game.account.set_process(true)
	game.profile.set_process(true)
	write_signal("developer-resumed")
	await wait_signal("client1-resume-observed")
	await wait_signal("client2-resume-observed")

	write_signal("far-tag")
	await wait_signal("client1-far-input")
	await wait_for(func(): return game.session.members.get(first_id, {}).get("tag", false), "far-away E input reaches host over ENet")
	await pause(0.2)
	check(game.score == 0 and not game.bots[0].tagged, "host rejects far-away tag")
	write_signal("far-done")
	await wait_signal("client1-far-done")

	write_signal("near-tag")
	await wait_for(func(): return game.score == 1 and game.bots[0].tagged, "nearby client E tags one shared authoritative bot")
	write_signal("near-done")
	await wait_signal("client1-near-done")
	await wait_signal("client2-near-done")
	write_signal("vr-tag")
	await wait_for(func(): return game.score == 2 and game.bots[1].tagged, "VR client's nearby hand tags a second shared authoritative bot")
	write_signal("vr-done")
	await wait_signal("client1-vr-done")
	await wait_signal("client2-vr-done")
	await wait_for(func(): return game.session.members.get(first_id, {}).get("body", Vector3.INF).distance_to(Vector3(-10, 0.1, -5)) < 0.1, "host accepts client's normal parked pose before rejection checks")

	var before_round: int = game.session.round_id
	write_signal("forge", {"round": before_round})
	await wait_signal("client1-forge-sent")
	await pause(0.25)
	var current_pose: Dictionary = game.session.members.get(first_id, {})
	check(game.score == 2 and game.session.round_id == before_round and not game.finished, "nonhost restart and forged authority snapshots cannot change host round")
	check(current_pose.has("body") and current_pose.body.distance_to(Vector3(-10, 0.1, -5)) < 0.1, "invalid bounds and stale-round poses cannot overwrite accepted player pose: %s" % current_pose.get("body", "missing"))
	write_signal("forge-done")
	await wait_signal("client1-forge-done")
	await wait_signal("client2-forge-done")

	game.request_restart()
	check(game.score == 0 and not game.finished and game.session.round_id > before_round, "host restart resets score and advances round generation")
	write_signal("restart", {"round": game.session.round_id})
	await wait_signal("client1-restart")
	await wait_signal("client2-restart")
	game.lobby.set_open(true)
	await pause(0.1)
	check(not game.player.input_allowed, "host menu pauses local movement")
	var before_time: float = game.remaining
	await pause(0.4)
	check(game.remaining < before_time - 0.25, "active clients keep authoritative timer running while host menu is open")
	write_signal("host-menu-done")
	await wait_signal("client1-menu-observed")
	await wait_signal("client2-menu-observed")

	write_signal("leave-client1")
	await wait_signal("client1-left")
	await wait_for(func(): return game.session.members.size() == 2 and game.session.avatars.size() == 1, "host removes disconnected member and remote avatar")
	await wait_signal("client2-peer-left")
	game.session.leave()
	write_signal("host-closed")
	await wait_signal("client2-host-left")
	check(game.session.mode == "offline" and game.session.avatars.is_empty(), "host leave returns to clean solo mode")
	write_signal("all-done")

func run_client() -> void:
	if not await wait_signal("host-ready"): return
	game.join_session("127.0.0.1")
	if not await wait_for(func(): return game.session.mode == "connected", "matching client completes protocol handshake"):
		return
	game.lobby.set_open(false)
	park_player(Vector3(-10, 0.1, -5))
	await wait_for(func(): return game.session.avatars.size() == 2, "client renders host and other client avatars")
	write_signal(role + "-ready", {"id": game.multiplayer.get_unique_id()})
	await wait_signal("lobby-check")
	check(game.session.phase == "lobby" and not game.session.can_start_round(), "client joins the waiting lobby without host start permission")
	check(game.session.room_roster().size() == 3 and game.session.room_roster()[0].label == "Host", "client receives the authoritative three-player roster")
	check(is_equal_approx(game.remaining, float(read_signal("lobby-check").get("remaining", -1))) and game.score == 0, "waiting client receives the paused countdown")
	check(not game.player.input_allowed and game.session.participant_poses().is_empty(), "waiting lobby blocks local movement and tagging")
	if role == "client1":
		check(not game.session.start_round() and not game.session.complete_loading(), "client cannot invoke host start or loading completion")
		var forged_phase := {"sequence": 999999, "round": game.session.received_round, "remaining": 0.0, "score": 5, "finished": true, "bots": [], "players": {}, "phase": "playing", "ready": true}
		print("Expected permission rejection follows: nonauthority peer attempts host-only phase RPC.")
		for peer_id in game.multiplayer.get_peers(): game.session._phase_snapshot.rpc_id(peer_id, forged_phase)
	await pause(0.2)
	check(game.session.phase == "lobby" and game.score == 0, "forged phase snapshot cannot start a client round")
	write_signal(role + "-lobby-checked")
	await wait_signal("host-started")
	await wait_for(func(): return game.session.phase == "playing" and game.player.input_allowed, "host start releases client play after loading")
	park_player(Vector3(-10, 0.1, -5))
	await wait_signal("baseline")
	await pause(0.2)
	var baseline := read_signal("baseline")
	check(game.session.received_round == int(baseline.get("round", -1)), "shared round generation matches host")
	check(game.remaining <= float(baseline.get("remaining", 0)) + 0.2 and game.remaining > float(baseline.get("remaining", 0)) - 1.0, "shared timer tracks host snapshots")
	await wait_for(func(): return game.bots[0].global_position.distance_to(Vector3.ZERO) < 0.1 and game.bots[1].global_position.distance_to(Vector3(9, 0, 9)) < 0.1, "shared bot positions converge to host snapshots")
	check(game.score == 0 and not game.bots[0].tagged, "clients begin with shared untagged bots")
	check(game.session.avatars.values().all(func(avatar): return avatar.visible), "both remote player avatars are active and visible")
	if role == "client1": check(game.session.avatars.values().any(func(avatar): return avatar.target.get("vr", false)), "desktop client renders a VR participant avatar")
	else: check(game.session.avatars.values().all(func(avatar): return not avatar.target.get("vr", false)), "VR client renders both desktop participant avatars")
	write_signal(role + "-baseline")

	await wait_signal("developer-paused")
	await wait_for(func(): return game.developer_round_paused, "client receives host pause through the actual ENet snapshot")
	var paused_countdown: float = game.remaining
	if role == "client1":
		park_player(Vector3(0, 0.1, 0))
		e_key(true)
	await pause(0.3)
	check(is_equal_approx(game.remaining, paused_countdown) and game.score == 0, "paused client sees stable timer and no accepted nearby tag")
	game.developer_action("pause_round")
	check(game.developer_round_paused and not game.developer_action_allowed("pause_round"), "client direct developer call cannot resume the host's paused round")
	e_key(false)
	park_player(Vector3(-10, 0.1, -5))
	write_signal(role + "-pause-observed")
	await wait_signal("developer-resumed")
	await wait_for(func(): return not game.developer_round_paused and game.remaining < paused_countdown, "client receives host resume and running timer")
	write_signal(role + "-resume-observed")

	if role == "client1":
		await wait_signal("far-tag")
		park_player(Vector3(12, 0.1, 0))
		e_key(true)
		await process_frame
		check(Input.is_physical_key_pressed(KEY_E), "test injects real desktop E input")
		write_signal("client1-far-input")
		await wait_signal("far-done")
		e_key(false)
		await pause(0.1)
		check(game.score == 0, "far-away tag leaves client shared score unchanged")
		write_signal("client1-far-done")
		await wait_signal("near-tag")
		park_player(Vector3(0, 0.1, 0))
		e_key(true)
	await wait_signal("near-done")
	await wait_for(func(): return game.score == 1 and game.bots[0].tagged, "client receives nearby shared bot tag and score")
	e_key(false)
	park_player(Vector3(-10, 0.1, -5))
	await pause(0.15)
	write_signal(role + "-near-done")
	await wait_signal("vr-tag")
	if role == "client2":
		park_player(Vector3(9, 0.1, 9))
		game.player.hand_visuals[1].global_position = Vector3(9, 0.7, 9)
	await wait_signal("vr-done")
	await wait_for(func(): return game.score == 2 and game.bots[1].tagged, "both clients receive VR hand tag and shared second score")
	park_player(Vector3(-10, 0.1, -5))
	await pause(0.15)
	write_signal(role + "-vr-done")

	await wait_signal("forge")
	if role == "client1":
		game.request_restart()
		check(game.session.status.contains("Only the host"), "client restart control reports host authority")
		game.session.set_physics_process(false)
		var pose_round: int = game.session.received_round
		game.session._submit_pose.rpc_id(1, pose_round, Vector3(50, 0, 0), Vector3(50, 1.65, 0), Vector3.ZERO, Vector3(50, 1, 0), Vector3(50, 1, 0), false, true, true)
		game.session._submit_pose.rpc_id(1, pose_round - 1, Vector3.ZERO, Vector3(0, 1.65, 0), Vector3.ZERO, Vector3(0, 1, 0), Vector3(0, 1, 0), false, true, true)
		var forged := {"sequence": 999999, "round": pose_round + 1000, "remaining": 0.0, "score": 5, "finished": true, "bots": [], "players": {}}
		print("Expected permission rejection follows: nonauthority peer attempts host-only RPC.")
		for peer_id in game.multiplayer.get_peers(): game.session._snapshot.rpc_id(peer_id, forged)
		write_signal("client1-forge-sent")
	await wait_signal("forge-done")
	check(game.score == 2 and game.session.received_round == int(read_signal("forge").get("round", -1)) and not game.finished, "forged authority snapshots cannot advance client state")
	if role == "client1": game.session.set_physics_process(true)
	write_signal(role + "-forge-done")

	await wait_signal("restart")
	var expected_round := int(read_signal("restart").get("round", -1))
	await wait_for(func(): return game.session.received_round == expected_round and game.score == 0, "client receives host restart and cleared shared score")
	check(not game.finished and game.bots.all(func(bot): return not bot.tagged), "host restart clears all client bot tags")
	check(game.player.global_position.distance_to(Vector3(0, 0.1, -5)) < 0.1, "host restart resets local client spawn")
	write_signal(role + "-restart")
	await wait_signal("host-menu-done")
	check(game.session.mode == "connected" and game.player.input_allowed, "host menu leaves remote client play enabled")
	write_signal(role + "-menu-observed")

	if role == "client1":
		await wait_signal("leave-client1")
		game.leave_session()
		check(game.session.mode == "offline" and game.session.avatars.is_empty(), "client leave clears online state and avatars")
		write_signal("client1-left")
	else:
		await wait_signal("client1-left")
		await wait_for(func(): return game.session.avatars.size() == 1, "remaining client removes departed remote avatar")
		write_signal("client2-peer-left")
		await wait_signal("host-closed")
		await wait_for(func(): return game.session.mode == "offline", "host disconnect returns remaining client to solo")
		check(game.session.avatars.is_empty() and game.score == 0 and not game.finished, "host disconnect clears avatars and resets solo round")
		write_signal("client2-host-left")
	await wait_signal("all-done")
