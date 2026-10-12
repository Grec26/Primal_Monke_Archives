extends CharacterBody3D

const MAX_VIRTUAL_REACH := 2.3
const SHOULDER_DROP := 0.20
const HORIZONTAL_ARM_SCALE := 1.35
const LOWERED_ARM_SCALE := 2.05
const PALM_REACH := 0.12

var head: XRCamera3D
var hands: Array[XRController3D] = []
var hand_visuals: Array[MeshInstance3D] = []
var capsule_node: CollisionShape3D
var xr_running := false
var input_allowed := true
var tracked := false
var contacts := false
var initialized := false
var anchors: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var last_grip_positions: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var push_velocity := Vector3.ZERO
var hand_shape := SphereShape3D.new()
var desktop_yaw := 0.0
var desktop_pitch := 0.0
var mouse_sensitivity := 1.0
var invert_y := false
var look_fov := 75.0:
	set(value):
		look_fov = value
		apply_desktop_settings()

func _ready() -> void:
	hand_shape.radius = 0.09

func apply_desktop_settings() -> void:
	# Headset projection comes from the XR runtime, rather than this PC preference.
	if not xr_running and is_instance_valid(head):
		head.fov = look_fov

func reset_player() -> void:
	global_position = Vector3(0, 0.1, -5)
	reset_tracking_history()

func reset_tracking_history() -> void:
	velocity = Vector3.ZERO
	push_velocity = Vector3.ZERO
	initialized = false
	contacts = false

func virtual_reach() -> float:
	return clampf(head.position.y + 0.15, 1.5, MAX_VIRTUAL_REACH)

func virtual_hand_position(hand: XRController3D) -> Vector3:
	# The controller is a grip, rather than the tip of a gorilla's long arm.
	# Extend lowered hands so an upright player can plant them on the floor.
	# Leave tracked head/grip transforms intact for rendering and menu rays.
	var shoulder := head.global_position + Vector3.DOWN * SHOULDER_DROP
	var offset := hand.global_position - shoulder
	var lowered := maxf(0.0, -offset.y)
	offset.x *= HORIZONTAL_ARM_SCALE
	offset.z *= HORIZONTAL_ARM_SCALE
	if offset.y < 0.0: offset.y *= LOWERED_ARM_SCALE
	offset.y -= PALM_REACH * clampf(lowered / 0.45, 0.0, 1.0)
	return head.global_position + (shoulder + offset - head.global_position).limit_length(virtual_reach())

func _clear_sweep_point(query: PhysicsShapeQueryParameters3D, anchor: Vector3, motion: Vector3, blocked: float) -> Vector3:
	var safe := 0.0
	query.motion = Vector3.ZERO
	for attempt in range(14):
		var middle := (safe + blocked) * 0.5
		query.transform.origin = anchor + motion * middle
		if get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): safe = middle
		else: blocked = middle
	return anchor + motion * safe

func resolve_hand(anchor: Vector3, desired: Vector3, seeding := false) -> Dictionary:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hand_shape
	query.transform = Transform3D(Basis.IDENTITY, anchor)
	query.motion = desired - anchor
	query.collision_mask = 1
	query.margin = 0.002
	var result := get_world_3d().direct_space_state.cast_motion(query)
	if result[0] < 1.0:
		var fraction := maxf(0.0, result[0] - 0.003 / maxf(query.motion.length(), 0.003))
		var motion := query.motion
		var point := anchor + motion * fraction
		query.motion = Vector3.ZERO
		query.transform.origin = point
		# A long sweep's reported safe fraction can still overlap a thin
		# surface. Confirm it and refine only that uncommon imprecise hit.
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			point = _clear_sweep_point(query, anchor, motion, fraction)
		return {"point": point, "contact": true}
	query.transform.origin = desired
	query.motion = Vector3.ZERO
	query.margin = 0.007
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		if seeding:
			# A clear tip inside the sticking margin should anchor at the tip,
			# not at the head. The latter would lift the body on every recenter.
			query.margin = 0.002
			var point := desired
			if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				point = _clear_sweep_point(query, anchor, desired - anchor, 1.0)
			return {"point": point, "contact": true}
		return {"point": anchor, "contact": true}
	return {"point": desired, "contact": false}

