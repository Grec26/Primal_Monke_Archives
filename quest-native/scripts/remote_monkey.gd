extends Node3D

var head: Node3D
var body: MeshInstance3D
var left: MeshInstance3D
var right: MeshInstance3D
var label: Label3D
var portrait: Sprite3D
var head_mesh: MeshInstance3D
var lava_spots: Array[MeshInstance3D] = []
var target: Dictionary = {}
var initialized := false
var peer_id := 0
var profile_name := ""
var profile_level := 1
var is_tagged := false
var _avatar_bytes := PackedByteArray()

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
	head_mesh = part(head, Vector3(0.23, 0.24, 0.22), "9770b5")
	var muzzle := part(head, Vector3(0.15, 0.09, 0.07), "cdac75")
	muzzle.position = Vector3(0, -0.04, -0.2)
	for x in [-0.08, 0.08]:
		var eye := part(head, Vector3.ONE * 0.03, "17241c")
		eye.position = Vector3(x, 0.06, -0.21)
	body = part(self, Vector3(0.3, 0.38, 0.22), "9770b5")
	for offset in [Vector3(-0.16, 0.14, -0.19), Vector3(0.13, -0.08, -0.22), Vector3(-0.04, -0.26, -0.18)]:
		var spot := part(body, Vector3.ONE * 0.17, "6c2018")
		spot.position = offset
		spot.visible = false
		lava_spots.append(spot)
	left = part(self, Vector3.ONE * 0.1, "cdac75")
	right = part(self, Vector3.ONE * 0.1, "cdac75")
	label = Label3D.new()
	label.font_size = 32
	label.pixel_size = 0.003
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	portrait = Sprite3D.new()
	portrait.pixel_size = 0.0035
	portrait.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	portrait.no_depth_test = false
	portrait.visible = false
	add_child(portrait)

func apply_pose(pose: Dictionary, id: int) -> void:
	target = pose
	peer_id = id
	visible = pose.get("active", false)
	_update_label()
	if not initialized:
		place(1)
		initialized = true

func _update_label() -> void:
	if label == null: return
	var display_name := profile_name if not profile_name.is_empty() else ("Host" if peer_id == 1 else "Player %s" % peer_id)
	label.text = "%s · Lv %s%s" % [display_name, profile_level, " · IT" if is_tagged else ""]
	label.modulate = Color("ffca7a") if is_tagged else Color("e5f2e9")

func set_tagged(value: bool) -> void:
	if is_tagged == value: return
	is_tagged = value
	for mesh in [head_mesh, body]:
		if mesh == null: continue
		var material := mesh.material_override as StandardMaterial3D
		material.albedo_color = Color("ff772c") if value else Color("9770b5")
		material.emission_enabled = value
		material.emission = Color("7a1900") if value else Color.BLACK
		material.emission_energy_multiplier = 0.3
	for spot in lava_spots: spot.visible = value
	_update_label()

func apply_profile(profile: Dictionary) -> void:
	profile_name = str(profile.get("name", "")).left(20)
	profile_level = clampi(int(profile.get("level", 1)), 1, 316)
	_update_label()
	var bytes: Variant = profile.get("avatar", PackedByteArray())
	if not bytes is PackedByteArray or bytes == _avatar_bytes: return
	portrait.visible = false
	portrait.texture = null
	if bytes.size() > 6000:
		_avatar_bytes = PackedByteArray()
		return
	_avatar_bytes = bytes.duplicate()
	if bytes.is_empty() or bytes.size() < 33: return
	if bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]): return
	if bytes.slice(8, 12) != PackedByteArray([0, 0, 0, 13]) or bytes.slice(12, 16).get_string_from_ascii() != "IHDR": return
	var width: int = (int(bytes[16]) << 24) | (int(bytes[17]) << 16) | (int(bytes[18]) << 8) | int(bytes[19])
	var height: int = (int(bytes[20]) << 24) | (int(bytes[21]) << 16) | (int(bytes[22]) << 8) | int(bytes[23])
	if width < 1 or height < 1 or width > 64 or height > 64: return
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.get_width() != width or image.get_height() != height: return
	portrait.texture = ImageTexture.create_from_image(image)
	portrait.visible = true

func place(weight: float) -> void:
	head.global_position = head.global_position.lerp(target.head, weight)
	head.global_basis = head.global_basis.slerp(Basis.from_euler(target.rotation), weight)
	body.global_position = body.global_position.lerp(target.head + Vector3.DOWN * 0.58, weight)
	left.global_position = left.global_position.lerp(target.left, weight)
	right.global_position = right.global_position.lerp(target.right, weight)
	label.global_position = head.global_position + Vector3.UP * 0.4
	portrait.global_position = head.global_position + Vector3.UP * 0.68

func _process(delta: float) -> void:
	if not target.is_empty(): place(1.0 - exp(-18 * delta))
