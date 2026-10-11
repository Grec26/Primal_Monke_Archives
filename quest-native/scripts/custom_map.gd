extends Node3D

const MapDocument = preload("res://scripts/map_document.gd")

var document: RefCounted:
	set(value):
		if document != null and document.changed.is_connected(_document_changed): document.changed.disconnect(_document_changed)
		document = value
		if document != null:
			document.changed.connect(_document_changed)
			if is_inside_tree(): apply_data(document.data)
var selected_id := -1
var solids: Array[StaticBody3D] = []
var status := ""
var _objects: Dictionary = {}
var _materials: Dictionary = {}
var _selection: MeshInstance3D
var _content: Node3D
var _applied: Dictionary = {}
var _active := true

func _ready() -> void:
	if document != null: apply_data(document.data)

func _document_changed() -> void:
	if is_inside_tree(): apply_data(document.data)

func set_active(value: bool) -> void:
	_active = value
	visible = value
	for solid in solids: solid.collision_layer = 1 if value else 0

func apply_data(value: Dictionary) -> bool:
	var validator := MapDocument.new()
	var clean: Dictionary = validator.validate_data(value)
	if clean.is_empty():
		status = validator._validation_error
		return false
	if is_instance_valid(_content):
		remove_child(_content)
		_content.queue_free()
	solids.clear()
	_objects.clear()
	_content = Node3D.new()
	_content.name = "CustomGeometry"
	add_child(_content)
	_applied = clean
	# The root's ForestFloor stays in place. The custom arena owns only its
	# four fixed walls and the editable objects.
	_box("NorthBoundary", Vector3(0, 3, 16), Vector3(34, 7, 1), Color("66776b"), _content)
	_box("SouthBoundary", Vector3(0, 3, -16), Vector3(34, 7, 1), Color("66776b"), _content)
	_box("EastBoundary", Vector3(16, 3, 0), Vector3(1, 7, 32), Color("66776b"), _content)
	_box("WestBoundary", Vector3(-16, 3, 0), Vector3(1, 7, 32), Color("66776b"), _content)
	for object in clean.objects: _create_object(object)
	_selection = MeshInstance3D.new()
	_selection.name = "SelectionOutline"
	_selection.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var selection_material := StandardMaterial3D.new()
	selection_material.albedo_color = Color("f4d986")
	selection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection.material_override = selection_material
	_content.add_child(_selection)
	set_selected(selected_id)
	status = "Rendered %s objects." % clean.objects.size()
	return true

func set_selected(id: int) -> void:
	selected_id = id if _objects.has(id) else -1
	if not is_instance_valid(_selection): return
	_selection.visible = selected_id >= 0
	if selected_id < 0: return
	var object: Dictionary = _objects[id]
	var position: Vector3 = MapDocument.vector(object.position)
	var half: Vector3 = MapDocument.vector(object.size) * 0.5 + Vector3.ONE * 0.035
	_selection.position = position
	_selection.rotation.y = deg_to_rad(object.yaw)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners: Array[Vector3] = []
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]: corners.append(half * Vector3(x, y, z))
	for pair in [[0, 1], [0, 2], [0, 4], [1, 3], [1, 5], [2, 3], [2, 6], [3, 7], [4, 5], [4, 6], [5, 7], [6, 7]]:
		mesh.surface_add_vertex(corners[pair[0]])
		mesh.surface_add_vertex(corners[pair[1]])
	mesh.surface_end()
	_selection.mesh = mesh

func _create_object(object: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Object_%s_%s" % [object.id, object.kind]
	root.position = MapDocument.vector(object.position)
	root.rotation.y = deg_to_rad(object.yaw)
	root.set_meta("map_object_id", object.id)
	_content.add_child(root)
	_objects[object.id] = object.duplicate(true)
	var size: Vector3 = MapDocument.vector(object.size)
	var color: Color = MapDocument.COLORS[object.color]
	if object.kind == "tree":
		var trunk_size := Vector3(size.x * 0.3, size.y * 0.72, size.z * 0.3)
		_poly("Trunk", Vector3(0, -size.y * 0.14, 0), trunk_size, Color("735035"), _cylinder(), root, object.id)
		_poly("Crown", Vector3(0, size.y * 0.28, 0), Vector3(size.x, size.y * 0.44, size.z), color, _sphere(), root, object.id)
	elif object.kind == "rock":
		_poly("Rock", Vector3.ZERO, size, color, _sphere(), root, object.id)
	else:
		_box("Surface", Vector3.ZERO, size, color, root, object.id)

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.95
		_materials[key] = material
	return _materials[key]

func _body(label: String, location: Vector3, parent: Node3D, id: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = location
	body.collision_layer = 1 if _active else 0
	body.collision_mask = 0
	if id >= 0: body.set_meta("map_object_id", id)
	parent.add_child(body)
	solids.append(body)
	return body

func _box(label: String, location: Vector3, size: Vector3, color: Color, parent: Node3D, id: int = -1) -> StaticBody3D:
	var body := _body(label, location, parent, id)
	var mesh := BoxMesh.new()
	mesh.size = size
	_visual(mesh, Vector3.ONE, color, body, id)
	var shape := BoxShape3D.new()
	shape.size = size
	_collision(shape, body, id)
	return body

func _poly(label: String, location: Vector3, size: Vector3, color: Color, mesh: PrimitiveMesh, parent: Node3D, id: int) -> void:
	var body := _body(label, location, parent, id)
	_visual(mesh, size, color, body, id)
	var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for index in range(points.size()): points[index] *= size
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	_collision(shape, body, id)

func _visual(mesh: Mesh, size: Vector3, color: Color, parent: Node3D, id: int) -> void:
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh
	visual.scale = size
	visual.material_override = _material(color)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if id >= 0: visual.set_meta("map_object_id", id)
	parent.add_child(visual)

func _collision(shape: Shape3D, parent: Node3D, id: int) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	if id >= 0: collision.set_meta("map_object_id", id)
	parent.add_child(collision)

func _sphere() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh

func _cylinder() -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	return mesh
