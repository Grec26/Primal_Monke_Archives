extends Node3D

var head: Node3D
var body: MeshInstance3D
var left: MeshInstance3D
var right: MeshInstance3D
var label: Label3D
var target: Dictionary = {}
var initialized := false

func part(parent: Node3D, size: Vector3, color: String) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 12
	mesh.rings = 6
	result.mesh = mesh
	result.scale = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 1
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result

func _ready() -> void:
	head = Node3D.new()
	add_child(head)
	part(head, Vector3(0.23, 0.24, 0.22), "9770b5")
	var muzzle := part(head, Vector3(0.15, 0.09, 0.07), "cdac75")
	muzzle.position = Vector3(0, -0.04, -0.2)
	for x in [-0.08, 0.08]:
		var eye := part(head, Vector3.ONE * 0.03, "17241c")
		eye.position = Vector3(x, 0.06, -0.21)
	body = part(self, Vector3(0.3, 0.38, 0.22), "9770b5")
	left = part(self, Vector3.ONE * 0.1, "cdac75")
	right = part(self, Vector3.ONE * 0.1, "cdac75")
	label = Label3D.new()
	label.font_size = 32
	label.pixel_size = 0.003
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func apply_pose(pose: Dictionary, id: int) -> void:
	target = pose
	visible = pose.get("active", false)
	label.text = "%s · %s" % ["VR" if pose.vr else "PC", id]
	if not initialized:
		place(1)
		initialized = true

func place(weight: float) -> void:
	head.global_position = head.global_position.lerp(target.head, weight)
	head.global_basis = head.global_basis.slerp(Basis.from_euler(target.rotation), weight)
	body.global_position = body.global_position.lerp(target.head + Vector3.DOWN * 0.58, weight)
	left.global_position = left.global_position.lerp(target.left, weight)
	right.global_position = right.global_position.lerp(target.right, weight)
	label.global_position = head.global_position + Vector3.UP * 0.4

func _process(delta: float) -> void:
	if not target.is_empty(): place(1.0 - exp(-18 * delta))
