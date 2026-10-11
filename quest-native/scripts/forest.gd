extends Node3D

const PlayerScript = preload("res://scripts/arm_player.gd")
const BotScript = preload("res://scripts/monkey_bot.gd")
var player: PlayerScript
var bots: Array[BotScript] = []
var board: Label3D
var desktop_label: Label
var remaining := 90.0
var score := 0
var finished := false
var restart_held := false
var last_board := ""
var xr: XRInterface
var xr_focused := true

func mat(color: String) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(color)
	result.roughness = 1.0
	return result

func box(label: String, location: Vector3, size: Vector3, color: String) -> void:
	var solid := StaticBody3D.new()
	solid.name = label
	solid.position = location
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = mat(color)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	solid.add_child(mesh)
	var collider := CollisionShape3D.new()
	var collision := BoxShape3D.new()
	collision.size = size
	collider.shape = collision
	solid.add_child(collider)
	add_child(solid)

func sphere(parent: Node3D, location: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 12
	mesh.rings = 6
	visual.mesh = mesh
	visual.position = location
	visual.scale = size
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	return visual

func _ready() -> void:
	xr = XRServer.find_interface("OpenXR")
	if DisplayServer.get_name() != "headless" and xr != null:
		if xr.is_initialized() or xr.initialize():
			get_viewport().use_xr = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			if xr is OpenXRInterface:
				xr_focused = xr.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED
				xr.session_focussed.connect(func(): xr_focused = true)
				xr.session_visible.connect(func(): xr_focused = false)
				xr.session_stopping.connect(func(): xr_focused = false)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("8aa798")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dceac0")
	environment.ambient_light_energy = 0.65
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	add_child(sun)
	box("ForestFloor", Vector3(0, -0.5, 0), Vector3(32, 1, 32), "47613a")
	box("NorthCliff", Vector3(0, 3, 16), Vector3(34, 7, 1), "566451")
	box("SouthCliff", Vector3(0, 3, -16), Vector3(34, 7, 1), "566451")
	box("EastCliff", Vector3(16, 3, 0), Vector3(1, 7, 32), "566451")
	box("WestCliff", Vector3(-16, 3, 0), Vector3(1, 7, 32), "566451")
	for i in range(12):
		var angle := float(i) * TAU / 12
		var location := Vector3(cos(angle) * 10, 0, sin(angle) * 10)
		box("Tree%s" % i, location + Vector3.UP * 3, Vector3(1.1, 6, 1.1), "684930")
		box("Branch%s" % i, location + Vector3.UP * 2.5, Vector3(3.2, 0.3, 0.8), "785738")
		sphere(self, location + Vector3.UP * 6.8, Vector3(2.9, 2.1, 2.5), mat("3c7344"))
	box("LowRock", Vector3(-3, 0.5, 1), Vector3(3, 1, 2), "81876b")
	box("HighRock", Vector3(-4, 1.25, 3), Vector3(2, 2.5, 2), "6f7861")
	create_player()
	if get_viewport().use_xr and xr is OpenXRInterface:
		xr.pose_recentered.connect(player.reset_tracking_history)
	create_bots()
	board = Label3D.new()
	board.name = "RoundBoard"
	board.position = Vector3(0, 2.4, -1.5)
	board.rotation.y = PI
	board.font_size = 64
	board.pixel_size = 0.0018
	board.modulate = Color("f3f4e3")
	board.outline_modulate = Color("17372b")
	board.outline_size = 20
	add_child(board)
	var overlay := CanvasLayer.new()
	desktop_label = Label.new()
	desktop_label.position = Vector2(25, 25)
	desktop_label.add_theme_font_size_override("font_size", 22)
	overlay.add_child(desktop_label)
	add_child(overlay)
	overlay.visible = not player.xr_running
	restart()

func create_player() -> void:
	player = PlayerScript.new()
	player.name = "VRMonkey"
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
	origin.name = "XROrigin3D"
	player.add_child(origin)
	var head := XRCamera3D.new()
	head.name = "Head"
	head.near = 0.03
	head.far = 65
	origin.add_child(head)
	player.head = head
	player.xr_running = get_viewport().use_xr
	if not player.xr_running: head.position.y = 1.65
	for side in ["left_hand", "right_hand"]:
		var hand := XRController3D.new()
		hand.tracker = side
		hand.pose = "grip"
		origin.add_child(hand)
		player.hands.append(hand)
		var visual := sphere(self, Vector3.ZERO, Vector3.ONE * 0.09, mat("d1a570"))
		visual.visible = false
		player.hand_visuals.append(visual)
	add_child(player)

func create_bots() -> void:
	for i in range(5):
		var bot := BotScript.new()
		bot.name = "Monkey%s" % i
		bot.collision_layer = 2
		bot.collision_mask = 1
		bot.player = player.head
		bot.home = Vector3(float(i - 2) * 2.8, 0.1, 5)
		bot.fur = mat("845634")
		var collider := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.35
		capsule.height = 1.2
		collider.shape = capsule
		collider.position.y = 0.62
		bot.add_child(collider)
		sphere(bot, Vector3(0, 0.64, 0), Vector3(0.43, 0.52, 0.32), bot.fur)
		sphere(bot, Vector3(0, 1.12, 0.06), Vector3(0.3, 0.29, 0.27), bot.fur)
		sphere(bot, Vector3(0, 1.02, 0.3), Vector3(0.19, 0.13, 0.11), mat("cdac75"))
		for side in [-1.0, 1.0]:
			sphere(bot, Vector3(side * 0.13, 1.2, 0.3), Vector3(0.045, 0.05, 0.04), mat("17241c"))
			sphere(bot, Vector3(side * 0.34, 1.1, 0), Vector3(0.1, 0.12, 0.08), mat("cdac75"))
			sphere(bot, Vector3(side * 0.54, 0.48, 0.02), Vector3(0.12, 0.43, 0.12), bot.fur)
		add_child(bot)
		bots.append(bot)

func restart() -> void:
	remaining = 90
	score = 0
	finished = false
	player.reset_player()
	for bot in bots: bot.reset_bot()
	last_board = ""

func tag_bot(bot: BotScript) -> void:
	if finished or bot.tagged: return
	bot.tag()
	score += 1
	if score == 5: finished = true

func _physics_process(delta: float) -> void:
	if player == null: return
	player.input_allowed = xr_focused
	var pressed: bool = (xr_focused and player.hands[1].is_button_pressed("ax_button")) if player.xr_running else Input.is_physical_key_pressed(KEY_R)
	if pressed and not restart_held: restart()
	restart_held = pressed
	var active: bool = player.tracked and xr_focused
	for bot in bots: bot.active = active and not finished
	if active and not finished:
		remaining = maxf(0, remaining - delta)
		for bot in bots:
			if bot.tagged: continue
			var target: Vector3 = bot.global_position + Vector3.UP * 0.7
			if player.xr_running:
				for visual in player.hand_visuals:
					if visual.global_position.distance_to(target) < 0.65: tag_bot(bot)
			elif Input.is_physical_key_pressed(KEY_E) and player.head.global_position.distance_to(target) < 1.7:
				tag_bot(bot)
		if remaining <= 0: finished = true
	var title := "ALL MONKEYS TAGGED!" if score == 5 else ("TIME'S UP!" if finished else "FOREST CHASE")
	var status := "Push surfaces to move. Touch monkeys to tag.\nRight A: restart" if active else "Tracking paused: headset + both controllers required"
	var text := "PRIMAL MONKE\n%s\n%s / 5 TAGGED     %ss\n%s" % [title, score, ceili(remaining), status]
	if text != last_board:
		board.text = text
		desktop_label.text = text + "\nDesktop: WASD / hold right mouse to look / Space / E to tag / R"
		last_board = text
