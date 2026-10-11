extends SceneTree

# These checks use the live physics world, rather than a second copy of the
# generation formulas. No headset or network account is needed.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func capsule_clear(game: Node3D, origin: Vector3, radius := 0.22, height := 1.65) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = origin + Vector3.UP * (height * 0.5 + 0.02)
	query.collision_mask = 1
	query.margin = 0.002
	return game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func ground_hit(game: Node3D, location: Vector3, max_drop := 1.0) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(location, location - Vector3.UP * max_drop, 1)
	return game.get_world_3d().direct_space_state.intersect_ray(query)

func route_treads(game: Node3D, nodes: Array, label: String) -> void:
	var previous_top := 0.0
	for index in range(nodes.size()):
		var step := nodes[index] as StaticBody3D
		var shape := step.get_node("CollisionShape3D").shape as BoxShape3D
		var top := step.global_position.y + shape.size.y * 0.5
		var stand := step.global_position + Vector3(0, shape.size.y * 0.5 + 0.1, -0.15)
		var surface := ground_hit(game, stand, 0.2)
		check(not surface.is_empty() and surface.collider == step, "%s step %s is an actual standing surface" % [label, index + 1])
		check(capsule_clear(game, stand, 0.22, 2.0), "%s step %s has two meters of standing clearance" % [label, index + 1])
		check(top - previous_top <= 0.401 and top > previous_top, "%s step %s is reachable with a desktop jump" % [label, index + 1])
		if index > 0:
			var previous := nodes[index - 1] as StaticBody3D
			check(previous.global_position.distance_to(step.global_position) < 0.8, "%s step %s is within a short forward jump" % [label, index + 1])
		previous_top = top

func walk_and_jump(start: Vector3, goal: Vector3) -> bool:
	# A physical capsule follows the shipping desktop speed, gravity, and
	# jump impulse. This catches routes whose individually clear steps still
	# cannot be traversed together by the actual movement model.
	var walker := CharacterBody3D.new()
	walker.collision_layer = 0
	walker.collision_mask = 1
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 1.65
	collider.shape = capsule
	collider.position.y = 0.845
	walker.add_child(collider)
	walker.position = start
	root.add_child(walker)
	await physics_frame
	var reached := false
	for frame in range(420):
		await physics_frame
		var delta := 1.0 / float(Engine.physics_ticks_per_second)
		var offset := Vector3(goal.x - walker.position.x, 0, goal.z - walker.position.z)
		var horizontal := offset.normalized() * minf(4.0, offset.length() * 6.0)
		walker.velocity.x = horizontal.x
		walker.velocity.z = horizontal.z
		if walker.is_on_floor() and offset.length() > 0.18: walker.velocity.y = 4.5
		else: walker.velocity.y -= 9.8 * delta
		walker.move_and_slide()
		if offset.length() < 0.18 and absf(walker.position.y - goal.y) < 0.15 and walker.is_on_floor():
			reached = true
			break
	if not reached:
		print("Route stopped at %s; goal %s" % [walker.position, goal])
	walker.queue_free()
	await process_frame
	return reached

