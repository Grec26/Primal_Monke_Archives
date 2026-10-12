extends SceneTree

# Real XR nodes consume synthetic floor-relative poses. These physics checks
# protect upright floor pushes, collision anchors, and tracking recovery; they
# do not claim real headset comfort or controller hardware testing.
const Player = preload("res://scripts/arm_player.gd")
const STEP := 1.0 / 60.0

var checks := 0
var failures := 0
var world: Node3D
var player: CharacterBody3D
var trackers: Array[XRPositionalTracker] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func static_box(location: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = location
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body

func create_player() -> void:
	player = Player.new()
	player.collision_layer = 4
	player.collision_mask = 1
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 1.65
	collider.shape = capsule
	collider.position.y = 0.845
	player.add_child(collider)
	player.capsule_node = collider
	var origin := XROrigin3D.new()
	player.add_child(origin)
	var head := XRCamera3D.new()
	origin.add_child(head)
	player.head = head
	player.xr_running = true
	for side in ["left_hand", "right_hand"]:
		var hand := XRController3D.new()
		hand.tracker = side
		hand.pose = "grip"
		origin.add_child(hand)
		player.hands.append(hand)
		var visual := MeshInstance3D.new()
		world.add_child(visual)
		player.hand_visuals.append(visual)
	world.add_child(player)
	player.set_physics_process(false)

func pose(tracker: XRPositionalTracker, position: Vector3) -> void:
	tracker.set_pose("default" if tracker.type == XRServer.TRACKER_HEAD else "grip",
		Transform3D(Basis.IDENTITY, position), Vector3.ZERO, Vector3.ZERO,
		XRPose.XR_TRACKING_CONFIDENCE_HIGH)

func profile(height: float, grip_height: float, z := 0.12) -> void:
	pose(trackers[0], Vector3(0, height, 0))
	pose(trackers[1], Vector3(-0.24, grip_height, z))
	pose(trackers[2], Vector3(0.24, grip_height, z))
	await process_frame
	await physics_frame

func step(count := 1) -> void:
	for frame in range(count):
		await physics_frame
		player._physics_process(STEP)

func settle(height: float, grip_height: float) -> void:
	player.position = Vector3(0, 0.1, 0)
	player.reset_tracking_history()
	await profile(height, grip_height)
	await step(90)

func check_anchor_clear(label: String) -> void:
	for index in range(2):
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player.hand_shape
		query.transform.origin = player.anchors[index]
		query.collision_mask = 1
		query.margin = 0.0
		check(world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "%s hand %s is outside solid geometry" % [label, index + 1])

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	static_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	for tracker_name in ["head", "left_hand", "right_hand"]:
		var tracker: XRPositionalTracker = XRPositionalTracker.new() if tracker_name == "head" else XRControllerTracker.new()
		tracker.name = tracker_name
		tracker.type = XRServer.TRACKER_HEAD if tracker_name == "head" else XRServer.TRACKER_CONTROLLER
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
	create_player()
	await physics_frame
	await step()
	check(not player.tracked and not player.initialized and player.velocity == Vector3.ZERO, "missing synthetic tracking holds the VR body and clears locomotion")
	await test_upright_reach()
	await test_floor_push_and_release()
	await test_climbing_and_collision()
	await test_asymmetric_contact_reach()
	await test_tracking_and_recenter()
	for tracker in trackers: XRServer.remove_tracker(tracker)
	world.queue_free()
	await process_frame
	print("VR movement checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_upright_reach() -> void:
	for height in [1.2, 1.65, 1.8, 1.95, 2.1, 2.2]:
		var label := "%.2f m upright pose" % height
		await settle(height, height * 0.72)
		check(player.tracked and not player.contacts and player.is_on_floor(), label + " can rest hands above the floor without moving")
		var resting_position: Vector3 = player.position
		await step(6)
		check(player.position.distance_to(resting_position) < 0.002 and player.push_velocity.length() < 0.001, label + " stationary rest generates no launch momentum")
		var tracked_head: Transform3D = player.head.transform
		var tracked_grips: Array[Transform3D] = [player.hands[0].transform, player.hands[1].transform]
		await profile(height, height * 0.5)
		player.reset_tracking_history()
		await step(6)
		check(player.contacts and player.anchors[0].y >= 0.085 and player.anchors[0].y <= 0.11, label + " lowered grips reach the virtual floor without crouching")
		check(is_equal_approx(player.head.position.y, height) and player.head.position.x == 0.0 and player.head.position.z == 0.0, label + " preserves the physical headset pose and floor reference")
		check(player.hands[0].position.is_equal_approx(Vector3(-0.24, height * 0.5, 0.12)) and player.hands[1].position.is_equal_approx(Vector3(0.24, height * 0.5, 0.12)), label + " preserves grip poses for menu and editor rays")
		check(player.push_velocity.length() < 0.001 and player.velocity == Vector3.ZERO, label + " acquiring an already planted hand creates no impulse")
		check(player.head.global_position.distance_to(player.hand_visuals[0].global_position) <= Player.MAX_VIRTUAL_REACH + 0.01, label + " virtual hands stay inside the multiplayer reach envelope")
		check_anchor_clear(label)
		check(tracked_head.basis.is_equal_approx(player.head.basis) and tracked_grips[0].basis.is_equal_approx(player.hands[0].basis), label + " leaves tracked orientation intact")
		var before_push: Vector3 = player.position
		for frame in range(8):
			await profile(height, height * 0.5, 0.12 + float(frame + 1) * 0.03)
			await step()
		check(player.contacts and player.position.z < before_push.z - 0.2, label + " can move forward by sweeping planted hands")
		check(is_equal_approx(player.head.position.y, height) and player.head.position.x == 0.0 and player.head.position.z == 0.0, label + " moves without bending the physical head")
		await profile(height, height * 0.72, 0.36)
		await step()
		check(not player.contacts and player.velocity.z < -0.2, label + " releases a floor push into forward momentum")
	await settle(1.65, 1.2)
	await profile(1.65, 0.70)
	player.reset_tracking_history()
	await step(6)
	check(player.contacts and player.anchors[1].y >= 0.085, "reported standing 1.65 m head / 0.70 m hands can push the floor")
	check(player.push_velocity.length() < 0.001, "reported standing pose does not create a launch on initialization")
	await settle(1.8, 1.3)
	await profile(1.8, 0.80)
	player.reset_tracking_history()
	await step(6)
	check(player.contacts and player.anchors[1].y >= 0.085, "standing 1.80 m head / 0.80 m hands can push the floor")
	await settle(0.9, 0.65)
	await profile(0.9, 0.35)
	player.reset_tracking_history()
	await step(6)
	check(player.contacts and is_equal_approx(player.head.position.y, 0.9) and is_equal_approx((player.capsule_node.shape as CapsuleShape3D).height, 0.9), "seated pose lowers hands to the same floor with a correctly fitted body")

func test_floor_push_and_release() -> void:
	await settle(1.8, 1.3)
	await profile(1.8, 0.9)
	player.reset_tracking_history()
	await step(6)
	var start: Vector3 = player.global_position
	for frame in range(8):
		await profile(1.8, 0.9, 0.12 + float(frame + 1) * 0.03)
		await step()
	check(player.contacts and player.global_position.z < start.z - 0.2, "sweeping planted hands backward moves the upright body forward")
	check(absf(player.global_position.x) < 0.015 and player.global_position.y > -0.1, "balanced two-hand pushes stay centered and above the floor")
	check(player.push_velocity.z < -0.2 and player.push_velocity.length() <= 7.0, "floor pushes accumulate bounded release momentum")
	var before_release: Vector3 = player.position
	await profile(1.8, 1.3, 0.36)
	await step()
	check(not player.contacts and player.velocity.z < -0.2 and player.position.z < before_release.z, "lifting planted hands releases the recorded forward push")
	check(player.push_velocity == Vector3.ZERO and player.velocity.length() <= 7.2, "releasing clears old push history while limiting launch speed")
	await settle(1.8, 0.9)
	player.reset_tracking_history()
	await step(6)
	await profile(1.8, 1.3)
	await step()
	check(not player.contacts and absf(player.velocity.x) < 0.001 and absf(player.velocity.z) < 0.001 and player.velocity.y <= 0.0, "lifting a stationary planted hand never invents motion")
	await settle(1.8, 1.3)
	var initial_height: float = player.position.y
	await profile(1.8, 0.9)
	await step(4)
	await profile(1.8, 0.78)
	await step(3)
	check(player.contacts and player.position.y > initial_height + 0.15, "pressing planted hands down lifts the body using collisions")
	await profile(1.8, 1.3)
	await step()
	check(not player.contacts and player.velocity.y > 0.1, "a downward hand push releases into a jump")

func test_climbing_and_collision() -> void:
	var wall := static_box(Vector3(0, 1.8, -1.2), Vector3(5, 3.6, 0.25))
	await settle(1.8, 1.3)
	await profile(1.8, 1.3, -1.0)
	player.reset_tracking_history()
	await step(6)
	check(player.contacts and player.anchors[0].z > -1.0, "long virtual arms plant against a wall rather than starting inside it")
	check_anchor_clear("wall initialization")
	var initial_y: float = player.position.y
	for frame in range(7):
		await profile(1.8, 1.3 - float(frame + 1) * 0.025, -1.0)
		await step()
	check(player.position.y > initial_y + 0.1 and player.contacts, "pulling a planted wall hand down climbs while standing upright")
	await profile(1.8, 1.45, -0.3)
	await step()
	check(not player.contacts and player.velocity.y > 0.0, "releasing a climbing surface preserves upward push momentum")
	await settle(1.8, 1.3)
	pose(trackers[1], Vector3(-0.24, 1.3, -4.0))
	pose(trackers[2], Vector3(0.24, 1.3, -4.0))
	await process_frame
	await physics_frame
	player.reset_tracking_history()
	await step(6)
	check(player.contacts and player.anchors[0].z > -1.0, "large controller pose change cannot tunnel through a wall")
	check_anchor_clear("large controller jump")
	check(player.head.global_position.distance_to(player.virtual_hand_position(player.hands[0])) <= Player.MAX_VIRTUAL_REACH + 0.001, "extreme controller offsets remain bounded")
	wall.queue_free()
	await physics_frame

func test_asymmetric_contact_reach() -> void:
	# Independent review reproduced this failure: the right wall push moves
	# the body away from the left planted tip after the two pushes average.
	# Checking desired tips alone misses the stretched resolved outgoing pose.
	var left_wall := static_box(Vector3(-2.375, 1.5, 0), Vector3(0.2, 3, 10))
	var front_wall := static_box(Vector3(0, 1.5, -0.5), Vector3(10, 3, 0.2))
	player.position = Vector3.ZERO
	player.reset_tracking_history()
	pose(trackers[0], Vector3(0, 2.2, 0))
	pose(trackers[1], Vector3(-4, 2, 0))
	pose(trackers[2], Vector3(0, 2, -4))
	await process_frame
	await physics_frame
	var longest_resolved_reach := 0.0
	for frame in range(6):
		await step()
		for visual in player.hand_visuals:
			longest_resolved_reach = maxf(longest_resolved_reach, visual.global_position.distance_to(player.head.global_position))
		check(longest_resolved_reach <= Player.MAX_VIRTUAL_REACH + 0.0002, "asymmetric two-wall frame %s keeps resolved hands inside the virtual reach limit" % (frame + 1))
		check_anchor_clear("asymmetric two-wall frame %s" % (frame + 1))
	check(player.tracked and player.position.is_finite() and player.velocity.is_finite(), "outlier two-wall controller poses keep the body stable and tracked")
	check(player.push_velocity == Vector3.ZERO, "releasing an unreachable fresh contact cannot create launch momentum")
	check(player.head.position.is_equal_approx(Vector3(0, 2.2, 0)) and player.hands[0].position.is_equal_approx(Vector3(-4, 2, 0)) and player.hands[1].position.is_equal_approx(Vector3(0, 2, -4)), "reach correction preserves the physical XR head and grip poses")
	await profile(2.2, 1.8, 0.1)
	await step()
	check(not player.contacts and player.velocity.length() <= 0.2, "raising hands after unreachable contacts resumes gravity without an artificial launch")
	left_wall.queue_free()
	front_wall.queue_free()
	await physics_frame

func test_tracking_and_recenter() -> void:
	await settle(1.65, 0.825)
	player.velocity = Vector3(2, 3, -4)
	player.push_velocity = Vector3.ONE
	trackers[2].invalidate_pose("grip")
	await process_frame
	await physics_frame
	var frozen_position: Vector3 = player.position
	await step(6)
	check(not player.tracked and not player.contacts and not player.initialized, "one lost controller clears contact anchors and tracking history")
	check(player.velocity == Vector3.ZERO and player.push_velocity == Vector3.ZERO and player.position.is_equal_approx(frozen_position), "tracking loss holds position and cancels every launch component")
	check(not player.hand_visuals[0].visible and not player.hand_visuals[1].visible, "lost tracking hides both virtual hands")
	await profile(1.65, 0.825)
	await step(6)
	check(player.tracked and player.contacts and player.push_velocity == Vector3.ZERO, "tracking reacquisition safely seeds floor contacts with no launch")
	player.velocity = Vector3.ONE
	player.push_velocity = Vector3.ONE
	player.reset_tracking_history()
	check(not player.initialized and not player.contacts and player.velocity == Vector3.ZERO and player.push_velocity == Vector3.ZERO, "recenter invalidates contact anchors and all momentum")
	await step(6)
	check(player.tracked and player.contacts and player.push_velocity == Vector3.ZERO, "stationary hands after recenter stay planted without an impulse")
	player.input_allowed = false
	player.velocity = Vector3.ONE
	player.push_velocity = Vector3.ONE
	var menu_position: Vector3 = player.position
	await step(6)
	check(not player.tracked and player.position.is_equal_approx(menu_position) and player.velocity == Vector3.ZERO and player.push_velocity == Vector3.ZERO, "menus pause virtual locomotion as well as launch history")
	player.input_allowed = true
	await step(6)
	check(player.tracked and player.contacts and player.push_velocity == Vector3.ZERO, "closing a menu restores grounded contacts without launching")
	trackers[0].invalidate_pose("default")
	await process_frame
	await physics_frame
	await step(2)
	check(not player.tracked and player.velocity == Vector3.ZERO and not player.initialized, "lost headset pose also cancels locomotion")
