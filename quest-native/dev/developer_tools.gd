extends Node3D

# Local, reversible map inspection. These visuals never own a collider or RPC.
# The forest checks permission first; this helper checks again on direct calls.
const MAX_MARKERS := 8
const MAX_BOUND_SHAPES := 128
const TELEPORTS := {
	"teleport_hub": "hub", "teleport_treehouse": "treehouse",
	"teleport_lookout": "lookout", "teleport_cave": "cave"
}
const LOCAL_ACTIONS := ["teleport_hub", "teleport_treehouse", "teleport_lookout", "teleport_cave", "place_marker", "clear_markers", "map_bounds"]

var game: Node3D
var bounds_visible := false
var bound_shape_count := 0
var marker_count: int:
	get: return _markers.size()
var summary: String:
	get: return "Pins %s / %s · Bounds %s" % [marker_count, MAX_MARKERS, ("ON (%s)" % bound_shape_count) if bounds_visible else "OFF"]
var _markers: Array[Node3D] = []
var _bounds: MeshInstance3D

func _allowed(action: String) -> bool:
	return action in LOCAL_ACTIONS and is_instance_valid(game) and game.has_method("developer_action_allowed") and bool(game.call("developer_action_allowed", action))

func perform(action: String) -> String:
	if not _allowed(action): return "Developer access required."
	if action in TELEPORTS: return _teleport(TELEPORTS[action])
	match action:
		"place_marker": return _place_marker()
		"clear_markers":
			_clear_markers()
			return "Local map pins cleared."
		"map_bounds":
			if bounds_visible:
				_clear_bounds()
				return "Map collision bounds hidden."
			return _show_bounds()
	return "Unknown developer tool."

func _teleport(landmark: String) -> String:
	var map: Node3D = game.get("forest_map") as Node3D
	var player: Node3D = game.get("player") as Node3D
	if not is_instance_valid(map) or not is_instance_valid(player): return "Map destination unavailable."
	var landmarks: Variant = map.get("landmarks")
	if not landmarks is Dictionary or not landmarks.get(landmark) is Vector3: return "Map destination unavailable."
	var destination: Vector3 = landmarks[landmark]
	if not destination.is_finite(): return "Map destination unavailable."
	var rig_position := destination
	var head: Node3D = player.get("head") as Node3D
	if bool(player.get("xr_running")) and is_instance_valid(head):
		# Room-scale head movement can offset the body several meters from its
		# rig origin. Landmarks target the body, while retaining headset height.
		if not head.global_position.is_finite(): return "Player position unavailable."
		var offset := head.global_position - player.global_position
		offset.y = 0
		if not offset.is_finite(): return "Player position unavailable."
		rig_position -= offset
		var capsule: CollisionShape3D = player.get("capsule_node") as CollisionShape3D
		if is_instance_valid(capsule) and capsule.shape is CapsuleShape3D:
			var local_head := player.to_local(head.global_position)
			var height := clampf(local_head.y, 0.6, 2.2)
			capsule.shape.height = height
			capsule.position = Vector3(local_head.x, height * 0.5 + 0.02, local_head.z)
	player.global_position = rig_position
	if player is CharacterBody3D: player.velocity = Vector3.ZERO
	if player.has_method("reset_tracking_history"): player.call("reset_tracking_history")
	return "Moved to %s." % landmark.capitalize()

func _world_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func _place_marker() -> String:
	var player: Node3D = game.get("player") as Node3D
	if not is_instance_valid(player): return "Player unavailable."
	var head: Node3D = player.get("head") as Node3D
	var forward := -head.global_basis.z if is_instance_valid(head) else Vector3.FORWARD
	forward.y = 0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var position_to_mark := player.global_position
	if bool(player.get("xr_running")) and is_instance_valid(head):
		if not head.global_position.is_finite(): return "Player position unavailable."
		position_to_mark.x = head.global_position.x
		position_to_mark.z = head.global_position.z
	position_to_mark += forward * 0.75
	if not position_to_mark.is_finite(): return "Player position unavailable."
	if _markers.size() >= MAX_MARKERS:
		var oldest: Node3D = _markers.pop_front()
		if is_instance_valid(oldest):
			remove_child(oldest)
			oldest.queue_free()
	var marker := Node3D.new()
	marker.name = "LocalMapPin"
	add_child(marker)
	marker.global_position = position_to_mark
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.025
	pole_mesh.bottom_radius = 0.025
	pole_mesh.height = 0.7
	pole_mesh.radial_segments = 8
	pole.mesh = pole_mesh
	pole.position.y = 0.35
	pole.material_override = _world_material(Color("efb66d"))
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(pole)
	var cap := MeshInstance3D.new()
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.105
	cap_mesh.height = 0.21
	cap_mesh.radial_segments = 12
	cap_mesh.rings = 6
	cap.mesh = cap_mesh
	cap.position.y = 0.75
	cap.material_override = _world_material(Color("b4d778"))
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(cap)
	_markers.append(marker)
	return "Local map pin placed (%s / %s)." % [marker_count, MAX_MARKERS]

func _collect_shapes(map: Node3D) -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	var solids: Variant = map.get("solids")
	if not solids is Array: return shapes
	for body in solids:
		if not body is StaticBody3D or not is_instance_valid(body): continue
		for child in body.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D and not child.disabled:
				shapes.append(child)
				if shapes.size() >= MAX_BOUND_SHAPES: return shapes
	return shapes

func _show_bounds() -> String:
	var map: Node3D = game.get("forest_map") as Node3D
	if not is_instance_valid(map): return "Map bounds unavailable."
	var shapes := _collect_shapes(map)
	if shapes.is_empty(): return "No box collision bounds in this map."
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, _world_material(Color("efb66d")))
	var edges := [[0, 1], [0, 2], [0, 4], [1, 3], [1, 5], [2, 3], [2, 6], [3, 7], [4, 5], [4, 6], [5, 7], [6, 7]]
	for shape_node in shapes:
		var half_size: Vector3 = shape_node.shape.size * 0.5
		var corners: Array[Vector3] = []
		for corner in range(8):
			var sign_vector := Vector3(1 if corner & 1 else -1, 1 if corner & 2 else -1, 1 if corner & 4 else -1)
			corners.append(to_local(shape_node.global_transform * (half_size * sign_vector)))
		for edge in edges:
			lines.surface_add_vertex(corners[edge[0]])
			lines.surface_add_vertex(corners[edge[1]])
	lines.surface_end()
	_bounds = MeshInstance3D.new()
	_bounds.name = "LocalCollisionBounds"
	_bounds.mesh = lines
	_bounds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bounds)
	bound_shape_count = shapes.size()
	bounds_visible = true
	return "Showing %s map collision boxes locally." % bound_shape_count

func _clear_markers() -> void:
	for marker in _markers:
		if is_instance_valid(marker):
			remove_child(marker)
			marker.queue_free()
	_markers.clear()

func _clear_bounds() -> void:
	if is_instance_valid(_bounds):
		remove_child(_bounds)
		_bounds.queue_free()
	_bounds = null
	bound_shape_count = 0
	bounds_visible = false

func reset() -> void:
	_clear_markers()
	_clear_bounds()

func _process(_delta: float) -> void:
	# Expiry can precede the account's next refresh or a menu action.
	if (marker_count > 0 or bounds_visible) and (not is_instance_valid(game) or not bool(game.get("account_is_developer"))): reset()
