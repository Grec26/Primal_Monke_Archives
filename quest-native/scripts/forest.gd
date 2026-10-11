extends Node3D

const PlayerScript = preload("res://scripts/arm_player.gd")
const BotScript = preload("res://scripts/monkey_bot.gd")
const SessionScript = preload("res://scripts/crossplay.gd")
const LobbyScript = preload("res://scripts/lobby_menu.gd")
const ModeScript = preload("res://scripts/play_mode.gd")
const AccountScript = preload("res://scripts/playfab_account.gd")
const AccountMenuScript = preload("res://scripts/account_menu.gd")
var session: SessionScript
var lobby: LobbyScript
var account: AccountScript
var account_menu: AccountMenuScript
var dev_menu: Node3D
var requested_play_mode := "auto"
var play_mode_notice := ""
var developer_bots_frozen := false
var diagnostics_enabled := false
var diagnostics_board: Label3D
var _developer_message := "Developer access verified"
var account_status: String:
	get: return account.status if account != null else "Not signed in"
var account_id: String:
	get: return account.account_id if account != null else ""
var account_busy: bool:
	get: return account != null and account.busy
var account_configured: bool:
	get: return account != null and account.configured()
var account_signed_in: bool:
	get: return account != null and account.is_signed_in()
var account_is_developer: bool:
	get: return account != null and account.is_developer()
var account_has_credentials: bool:
	get: return account != null and account.has_credentials
var developer_status: String:
	get: return _developer_message if account_is_developer else "Developer access required"
var network_status: String:
	get: return session.status if session != null else "Solo"
var session_address: String:
	get: return session.address if session != null else ""
var network_mode: String:
	get: return session.mode if session != null else "offline"
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
	requested_play_mode = ModeScript.requested(OS.get_cmdline_user_args(), OS.has_feature("android"))
	xr = XRServer.find_interface("OpenXR")
	if requested_play_mode != "desktop" and DisplayServer.get_name() != "headless" and xr != null:
		if xr.is_initialized() or xr.initialize():
			get_viewport().use_xr = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			if xr is OpenXRInterface:
				xr_focused = xr.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED
				xr.session_focussed.connect(func(): xr_focused = true)
				xr.session_visible.connect(func(): xr_focused = false)
				xr.session_stopping.connect(func(): xr_focused = false)
	if requested_play_mode == "pcvr" and not get_viewport().use_xr:
		play_mode_notice = "PC VR unavailable. Start your headset's OpenXR runtime, then retry PC VR."
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
	session = SessionScript.new()
	session.name = "Crossplay"
	session.game = self
	add_child(session)
	lobby = LobbyScript.new()
	lobby.name = "LobbyMenu"
	lobby.game = self
	add_child(lobby)
	account = AccountScript.new()
	account.name = "PlayFabAccount"
	add_child(account)
	account_menu = AccountMenuScript.new()
	account_menu.name = "AccountMenu"
	account_menu.game = self
	add_child(account_menu)
	account.state_changed.connect(_account_changed)
	diagnostics_board = Label3D.new()
	diagnostics_board.position = Vector3(0, -0.22, -0.7)
	diagnostics_board.font_size = 22
	diagnostics_board.pixel_size = 0.001
	diagnostics_board.no_depth_test = true
	diagnostics_board.visible = false
	player.head.add_child(diagnostics_board)
	# Headless tests never register real players or make external account requests.
	if DisplayServer.get_name() != "headless": account.call_deferred("login_device")

func can_switch_play_mode(mode: String) -> bool:
	if OS.has_feature("android") or DisplayServer.get_name() == "headless": return false
	if mode not in ["desktop", "pcvr"] or player == null or network_mode != "offline": return false
	return (mode == "pcvr" and not player.xr_running) or (mode == "desktop" and player.xr_running)

func switch_play_mode(mode: String) -> void:
	if not can_switch_play_mode(mode):
		play_mode_notice = "Leave the multiplayer session before switching play modes."
		return
	var editor_path := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else ""
	var process_id := OS.create_process(OS.get_executable_path(), ModeScript.launch_arguments(mode, editor_path))
	if process_id <= 0:
		play_mode_notice = "Could not launch %s. Try its launcher in the Windows download." % mode
		return
	get_tree().quit()

func open_account_menu() -> void:
	account_menu.set_open(true)

func on_account_menu_open() -> void:
	lobby.set_open(false)
	if is_instance_valid(dev_menu): dev_menu.set_open(false)

func on_developer_menu_open() -> void:
	lobby.set_open(false)
	account_menu.set_open(false)

func account_login_device() -> void:
	account.login_device()

func account_login_credentials(identifier: String, password: String) -> void:
	account.login_credentials(identifier, password)

func account_register(username: String, email: String, password: String) -> void:
	account.register(username, email, password)

func account_refresh() -> void:
	account.refresh_permissions()

func account_logout() -> void:
	account.sign_out()

func _account_changed() -> void:
	if account_is_developer:
		if not is_instance_valid(dev_menu):
			var script := load("res://dev/developer_menu.gd") as Script
			if script == null: return
			dev_menu = script.new()
			dev_menu.name = "DeveloperMenu"
			dev_menu.game = self
			add_child(dev_menu)
	else:
		if is_instance_valid(dev_menu):
			dev_menu.set_open(false)
			dev_menu.queue_free()
			dev_menu = null
		developer_bots_frozen = false
		diagnostics_enabled = false

