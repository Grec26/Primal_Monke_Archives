extends SceneTree

var failures := 0
func check(condition: bool, label: String) -> void:
	if condition: print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://forest.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	game.start_solo()
	while game.frontend_state == "loading": await process_frame
	check(game.bots.size() == 5, "five native monkeys spawned")
	check(game.get_node_or_null("ForestFloor") != null, "arena and colliders created")
	var resolved: Dictionary = game.player.resolve_hand(Vector3(0, 1, 0), Vector3(0, -4, 0))
	check(resolved.contact and resolved.point.y >= 0.08, "hand sweep cannot tunnel through floor")
	for i in range(120): await physics_frame
	check(game.player.global_position.y > -0.1, "player capsule stays above floor under gravity")
	check(game.remaining < 90 and game.remaining > 85, "live native round countdown executes")
	game.player.initialized = true
	game.player.push_velocity = Vector3.ONE
	game.lobby.set_open(true)
	check(not game.player.initialized and game.player.push_velocity == Vector3.ZERO, "opening lobby clears locomotion anchors and launch momentum")
	var move_event := InputEventKey.new()
	move_event.keycode = KEY_W
	move_event.physical_keycode = KEY_W
	move_event.pressed = true
	Input.parse_input_event(move_event)
	await physics_frame
	await physics_frame
	var menu_position: Vector3 = game.player.global_position
	var menu_time: float = game.remaining
	for i in range(4): await physics_frame
	check(not game.player.input_allowed and game.player.global_position.distance_to(menu_position) < 0.001, "desktop movement stays frozen while entering lobby address")
	check(game.remaining == menu_time, "solo round pauses while lobby is open")
	move_event.pressed = false
	Input.parse_input_event(move_event)
	game.lobby.set_open(false)
	await physics_frame
	game.player.xr_running = true
	await physics_frame
	await physics_frame
	var paused_time: float = game.remaining
	for i in range(4): await physics_frame
	check(game.remaining == paused_time, "missing headset/controllers pauses round")
	var trackers: Array[XRPositionalTracker] = []
	for tracker_name in ["head", "left_hand", "right_hand"]:
		var tracker: XRPositionalTracker = XRPositionalTracker.new() if tracker_name == "head" else XRControllerTracker.new()
		tracker.name = tracker_name
		tracker.type = XRServer.TRACKER_HEAD if tracker_name == "head" else XRServer.TRACKER_CONTROLLER
		var pose_name := "default" if tracker_name == "head" else "grip"
		var position := Vector3(0, 1.65, 0) if tracker_name == "head" else Vector3(0.3, 1.0, 0.4)
		tracker.set_pose(pose_name, Transform3D(Basis.IDENTITY, position), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
	await physics_frame
	await physics_frame
	check(game.player.tracked, "mocked tracked head and grip poses activate native XR movement")
	trackers[2].invalidate_pose("grip")
	await physics_frame
	await physics_frame
	paused_time = game.remaining
	for i in range(4): await physics_frame
	check(not game.player.tracked and game.remaining == paused_time, "controller pose tracking loss pauses despite tracker being registered")
	game.player.initialized = true
	game.player.velocity = Vector3.ONE
	game.player.push_velocity = Vector3.ONE
	game.player.reset_tracking_history()
	check(not game.player.initialized and game.player.velocity == Vector3.ZERO and game.player.push_velocity == Vector3.ZERO, "recenter clears stale anchors and launch momentum")
	for tracker in trackers: XRServer.remove_tracker(tracker)
	game.player.xr_running = false
	game.restart()
	game.tag_bot(game.bots[0])
	game.tag_bot(game.bots[0])
	check(game.score == 1, "duplicate tags count once")
	for i in range(1, 5): game.tag_bot(game.bots[i])
	check(game.score == 5 and game.finished, "all monkeys tagged completes round")
	game.restart()
	check(game.score == 0 and not game.finished and game.remaining == 90, "restart resets round")
	game.remaining = 0.001
	await physics_frame
	await physics_frame
	check(game.finished and game.remaining == 0, "timeout ends round")
	game.queue_free()
	await process_frame
	print("Native smoke checks complete; failures: %s" % failures)
	quit(0 if failures == 0 else 1)
