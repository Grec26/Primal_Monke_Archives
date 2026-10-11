extends Node3D

# The same deterministic arena is built on desktop, PC VR, and Quest. All
# routes use layer 1, so a surface a hand can push against is also solid for a
# desktop player. The center remains open for chasing and bot spawn points.
var game: Node3D
var solids: Array[StaticBody3D] = []
var solid_count: int:
	get: return solids.size()
var landmarks := {
	"hub": Vector3(0, 0.1, -5),
	"treehouse": Vector3(-1.5, 3.05, 8.0),
	"lookout": Vector3(12.0, 3.16, 8.5),
	"cave": Vector3(-12.0, 0.1, -8.5),
}
var map_summary := "Forest hub · shaded cave · treehouse · lookout and canopy bridge"
var _materials: Dictionary = {}

func _ready() -> void:
	_arena()
	_tree_ring()
	_treehouse()
	_lookout()
	_cave()
	_hub()

func _material(color: String) -> StandardMaterial3D:
	if not _materials.has(color):
		var result := StandardMaterial3D.new()
		result.albedo_color = Color(color)
		result.roughness = 1.0
		_materials[color] = result
	return _materials[color] as StandardMaterial3D

func _visual(label: String, location: Vector3, size: Vector3, color: String, parent: Node3D = self) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.position = location
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(color)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	return visual

func _box(label: String, location: Vector3, size: Vector3, color: String, parent: Node3D = self) -> StaticBody3D:
	var solid := StaticBody3D.new()
	solid.name = label
	solid.position = location
	solid.collision_layer = 1
	solid.collision_mask = 0
	_visual("Surface", Vector3.ZERO, size, color, solid)
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var collision := BoxShape3D.new()
	collision.size = size
	collider.shape = collision
	solid.add_child(collider)
	parent.add_child(solid)
	solids.append(solid)
	return solid

func _arena() -> void:
	# Retain the root floor name for old saved scene checks and integrations.
	_box("ForestFloor", Vector3(0, -0.5, 0), Vector3(32, 1, 32), "47613a", game)
	_box("NorthCliff", Vector3(0, 3, 16), Vector3(34, 7, 1), "566451")
	_box("SouthCliff", Vector3(0, 3, -16), Vector3(34, 7, 1), "566451")
	_box("EastCliff", Vector3(16, 3, 0), Vector3(1, 7, 32), "566451")
	_box("WestCliff", Vector3(-16, 3, 0), Vector3(1, 7, 32), "566451")

func _tree_ring() -> void:
	for index in range(12):
		var angle := float(index) * TAU / 12.0
		var location := Vector3(cos(angle) * 10, 0, sin(angle) * 10)
		_box("Tree%s" % index, location + Vector3.UP * 3, Vector3(1.1, 6, 1.1), "684930")
		# This branch clears the treehouse approach instead of crossing its
		# second and third treads at head height.
		var branch_height := 3.6 if index == 1 else 2.5
		_box("Branch%s" % index, location + Vector3.UP * branch_height, Vector3(3.2, 0.3, 0.8), "785738")
		var leaves := MeshInstance3D.new()
		leaves.name = "Canopy%s" % index
		var crown := SphereMesh.new()
		crown.radius = 1
		crown.height = 2
		crown.radial_segments = 8
		crown.rings = 4
		leaves.mesh = crown
		leaves.position = location + Vector3.UP * 6.8
		leaves.scale = Vector3(2.9, 2.1, 2.5)
		leaves.material_override = _material("3c7344" if index % 2 == 0 else "416c3c")
		leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(leaves)
	_box("LowRock", Vector3(-3, 0.5, 1), Vector3(3, 1, 2), "81876b")
	_box("HighRock", Vector3(-4, 1.25, 3), Vector3(2, 2.5, 2), "6f7861")

func _treehouse() -> void:
	_box("TreehouseDeck", Vector3(0, 2.8, 9), Vector3(6, 0.3, 4), "8d683d")
	for side in [-1.0, 1.0]:
		_box("TreehousePost%s" % side, Vector3(side * 2.6, 1.4, 9), Vector3(0.35, 2.8, 0.35), "694b2e")
		_box("ClimbingPole%s" % side, Vector3(side * 2.4, 2.8, 6.8), Vector3(0.18, 5.6, 0.18), "b28e56")
	_box("TreehouseRoof", Vector3(0, 5.5, 9), Vector3(6.5, 0.25, 4.4), "365c37")
	# The original seven steps move outside the bot homes. Their 0.38 m rises
	# are within a desktop jump, and each 0.85 m tread overlaps the next.
	for index in range(7):
		_box("ClimbStep%s" % index, Vector3(7.3, 0.22 + index * 0.38, 4.0 + index * 0.6), Vector3(1.8, 0.36, 0.85), "907348")
	_box("TreehouseTurnLanding", Vector3(7.3, 2.91, 8.55), Vector3(1.8, 0.3, 1.1), "9a7645")
	_box("StairBridgeConnector", Vector3(7.3, 2.95, 10.35), Vector3(1.8, 0.22, 2.8), "9a7645")
	_box("TreehouseBridgeConnector", Vector3(2.0, 2.8, 11.1), Vector3(1.6, 0.3, 2.4), "8d683d")
	# The bridge loops behind the tree ring, avoiding trunks and canopy. Wider
	# resting pads break up its narrow balance sections without a jump gap.
	_box("BridgeRoute", Vector3(8.1, 2.95, 11.7), Vector3(10.6, 0.22, 1.0), "9a7645")
	for index in range(3):
		_box("BridgeRestPad%s" % index, Vector3(4.1 + index * 3.2, 2.966, 11.7), Vector3(1.35, 0.22, 1.65), "b28e56")
	for index in range(4):
		var side := -1.0 if index % 2 == 0 else 1.0
		_box("BridgeBalancePost%s" % index, Vector3(4.8 + index * 1.8, 3.65, 11.7 + side * 0.65), Vector3(0.18, 1.4, 0.18), "694b2e")
	_sign("TreehouseSign", Vector3(-2.1, 4.15, 7.25), "TREEHOUSE\nCanopy loop →", "efc178")