func developer_action_allowed(action: String) -> bool:
	if not account_is_developer: return false
	if action in ["respawn", "diagnostics"]: return true
	if action not in ["restart", "add_time", "freeze_bots", "tag_all"]: return false
	return session != null and not session.is_client()

func developer_action(action: String) -> void:
	# Menu buttons, shortcuts, and direct calls all pass the same role/authority gate.
	if not developer_action_allowed(action): return
	match action:
		"restart": restart()
		"add_time":
			if score < bots.size():
				remaining = minf(300, remaining + 30)
				finished = false
		"freeze_bots": developer_bots_frozen = not developer_bots_frozen
		"tag_all":
			for bot in bots: tag_bot(bot)
		"respawn": player.reset_player()
		"diagnostics": diagnostics_enabled = not diagnostics_enabled
	_developer_message = "Bots frozen" if developer_bots_frozen else "Developer access verified"
	if session.is_host(): session._send_snapshot()

func host_session() -> void:
	session.host()
	if session.is_host(): lobby.set_open(false)

func join_session(address: String) -> void:
	session.join(address)

func leave_session() -> void:
	session.leave()

func is_session_host() -> bool:
	return session != null and session.is_host()

func request_restart() -> void:
	if session != null and session.is_client():
		session.status = "Only the host can restart the shared round"
		return
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
	if session != null and session.is_client(): return
	remaining = 90
	score = 0
	finished = false
	player.reset_player()
	for bot in bots: bot.reset_bot()
	last_board = ""
	developer_bots_frozen = false
	_developer_message = "Developer access verified"
	if session != null: session.round_restarted()

func tag_bot(bot: BotScript) -> void:
	if session != null and session.is_client(): return
	if finished or bot.tagged: return
	bot.tag()
	score += 1
	if score == 5: finished = true

func _physics_process(delta: float) -> void:
	if player == null: return
	var menu_open: bool = (lobby != null and lobby.is_open) or (account_menu != null and account_menu.is_open) or (is_instance_valid(dev_menu) and dev_menu.is_open)
	# Opening the public lobby closes any other overlay, so only one menu owns input.
	if lobby != null and lobby.is_open:
		if account_menu != null and account_menu.is_open: account_menu.set_open(false)
		if is_instance_valid(dev_menu) and dev_menu.is_open: dev_menu.set_open(false)
	player.input_allowed = xr_focused and not menu_open
	var pressed: bool = (xr_focused and player.hands[1].is_button_pressed("ax_button")) if player.xr_running else Input.is_physical_key_pressed(KEY_R)
	if pressed and not restart_held and player.input_allowed: request_restart()
	restart_held = pressed
	var poses: Array = session.participant_poses() if session != null else []
	var active := not poses.is_empty()
	var authority := session == null or not session.is_client()
	for bot in bots:
		bot.active = authority and active and not finished and not developer_bots_frozen
		bot.use_network_target = session != null and session.is_host()
		if bot.use_network_target:
			var closest := INF
			for pose in poses:
				var distance: float = bot.global_position.distance_squared_to(pose.head)
				if distance < closest:
					closest = distance
					bot.chase_position = pose.head
	if authority and active and not finished:
		remaining = maxf(0, remaining - delta)
		for bot in bots:
			if bot.tagged: continue
			var target: Vector3 = bot.global_position + Vector3.UP * 0.7
			for pose in poses:
				if pose.vr:
					if pose.left.distance_to(target) < 0.65 or pose.right.distance_to(target) < 0.65: tag_bot(bot)
				elif pose.tag and pose.head.distance_to(target) < 1.7: tag_bot(bot)
		if remaining <= 0: finished = true
	var title := "ALL MONKEYS TAGGED!" if score == 5 else ("TIME'S UP!" if finished else "FOREST CHASE")
	var status := "Push surfaces to move. Touch monkeys to tag." if player.xr_running else "WASD / right mouse: look / Space / E: tag"
	if not active: status = "Paused — close menu / restore headset + controller tracking"
	status += "\nRight B / Tab: multiplayer menu · " + network_mode
	if session != null and session.is_client(): status += " · Host restarts"
	else: status += " · Right A / R: restart"
	if not play_mode_notice.is_empty(): status += "\n" + play_mode_notice
	if account_is_developer: status += "\nDeveloper tools: F2 / left Y · Account: F3 / left X"
	var diagnostics := "%s FPS · %s · Tracking %s\nPosition %s\nRound %s / 5 · %ss" % [Engine.get_frames_per_second(), network_mode, player.tracked, player.global_position.snapped(Vector3.ONE * 0.1), score, ceili(remaining)]
	if diagnostics_enabled and not account_is_developer: diagnostics_enabled = false
	if diagnostics_board != null:
		diagnostics_board.visible = diagnostics_enabled and player.xr_running
		diagnostics_board.text = diagnostics
	var text := "PRIMAL MONKE\n%s\n%s / 5 TAGGED     %ss\n%s" % [title, score, ceili(remaining), status]
	if text != last_board:
		board.text = text
		desktop_label.text = text
		last_board = text
	desktop_label.text = text + ("\n" + diagnostics if diagnostics_enabled else "")