func _physics_process(delta: float) -> void:
	if not xr_running:
		apply_desktop_settings()
		tracked = input_allowed
		if not input_allowed:
			velocity = Vector3.ZERO
			return
		var movement := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W): movement.z -= 1
		if Input.is_physical_key_pressed(KEY_S): movement.z += 1
		if Input.is_physical_key_pressed(KEY_A): movement.x -= 1
		if Input.is_physical_key_pressed(KEY_D): movement.x += 1
		movement = movement.normalized().rotated(Vector3.UP, desktop_yaw)
		velocity.x = movement.x * 4.0
		velocity.z = movement.z * 4.0
		if is_on_floor() and Input.is_physical_key_pressed(KEY_SPACE): velocity.y = 4.5
		else: velocity.y -= 9.8 * delta
		head.rotation = Vector3(desktop_pitch, desktop_yaw, 0)
		move_and_slide()
		return
	var head_tracker := XRServer.get_tracker("head") as XRPositionalTracker
	var head_pose: XRPose = head_tracker.get_pose("default") if head_tracker != null else null
	tracked = input_allowed and head_pose != null and head_pose.has_tracking_data and hands[0].get_has_tracking_data() and hands[1].get_has_tracking_data()
	for visual in hand_visuals: visual.visible = tracked
	if not tracked:
		initialized = false
		contacts = false
		velocity = Vector3.ZERO
		push_velocity = Vector3.ZERO
		return
	var height := clampf(head.position.y, 0.6, 2.2)
	var capsule := capsule_node.shape as CapsuleShape3D
	capsule.height = height
	capsule_node.position = Vector3(head.position.x, height * 0.5 + 0.02, head.position.z)
	var desired: Array[Vector3] = []
	var grips_changed := false
	for i in range(2):
		desired.append(virtual_hand_position(hands[i]))
		if not hands[i].position.is_equal_approx(last_grip_positions[i]): grips_changed = true
		last_grip_positions[i] = hands[i].position
	var fresh_tracking := not initialized
	if fresh_tracking:
		# Starting directly at a tip inside the floor/wall makes it an invalid
		# stationary anchor. Sweep outwards from the head to seed a clear tip.
		for i in range(2): anchors[i] = resolve_hand(head.global_position, desired[i], true).point
		initialized = true
	var resolved: Array[Dictionary] = []
	var correction := Vector3.ZERO
	var contact_count := 0
	for i in range(2):
		var result := resolve_hand(anchors[i], desired[i])
		resolved.append(result)
		if result.contact:
			correction += Vector3(result.point) - desired[i]
			contact_count += 1
	var before := global_position
	if contact_count > 0:
		move_and_collide(correction / float(contact_count))
		if fresh_tracking:
			# Tracking reacquisition or recentering is not an arm push.
			push_velocity = Vector3.ZERO
		else:
			if not contacts: push_velocity = Vector3.ZERO
			# Collision solver settling is not a controller stroke. Test the
			# raw grip's local pose, which body motion does not alter.
			var stroke_velocity := (global_position - before) / delta if grips_changed else Vector3.ZERO
			push_velocity = push_velocity.lerp(stroke_velocity, 1.0 - exp(-18.0 * delta))
		velocity = Vector3.ZERO
	else:
		if contacts:
			velocity = (push_velocity * 1.15).limit_length(7.0)
			push_velocity = Vector3.ZERO
		velocity.y -= 9.8 * delta
		move_and_slide()
	contacts = false
	var released_unreachable := false
	for i in range(2):
		anchors[i] = resolved[i].point
		if not resolved[i].contact: anchors[i] += global_position - before
		# Averaging two different surface pushes can move the head away from
		# one planted hand. Release that anchor instead of stretching the arm.
		# Sweep to a new tip so the replacement stays outside solid geometry.
		if anchors[i].distance_to(head.global_position) > MAX_VIRTUAL_REACH + 0.0001:
			anchors[i] = resolve_hand(head.global_position, virtual_hand_position(hands[i]), true).point
			resolved[i].contact = false
			released_unreachable = true
		contacts = contacts or bool(resolved[i].contact)
		hand_visuals[i].global_position = anchors[i]
	if released_unreachable and not contacts: push_velocity = Vector3.ZERO
	if global_position.y < -10: reset_player()

func _unhandled_input(event: InputEvent) -> void:
	if xr_running or not input_allowed: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_mouse_look(event.relative)

func _apply_mouse_look(relative: Vector2) -> void:
	desktop_yaw -= relative.x * 0.004 * mouse_sensitivity
	var pitch_direction := 1.0 if invert_y else -1.0
	desktop_pitch = clampf(desktop_pitch + relative.y * 0.004 * mouse_sensitivity * pitch_direction, -1.2, 1.2)