func run() -> void:
	var game = load("res://forest.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	var map: Node3D = game.get("forest_map")
	check(is_instance_valid(map), "forest scene installs the shared expanded map")
	if not is_instance_valid(map):
		game.queue_free()
		quit(1)
		return
	check(map.get("solid_count") <= 150 and map.get("solid_count") > 60, "expanded arena stays within its 150 solid budget")
	var solids: Array = map.get("solids")
	var materials: Dictionary = {}
	for solid: StaticBody3D in solids:
		var mesh := solid.get_node("Surface") as MeshInstance3D
		materials[mesh.material_override.get_instance_id()] = true
	check(materials.size() < 18 and materials.size() < solids.size() / 3, "forest surfaces share a small material palette")
	check(game.get_node_or_null("ForestFloor") != null, "floor keeps the established root scene path")
	check(capsule_clear(game, Vector3(0, 0.1, -5)), "original player spawn is clear of all new geometry")
	for index in range(5):
		check(capsule_clear(game, Vector3(float(index - 2) * 2.8, 0.1, 5), 0.35, 1.2), "monkey home %s remains clear" % (index + 1))
	for index in range(12):
		check(map.get_node_or_null("Tree%s" % index) != null and map.get_node_or_null("Branch%s" % index) != null, "original tree ring keeps tree and climbable branch %s" % index)
	check(map.get_node_or_null("LowRock") != null and map.get_node_or_null("HighRock") != null, "original rock chase route is preserved")
	var destinations: Dictionary = map.get("landmarks")
	for key in ["hub", "treehouse", "lookout", "cave"]:
		check(destinations.has(key) and destinations[key] is Vector3, "%s landmark exposes a player origin" % key)
		if not destinations.has(key): continue
		var destination: Vector3 = destinations[key]
		check(absf(destination.x) < 15.0 and absf(destination.z) < 15.0, "%s landmark remains inside the bounded arena" % key)
		check(capsule_clear(game, destination), "%s teleport has standing body and head clearance" % key)
		var ground := ground_hit(game, destination, 0.3)
		check(not ground.is_empty() and destination.y - ground.position.y <= 0.2, "%s teleport lands just above a real floor" % key)
	var tree_steps: Array = []
	for index in range(7): tree_steps.append(map.get_node("ClimbStep%s" % index))
	route_treads(game, tree_steps, "Treehouse")
	var lookout_steps: Array = []
	for index in range(9): lookout_steps.append(map.get_node("LookoutStep%s" % index))
	route_treads(game, lookout_steps, "Lookout")
	check(await walk_and_jump(Vector3(7.3, 0.1, 3.05), Vector3(7.3, 3.04, 8.55)), "desktop capsule can jump the full treehouse stair route")
	check(await walk_and_jump(Vector3(12, 0.1, 0.35), Vector3(12, 3.04, 7.4)), "desktop capsule can jump the full lookout stair route")
	for stand in [Vector3(7.3, 3.16, 8.55), Vector3(7.3, 3.16, 10.35), Vector3(2.0, 3.05, 11.1), Vector3(12, 3.16, 11.0)]:
		check(capsule_clear(game, stand) and not ground_hit(game, stand, 0.3).is_empty(), "canopy connector %s is a clear resting point" % stand)
	for index in range(18):
		var stand := Vector3(2.7 + index * 0.6, 3.16, 11.7)
		check(capsule_clear(game, stand) and not ground_hit(game, stand, 0.4).is_empty(), "canopy loop section %s has a continuous floor and clearance" % (index + 1))
	for index in range(7):
		var origin := Vector3(-7.8 - index * 0.75, 0.1, -8.5)
		check(capsule_clear(game, origin) and not ground_hit(game, origin, 0.3).is_empty(), "cave entrance and interior section %s are walkable" % (index + 1))
	var cave_roof := PhysicsRayQueryParameters3D.create(Vector3(-12, 1.9, -8.5), Vector3(-12, 5, -8.5), 1)
	var roof_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(cave_roof)
	check(not roof_hit.is_empty() and roof_hit.collider.name == "CaveRoof" and roof_hit.position.y >= 2.8, "cave roof provides generous real overhead clearance")
	var hand: Dictionary = game.player.resolve_hand(Vector3(-13.5, 1.2, -8.5), Vector3(-16, 1.2, -8.5))
	check(hand.contact and hand.point.x > -14.75, "VR hand sweeps stop against the cave wall")
	hand = game.player.resolve_hand(Vector3(14.25, 1.3, 7.8), Vector3(14.25, 1.3, 9.2))
	check(hand.contact, "lookout climbing pole supports physical arm movement")
	for side in [Vector3(0, 1, 17), Vector3(0, 1, -17), Vector3(17, 1, 0), Vector3(-17, 1, 0)]:
		var center := Vector3(0, 1, 0)
		var boundary: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(center, side, 1))
		check(not boundary.is_empty(), "arena remains bounded toward %s" % side)
	for name in ["HubWayfinding", "CaveTrailSign", "LookoutTrailSign", "TreehouseTrailSign"]:
		var sign := map.get_node_or_null(name) as Label3D
		check(sign != null and not sign.text.is_empty(), "%s gives visible route directions" % name)
	print("Map budget: %s solids, %s shared materials" % [solids.size(), materials.size()])
	game.queue_free()
	await process_frame
	print("Map checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)
