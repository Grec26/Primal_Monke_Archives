extends CharacterBody3D

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
var push_velocity := Vector3.ZERO
var hand_shape := SphereShape3D.new()
var desktop_yaw := 0.0
var desktop_pitch := 0.0

func _ready() -> void:
	hand_shape.radius = 0.09

func reset_player() -> void:
	global_position = Vector3(0, 0.1, -5)
	reset_tracking_history()

func reset_tracking_history() -> void:
	velocity = Vector3.ZERO
	push_velocity = Vector3.ZERO
	initialized = false
	contacts = false

func resolve_hand(anchor: Vector3, desired: Vector3) -> Dictionary:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hand_shape
	query.transform = Transform3D(Basis.IDENTITY, anchor)
	query.motion = desired - anchor
	query.collision_mask = 1
	query.margin = 0.002
	var result := get_world_3d().direct_space_state.cast_motion(query)
	if result[0] < 1.0:
		var fraction := maxf(0.0, result[0] - 0.003 / maxf(query.motion.length(), 0.003))
		return {"point": anchor + query.motion * fraction, "contact": true}
	query.transform.origin = desired
	query.motion = Vector3.ZERO
	query.margin = 0.007
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return {"point": anchor, "contact": true}
	return {"point": desired, "contact": false}

func _physics_process(delta: float) -> void:
	if not xr_running:
		tracked = true
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
	for hand in hands:
		var offset := hand.global_position - head.global_position
		desired.append(head.global_position + offset.limit_length(1.5))
	if not initialized:
		for i in range(2): anchors[i] = desired[i]
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
		push_velocity = push_velocity.lerp((global_position - before) / delta, 1.0 - exp(-18.0 * delta))
		velocity = Vector3.ZERO
	else:
		if contacts: velocity = (push_velocity * 1.15).limit_length(7.0)
		velocity.y -= 9.8 * delta
		move_and_slide()
	contacts = contact_count > 0
	for i in range(2):
		anchors[i] = resolved[i].point
		if not resolved[i].contact: anchors[i] += global_position - before
		hand_visuals[i].global_position = anchors[i]
	if global_position.y < -10: reset_player()

func _unhandled_input(event: InputEvent) -> void:
	if xr_running: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		desktop_yaw -= event.relative.x * 0.004
		desktop_pitch = clampf(desktop_pitch - event.relative.y * 0.004, -1.2, 1.2)