func _lookout() -> void:
	_box("LookoutDeck", Vector3(12, 2.9, 8.5), Vector3(4.2, 0.32, 4.2), "8d683d")
	for index in range(9):
		var height := float(index + 1) * 0.34
		_box("LookoutStep%s" % index, Vector3(12, height - 0.16, 1.3 + index * 0.62), Vector3(1.8, 0.32, 0.85), "907348")
	_box("LookoutBridgeConnector", Vector3(12, 2.95, 11.0), Vector3(1.8, 0.22, 2.5), "9a7645")
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			_box("LookoutPost%s%s" % [side, end], Vector3(12 + side * 1.85, 3.0, 8.5 + end * 1.85), Vector3(0.25, 6.0, 0.25), "694b2e")
	_box("LookoutRoof", Vector3(12, 6.1, 8.5), Vector3(4.65, 0.22, 4.65), "365c37")
	_box("LookoutClimbPole", Vector3(14.25, 2.2, 8.5), Vector3(0.22, 4.4, 0.22), "b28e56")
	_sign("LookoutSign", Vector3(13.4, 4.4, 9.9), "EAST LOOKOUT\nCanopy loop ←", "83c8d4")
	_sign("LookoutTrailSign", Vector3(13.8, 1.5, 0.2), "LOOKOUT ↑\nSteps or arm climb", "83c8d4")

func _cave() -> void:
	# A broad opening faces the hub. The interior has a continuous ground
	# floor and at least 2.8 m overhead clearance, with no decorative blockers.
	_box("CaveWestWall", Vector3(-14.9, 1.5, -8.5), Vector3(0.5, 3, 5.7), "596359")
	_box("CaveNorthWall", Vector3(-12, 1.5, -5.9), Vector3(6.2, 3, 0.5), "6f7861")
	_box("CaveSouthWall", Vector3(-12, 1.5, -11.1), Vector3(6.2, 3, 0.5), "596359")
	_box("CaveDoorNorth", Vector3(-9.1, 1.5, -6.3), Vector3(0.5, 3, 1.3), "81876b")
	_box("CaveDoorSouth", Vector3(-9.1, 1.5, -10.55), Vector3(0.5, 3, 1.5), "81876b")
	_box("CaveDoorLintel", Vector3(-9.1, 2.85, -8.5), Vector3(0.6, 0.3, 3.3), "6f7861")
	_box("CaveRoof", Vector3(-12, 3.2, -8.5), Vector3(6.3, 0.4, 5.8), "566451")
	_visual("CaveGround", Vector3(-12, 0.006, -8.5), Vector3(5.2, 0.01, 4.7), "73806a")
	_visual("CaveMossNorth", Vector3(-12.9, 3.43, -7.2), Vector3(2.9, 0.05, 2.1), "47613a")
	_visual("CaveMossSouth", Vector3(-11.1, 3.43, -9.6), Vector3(2.8, 0.05, 1.4), "47613a")
	_box("CaveTrailBoulder", Vector3(-7.75, 0.5, -10.5), Vector3(1.4, 1.0, 1.2), "81876b")
	_sign("CaveTrailSign", Vector3(-7.5, 1.55, -7.0), "SHADED CAVE ←\nGround route", "b2bde3")

func _hub() -> void:
	# Thin visual paths avoid extra collisions while giving each zone a clear
	# color and direction. They never alter the shared floor's height.
	_visual("HubPath", Vector3(0, 0.007, -5.1), Vector3(3.7, 0.01, 3.2), "697c50")
	_visual("CavePath", Vector3(-5.2, 0.007, -8.5), Vector3(7.5, 0.01, 1.3), "697c50")
	_visual("LookoutPath", Vector3(8.2, 0.007, -1.1), Vector3(7.8, 0.01, 1.3), "697c50")
	_visual("TreehousePath", Vector3(7.3, 0.007, 1.8), Vector3(1.3, 0.01, 3.8), "697c50")
	_box("HubBenchWest", Vector3(-3.4, 0.32, -5.9), Vector3(1.4, 0.64, 0.7), "8d683d")
	_box("HubBenchEast", Vector3(3.4, 0.32, -5.9), Vector3(1.4, 0.64, 0.7), "8d683d")
	_sign("HubWayfinding", Vector3(0, 1.8, -7.1), "PRIMAL MONKE\n← CAVE   LOOKOUT →\nTREEHOUSE ↑", "efc178")
	_sign("TreehouseTrailSign", Vector3(8.6, 1.55, 2.8), "TREEHOUSE ↑\nClimb steps to loop", "efc178")

func _sign(label: String, location: Vector3, text: String, accent: String) -> void:
	var post_height := maxf(location.y - 0.2, 0.4)
	_box(label + "Post", Vector3(location.x, post_height * 0.5, location.z), Vector3(0.14, post_height, 0.14), "694b2e")
	# Signs use billboarded labels so directions remain readable from both
	# approaches. The narrow post is the only physical decoration.
	var sign_text := Label3D.new()
	sign_text.name = label
	sign_text.position = location
	sign_text.text = text
	sign_text.font_size = 56
	sign_text.pixel_size = 0.0025
	sign_text.modulate = Color(accent)
	sign_text.outline_modulate = Color("17372b")
	sign_text.outline_size = 8
	sign_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sign_text)
