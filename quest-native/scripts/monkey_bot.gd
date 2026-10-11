extends CharacterBody3D

var player: Node3D
var chase_position := Vector3.ZERO
var use_network_target := false
var fur: StandardMaterial3D
var tagged := false
var active := true
var home := Vector3.ZERO
var target := Vector3.ZERO
var next_choice := 0.0
var elapsed := 0.0

func reset_bot() -> void:
	global_position = home
	velocity = Vector3.ZERO
	tagged = false
	active = true
	next_choice = 0
	fur.albedo_color = Color("845634")

func tag() -> void:
	tagged = true
	fur.albedo_color = Color("ed873d")

func _physics_process(delta: float) -> void:
	if not active or tagged: return
	elapsed += delta
	var away := global_position - (chase_position if use_network_target else player.global_position)
	away.y = 0
	if elapsed >= next_choice:
		if away.length() < 4.0: target = global_position + away.normalized() * 5.0
		else: target = Vector3(randf_range(-11, 11), 0, randf_range(-11, 11))
		target.x = clampf(target.x, -12, 12)
		target.z = clampf(target.z, -12, 12)
		next_choice = elapsed + randf_range(1.0, 2.5)
	var direction := target - global_position
	direction.y = 0
	if direction.length() > 0.4:
		direction = direction.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), delta * 5)
	else: direction = Vector3.ZERO
	velocity.x = direction.x * 2.1
	velocity.z = direction.z * 2.1
	velocity.y = -1 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()
	if is_on_wall(): next_choice = 0
	if global_position.y < -5: reset_bot()
