extends Node3D

const PlayerScript = preload("res://scripts/arm_player.gd")
const BotScript = preload("res://scripts/monkey_bot.gd")
const SessionScript = preload("res://scripts/crossplay.gd")
const LobbyScript = preload("res://scripts/multiplayer_lobby.gd")
const MainMenuScript = preload("res://scripts/main_menu.gd")
const LoadingScript = preload("res://scripts/loading_screen.gd")
const ModeScript = preload("res://scripts/play_mode.gd")
const AccountScript = preload("res://scripts/playfab_account.gd")
const AccountMenuScript = preload("res://scripts/account_menu.gd")
var session: SessionScript
var lobby: LobbyScript
var main_menu: MainMenuScript
var loading_screen: LoadingScript
var frontend_state := "main_menu"
var _resume_available := false
var _loading_generation := 0
var _changing_frontend := false
var _returning_to_main := false
var frontend_status := "Climb, chase, and play together."
var lobby_members: Array:
	get:
		if session == null or network_mode == "offline":
			return [{"id": 0, "label": "Local player", "is_host": false, "is_self": true}]
		var roster: Array = []
		for member in session.room_roster():
			roster.append({"id": member.id, "label": member.label, "name": member.get("name", member.label), "level": member.get("level", 1), "avatar": member.get("avatar", PackedByteArray()), "is_host": member.host, "is_self": member.local})
		return roster
var lobby_can_start: bool:
	get: return session != null and session.can_start_round() and frontend_state != "loading"
var lobby_is_staging: bool:
	get: return not _resume_available or (session != null and network_mode != "offline" and session.phase != "playing")
var account: AccountScript
var account_menu: AccountMenuScript
var profile: Node
var profile_menu: Node3D
var voice: Node
var voice_menu: Node3D
var tutorial: Node3D
var sounds: Node
var onboarding: Node
var settings: Node
var settings_menu: Node3D
var forest_map: Node3D
var developer_tools: Node3D
var map_creator: Node3D
var presentation: Node3D
var local_tag_count := 0
var _profile_level := 1
var _progress_round := ""
var _progress_score := 0
var _progress_finished := false
var _local_round_serial := 0
var _room_serial := 0
var profile_summary: String:
	get: return str(profile.call("summary")) if is_instance_valid(profile) and profile.has_method("summary") else "Monke · Level 1"
var room_game_mode: String:
	get: return str(session.get("game_mode")) if session != null else "co_op"
var room_mode_label: String:
	get: return "Player Tag · chase the orange monke" if room_game_mode == "tag" else "Co-op Chase · tag five monkeys"
var account_error_code: String:
	get: return account.error_code if account != null else ""
var dev_menu: Node3D
var requested_play_mode := "auto"
var play_mode_notice := ""
var developer_bots_frozen := false
var developer_round_paused := false
var developer_bot_speed := 1.0
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
	forest_map = _component("res://scripts/forest_map.gd", "ForestMap") as Node3D
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
	main_menu = MainMenuScript.new()
	main_menu.name = "MainMenu"
	main_menu.game = self
	add_child(main_menu)
	loading_screen = LoadingScript.new()
	loading_screen.name = "LoadingScreen"
	player.head.add_child(loading_screen)
	account = AccountScript.new()
	account.name = "PlayFabAccount"
	add_child(account)
	account_menu = AccountMenuScript.new()
	account_menu.name = "AccountMenu"
	account_menu.game = self
	add_child(account_menu)
	account.state_changed.connect(_account_changed)
	_initialize_features()
	diagnostics_board = Label3D.new()
	diagnostics_board.position = Vector3(0, -0.22, -0.7)
	diagnostics_board.font_size = 22
	diagnostics_board.pixel_size = 0.001
	diagnostics_board.no_depth_test = true
	diagnostics_board.visible = false
	player.head.add_child(diagnostics_board)
	_set_frontend_state("main_menu")
	# Headless tests never register real players or make external account requests.
	if DisplayServer.get_name() != "headless":
		if onboarding != null and onboarding.call("should_skip_auto_device_login"):
			onboarding.call_deferred("begin_if_needed")
		else:
			account.call_deferred("login_device")

func _component(path: String, component_name: String) -> Node:
	if not ResourceLoader.exists(path): return null
	var script := load(path) as Script
	if script == null: return null
	var node: Node = script.new()
	node.name = component_name
	node.set("game", self)
	add_child(node)
	return node

func _initialize_features() -> void:
	sounds = _component("res://scripts/game_sounds.gd", "GameSounds")
	settings = _component("res://scripts/settings_state.gd", "SettingsState")
	settings_menu = _component("res://scripts/settings_menu.gd", "SettingsMenu") as Node3D
	developer_tools = _component("res://dev/developer_tools.gd", "DeveloperTools") as Node3D
	profile = _component("res://scripts/profile_state.gd", "ProfileState")
	voice = _component("res://scripts/voice_chat.gd", "VoiceChat")
	profile_menu = _component("res://scripts/profile_menu.gd", "ProfileMenu") as Node3D
	voice_menu = _component("res://scripts/voice_menu.gd", "VoiceMenu") as Node3D
	tutorial = _component("res://scripts/tutorial_menu.gd", "TutorialMenu") as Node3D
	onboarding = _component("res://scripts/onboarding.gd", "Onboarding")
	map_creator = _component("res://scripts/map_creator.gd", "MapCreator") as Node3D
	presentation = _component("res://scripts/game_presentation.gd", "GamePresentation") as Node3D
	if profile != null:
		profile.connect("public_profile_changed", _profile_changed)
		profile.call("account_changed")
	# Bind GUI buttons once. VR actions use the shared menu ray handler.
	for menu in [main_menu, lobby, account_menu, profile_menu, voice_menu, settings_menu]:
		if menu == null: continue
		var buttons: Variant = menu.get("_desktop_buttons")
		if buttons is Dictionary:
			for button in buttons.values():
				if button is Button: button.pressed.connect(func(): play_ui_sound("click"))

func _feature_menus() -> Array:
	return [profile_menu, voice_menu, tutorial, settings_menu]

func _map_creation_active() -> bool:
	return is_instance_valid(map_creator) and map_creator.get("active") == true

func _ordinary_menus_allowed() -> bool:
	return frontend_state != "loading" and not _map_creation_active()

func can_open_map_creator() -> bool:
	return is_instance_valid(map_creator) and _ordinary_menus_allowed() and network_mode == "offline"

func open_map_creator() -> void:
	if can_open_map_creator(): map_creator.call("begin")

func enter_map_creation() -> void:
	if network_mode != "offline" or frontend_state == "loading": return
	_loading_generation += 1
	_resume_available = false
	if tutorial != null: tutorial.set("practice_active", false)
	if is_instance_valid(developer_tools): developer_tools.call("reset")
	diagnostics_enabled = false
	_set_frontend_state("creating")
	forest_map.call("set_arena_active", false)
	_reset_map_spawn()
	frontend_status = "Create a local map, save it, and try it in playtest."

func begin_map_playtest() -> void:
	if not _map_creation_active() or network_mode != "offline": return
	_set_frontend_state("map_playtest")
	_reset_map_spawn()
	if not player.xr_running:
		player.desktop_yaw = PI
		player.desktop_pitch = 0.0
		player.head.rotation = Vector3(0, PI, 0)
	player.head.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func end_map_playtest() -> void:
	if not _map_creation_active(): return
	_set_frontend_state("creating")
	_reset_map_spawn()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func finish_map_creation() -> void:
	if network_mode != "offline": return
	forest_map.call("set_arena_active", true)
	player.head.current = true
	restart()
	_resume_available = false
	frontend_status = "Your local maps are available in Map creator."
	_set_frontend_state("main_menu")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _reset_map_spawn() -> void:
	player.reset_player()
	# Put the tracked capsule, rather than the room origin, at the clear spawn.
	if player.xr_running:
		var offset := player.head.position
		player.global_position -= Vector3(offset.x, 0, offset.z)
		var height := clampf(player.head.position.y, 0.6, 2.2)
		(player.capsule_node.shape as CapsuleShape3D).height = height
		player.capsule_node.position = Vector3(offset.x, height * 0.5 + 0.02, offset.z)
	player.reset_tracking_history()

func _feature_open() -> bool:
	for menu in _feature_menus():
		if is_instance_valid(menu) and menu.get("is_open") == true: return true
	return false

func _close_feature_menus(except: Node = null) -> void:
	for menu in _feature_menus():
		if is_instance_valid(menu) and menu != except and menu.get("is_open") == true:
			menu.call("set_open", false)

func on_feature_menu_open(menu: Node) -> void:
	if not _ordinary_menus_allowed(): return
	_changing_frontend = true
	_close_feature_menus(menu)
	lobby.set_open(false)
	main_menu.set_open(false)
	account_menu.set_open(false)
	if is_instance_valid(dev_menu): dev_menu.set_open(false)
	_changing_frontend = false
	player.input_allowed = false

func close_feature_menu(menu: Node) -> void:
	if _changing_frontend: return
	if menu != null and menu.get("is_open") == true:
		_changing_frontend = true
		menu.call("set_open", false)
		_changing_frontend = false
	on_account_menu_closed()

func open_settings_menu() -> void:
	if _ordinary_menus_allowed() and settings_menu != null: settings_menu.call("set_open", true)

func open_profile_menu() -> void:
	if _ordinary_menus_allowed() and profile_menu != null: profile_menu.call("set_open", true)

func open_voice_menu() -> void:
	if _ordinary_menus_allowed() and voice_menu != null: voice_menu.call("set_open", true)

func open_tutorial_menu() -> void:
	if not _ordinary_menus_allowed() or tutorial == null: return
	if tutorial.get("practice_active") == true: tutorial.call("set_open", true)
	else: tutorial.call("begin")

func on_first_time_account_closed() -> void:
	if onboarding != null: onboarding.call("continue_as_guest", not _changing_frontend)

func cycle_room_mode() -> void:
	if session != null and frontend_state != "loading": session.call("cycle_game_mode")

func play_ui_sound(cue := "click") -> void:
	if sounds != null: sounds.call("play_cue", cue)

func _profile_changed() -> void:
	if profile == null: return
	var level := int(profile.get("level"))
	if level > _profile_level: play_ui_sound("level_up")
	_profile_level = level
	if session != null: session.call("publish_profile", profile.call("public_profile"))

func on_bot_tagged(tagger: int, _index: int, _event_key: String) -> void:
	if tagger == multiplayer.get_unique_id(): local_tag_count += 1
	play_ui_sound("tag")

func on_player_tagged(tagger: int, _target: int, event_key: String) -> void:
	if tagger == multiplayer.get_unique_id():
		local_tag_count += 1
		if profile != null: profile.call("award_xp", 20, "player:%s:%s" % [_room_serial, event_key])
	play_ui_sound("tag")

func _update_progress() -> void:
	if profile == null or frontend_state != "playing": return
	var serial := session.received_round if session != null and session.is_client() else (session.round_id if session != null else _local_round_serial)
	var key := "%s:%s:%s:%s" % [_room_serial, network_mode, serial, _local_round_serial if network_mode == "offline" else 0]
	if key != _progress_round:
		_progress_round = key
		_progress_score = 0
		_progress_finished = false
	if room_game_mode == "co_op":
		while _progress_score < score:
			_progress_score += 1
			profile.call("award_xp", 10, "round:" + key + ":bot:" + str(_progress_score))
	if finished and not _progress_finished:
		_progress_finished = true
		if room_game_mode == "co_op" and score == bots.size():
			profile.call("award_xp", 25, "round:" + key + ":win")
			play_ui_sound("success")
		elif room_game_mode == "tag" and not session.call("is_local_tagger"):
			profile.call("award_xp", 15, "round:" + key + ":survive")
			play_ui_sound("success")
		else: play_ui_sound("error")

func _set_frontend_state(state: String) -> void:
	frontend_state = state
	_changing_frontend = true
	_close_feature_menus()
	if account_menu != null: account_menu.set_open(false)
	if is_instance_valid(dev_menu): dev_menu.set_open(false)
	if main_menu != null: main_menu.set_open(state == "main_menu")
	if lobby != null: lobby.set_open(state == "lobby")
	if loading_screen != null and state != "loading": loading_screen.hide_loading()
	_changing_frontend = false
	player.input_allowed = false
	player.reset_tracking_history()
	board.visible = state == "playing"
	desktop_label.visible = state == "playing"

func open_main_menu() -> void:
	if frontend_state == "loading": return
	if _map_creation_active():
		if map_creator.get("playtesting") == true: map_creator.call("stop_playtest")
		else: map_creator.call("request_exit")
		return
	_set_frontend_state("main_menu")

func can_resume_play() -> bool:
	return _resume_available and _ordinary_menus_allowed() and (network_mode == "offline" or session.phase == "playing")

func resume_play() -> void:
	if can_resume_play(): _set_frontend_state("playing")

func open_multiplayer_lobby() -> void:
	if not _ordinary_menus_allowed(): return
	_set_frontend_state("lobby")

func can_open_lobby_menu() -> bool:
	return _ordinary_menus_allowed() and frontend_state in ["lobby", "playing"]

func on_lobby_menu_closed() -> void:
	if can_resume_play(): _set_frontend_state("playing")

func return_to_main_menu() -> void:
	if _map_creation_active():
		map_creator.call("request_exit")
		return
	_loading_generation += 1
	_returning_to_main = true
	session.leave()
	_returning_to_main = false
	_resume_available = false
	_set_frontend_state("main_menu")

func start_solo() -> void:
	if not _ordinary_menus_allowed(): return
	_returning_to_main = true
	session.leave()
	session.call("set_game_mode", "co_op")
	_returning_to_main = false
	_loading_generation += 1
	var generation := _loading_generation
	_set_frontend_state("loading")
	loading_screen.show_loading("Preparing the forest", 0.15)
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _loading_generation or frontend_state != "loading": return
	restart()
	loading_screen.set_progress(1.0, "Forest ready")
	await get_tree().process_frame
	if generation != _loading_generation or frontend_state != "loading": return
	_resume_available = true
	_set_frontend_state("playing")

func start_multiplayer_round() -> void:
	if lobby_can_start: session.start_round()

func on_lobby_phase_changed(phase: String) -> void:
	if _returning_to_main or main_menu == null: return
	if network_mode == "offline":
		_loading_generation += 1
		_set_frontend_state("playing" if _resume_available else "lobby")
	elif phase == "lobby":
		_resume_available = false
		_loading_generation += 1
		_set_frontend_state("lobby")
	elif phase == "loading":
		_prepare_online_round(session.phase_generation)
	elif phase == "playing":
		_finish_online_transition()

func _finish_online_transition() -> void:
	# A newer authoritative snapshot can overtake the loading announcement.
	# Always present local preparation before unlocking a newly started round.
	_loading_generation += 1
	var generation := _loading_generation
	_set_frontend_state("loading")
	loading_screen.show_loading("Forest ready", 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _loading_generation or network_mode == "offline" or session.phase != "playing": return
	_resume_available = true
	_set_frontend_state("playing")

func _prepare_online_round(phase_generation: int) -> void:
	_loading_generation += 1
	var generation := _loading_generation
	_set_frontend_state("loading")
	loading_screen.show_loading("Preparing the shared forest" if session.is_host() else "Waiting for the host", 0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _loading_generation or frontend_state != "loading": return
	if session.is_host(): session.complete_loading(phase_generation)

func on_network_left() -> void:
	# Hosts can reuse round/event IDs. Scope cosmetic rewards to this connection.
	_room_serial += 1
	if _returning_to_main: return
	_loading_generation += 1
	# Disconnects can arrive after the room phase became playing, while the
	# local loading view is still being presented. Always release that view.
	if frontend_state == "loading":
		_resume_available = false
		_set_frontend_state("lobby")
	elif not _resume_available and frontend_state != "main_menu":
		_set_frontend_state("lobby")

func quit_game() -> void:
	if OS.has_feature("android") or frontend_state == "loading": return
	session.leave()
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F8 and not _map_creation_active():
			open_map_creator()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_TAB and network_mode == "offline" and frontend_state != "lobby":
			if frontend_state == "main_menu" and can_resume_play(): resume_play()
			else: open_main_menu()
			get_viewport().set_input_as_handled()

func can_switch_play_mode(mode: String) -> bool:
	if not _ordinary_menus_allowed(): return false
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
	if can_open_account_menu(): account_menu.set_open(true)

func can_open_account_menu() -> bool:
	return _ordinary_menus_allowed()

func open_developer_menu() -> void:
	if can_open_developer_menu(): dev_menu.set_open(true)

func can_open_developer_menu() -> bool:
	return account_is_developer and _ordinary_menus_allowed() and is_instance_valid(dev_menu)

func on_account_menu_open() -> void:
	_changing_frontend = true
	_close_feature_menus()
	lobby.set_open(false)
	main_menu.set_open(false)
	player.input_allowed = false
	if is_instance_valid(dev_menu): dev_menu.set_open(false)
	_changing_frontend = false

func on_account_menu_closed() -> void:
	if _changing_frontend: return
	if frontend_state == "main_menu": main_menu.set_open(true)
	elif frontend_state == "lobby": lobby.set_open(true)

func on_developer_menu_open() -> void:
	_changing_frontend = true
	_close_feature_menus()
	lobby.set_open(false)
	main_menu.set_open(false)
	account_menu.set_open(false)
	_changing_frontend = false
	player.input_allowed = false

func on_developer_menu_closed() -> void:
	on_account_menu_closed()

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
	if profile != null: profile.call("account_changed")
	if not account.error_code.is_empty(): play_ui_sound("error")
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
		if session == null or not session.is_client(): developer_round_paused = false
		developer_bot_speed = 1.0
		if is_instance_valid(developer_tools): developer_tools.call("reset")
	if is_instance_valid(main_menu): main_menu.refresh_status()
	if is_instance_valid(account_menu): account_menu.refresh_status()

func developer_action_allowed(action: String) -> bool:
	if not account_is_developer or not _ordinary_menus_allowed(): return false
	if action in ["respawn", "diagnostics"]: return true
	if action in ["teleport_hub", "teleport_treehouse", "teleport_lookout", "teleport_cave", "place_marker", "clear_markers", "map_bounds"]:
		return is_instance_valid(developer_tools)
	if action not in ["restart", "add_time", "freeze_bots", "tag_all", "pause_round", "bot_speed", "end_round"]: return false
	if action in ["freeze_bots", "tag_all", "bot_speed"] and room_game_mode != "co_op": return false
	if action == "tag_all" and developer_round_paused: return false
	if frontend_state != "playing" or (network_mode != "offline" and session.phase != "playing"): return false
	return session != null and not session.is_client()

func developer_action(action: String) -> void:
	# All UI routes and direct calls use the current verified role and authority.
	if not developer_action_allowed(action): return
	match action:
		"restart":
			restart()
			_developer_message = "Round restarted"
		"add_time":
			if score < bots.size():
				remaining = minf(300, remaining + 30)
				finished = false
				_developer_message = "Added 30 seconds · maximum 300"
		"freeze_bots":
			developer_bots_frozen = not developer_bots_frozen
			_developer_message = "Bots frozen" if developer_bots_frozen else "Bots resumed"
		"tag_all":
			for bot in bots: tag_bot(bot)
			_developer_message = "Tagged all monkeys"
		"respawn":
			player.reset_player()
			_developer_message = "Returned to forest hub"
		"diagnostics":
			diagnostics_enabled = not diagnostics_enabled
			_developer_message = "Diagnostics on" if diagnostics_enabled else "Diagnostics off"
		"pause_round":
			developer_round_paused = not developer_round_paused
			_developer_message = "Round paused · players can explore" if developer_round_paused else "Round resumed"
		"bot_speed":
			developer_bot_speed = 0.65 if developer_bot_speed == 1.0 else (1.4 if developer_bot_speed == 0.65 else 1.0)
			_developer_message = "Bot pace: " + ("Slow" if developer_bot_speed == 0.65 else ("Fast" if developer_bot_speed == 1.4 else "Normal"))
		"end_round":
			remaining = 0.0
			finished = true
			developer_round_paused = false
			_developer_message = "Round ended"
		_:
			_developer_message = str(developer_tools.call("perform", action))
	if session != null and session.is_host(): session._send_snapshot()

func host_session() -> void:
	if not _ordinary_menus_allowed(): return
	session.host()
	if session.is_host(): _set_frontend_state("lobby")

func join_session(address: String) -> void:
	if not _ordinary_menus_allowed(): return
	session.join(address)

func leave_session() -> void:
	if _map_creation_active(): return
	_loading_generation += 1
	_returning_to_main = true
	session.leave()
	_returning_to_main = false
	_resume_available = false
	_set_frontend_state("lobby")

func is_session_host() -> bool:
	return session != null and session.is_host()

func request_restart() -> void:
	if _map_creation_active():
		if frontend_state == "map_playtest": _reset_map_spawn()
		return
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
	head.current = true
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
	if _map_creation_active():
		if frontend_state == "map_playtest": _reset_map_spawn()
		return
	if session != null and session.is_client(): return
	_local_round_serial += 1
	remaining = 90
	score = 0
	finished = false
	player.reset_player()
	for bot in bots: bot.reset_bot()
	last_board = ""
	developer_bots_frozen = false
	developer_round_paused = false
	developer_bot_speed = 1.0
	if is_instance_valid(developer_tools): developer_tools.call("reset")
	_developer_message = "Developer access verified"
	if session != null: session.round_restarted()

func tag_bot(bot: BotScript, tagger := 0) -> void:
	if _map_creation_active(): return
	if frontend_state != "playing" or (session != null and network_mode != "offline" and session.phase != "playing"): return
	if session != null and session.is_client(): return
	if room_game_mode != "co_op": return
	if finished or bot.tagged or developer_round_paused: return
	bot.tag()
	score += 1
	if tagger == 0: tagger = multiplayer.get_unique_id()
	if session != null: session.call("notify_bot_tag", tagger, bots.find(bot))
	else: on_bot_tagged(tagger, bots.find(bot), "solo")
	if score == 5: finished = true

func _physics_process(delta: float) -> void:
	if player == null: return
	if _map_creation_active():
		# Local map tests never advance a shared round or grant account rewards.
		player.input_allowed = xr_focused and frontend_state == "map_playtest"
		if player.input_allowed:
			var body_position := player.global_position + (Vector3(player.head.position.x, 0, player.head.position.z) if player.xr_running else Vector3.ZERO)
			if body_position.y < -10 or absf(body_position.x) > 18 or absf(body_position.z) > 18: _reset_map_spawn()
		for bot in bots:
			bot.visible = false
			bot.active = false
		board.visible = false
		desktop_label.visible = false
		if diagnostics_board != null: diagnostics_board.visible = false
		if is_instance_valid(presentation):
			presentation.call("update_hud", {"visible": frontend_state == "map_playtest" and not player.xr_running and (settings == null or settings.get("hud_visible") == true), "mode": "map_playtest", "title": "MAP PLAYTEST", "map_name": str(map_creator.get("document").data.get("name", "Local map")), "status": "R / right A: respawn", "network": "LOCAL", "profile": profile_summary})
		var reset_pressed: bool = player.hands[1].is_button_pressed("ax_button") if player.xr_running else Input.is_physical_key_pressed(KEY_R)
		if reset_pressed and not restart_held and player.input_allowed: _reset_map_spawn()
		restart_held = reset_pressed
		return
	var menu_open: bool = frontend_state != "playing" or (main_menu != null and main_menu.is_open) or (lobby != null and lobby.is_open) or (account_menu != null and account_menu.is_open) or (is_instance_valid(dev_menu) and dev_menu.is_open) or _feature_open()
	# Opening the public lobby closes any other overlay, so only one menu owns input.
	if lobby != null and lobby.is_open:
		_changing_frontend = true
		_close_feature_menus()
		if account_menu != null and account_menu.is_open: account_menu.set_open(false)
		if is_instance_valid(dev_menu) and dev_menu.is_open: dev_menu.set_open(false)
		_changing_frontend = false
	player.input_allowed = xr_focused and not menu_open and (network_mode == "offline" or session.phase == "playing")
	var pressed: bool = (xr_focused and player.hands[1].is_button_pressed("ax_button")) if player.xr_running else Input.is_physical_key_pressed(KEY_R)
	if pressed and not restart_held and player.input_allowed: request_restart()
	restart_held = pressed
	var poses: Array = session.participant_poses() if session != null else []
	var active := not poses.is_empty()
	var authority := session == null or not session.is_client()
	for bot in bots:
		bot.visible = room_game_mode == "co_op"
		bot.active = room_game_mode == "co_op" and authority and active and not finished and not developer_bots_frozen and not developer_round_paused
		bot.speed_multiplier = developer_bot_speed if authority else 1.0
		bot.use_network_target = session != null and session.is_host()
		if bot.use_network_target:
			var closest := INF
			for pose in poses:
				var distance: float = bot.global_position.distance_squared_to(pose.head)
				if distance < closest:
					closest = distance
					bot.chase_position = pose.head
	if authority and active and not finished and not developer_round_paused:
		remaining = maxf(0, remaining - delta)
		for bot in bots:
			if room_game_mode != "co_op": break
			if bot.tagged: continue
			var target: Vector3 = bot.global_position + Vector3.UP * 0.7
			for pose in poses:
				if pose.vr:
					if pose.left.distance_to(target) < 0.65 or pose.right.distance_to(target) < 0.65: tag_bot(bot, int(pose.get("peer_id", multiplayer.get_unique_id())))
				elif pose.tag and pose.head.distance_to(target) < 1.7: tag_bot(bot, int(pose.get("peer_id", multiplayer.get_unique_id())))
		if remaining <= 0: finished = true
	_update_progress()
	var show_hud := settings == null or bool(settings.get("hud_visible"))
	board.visible = frontend_state == "playing" and show_hud and (player.xr_running or not is_instance_valid(presentation))
	desktop_label.visible = frontend_state == "playing" and show_hud and not player.xr_running and not is_instance_valid(presentation)
	var title := "ALL MONKEYS TAGGED!" if score == 5 else ("TIME'S UP!" if finished else "FOREST CHASE")
	if room_game_mode == "tag": title = "TIME'S UP!" if finished else ("YOU ARE IT!" if session.call("is_local_tagger") else "RUN FROM THE ORANGE MONKE")
	var status := "Push surfaces to move. Touch monkeys to tag." if player.xr_running else "WASD / right mouse: look / Space / E: tag"
	if developer_round_paused: status = "Round paused by developer · explore the forest"
	if not active: status = "Paused — close menu / restore headset + controller tracking"
	status += "\nRight B / Tab: menu · F1: main menu · " + network_mode
	if session != null and session.is_client(): status += " · Host restarts"
	else: status += " · Right A / R: restart"
	if not play_mode_notice.is_empty(): status += "\n" + play_mode_notice
	if account_is_developer: status += "\nDeveloper tools: F2 / left Y · Account: F3 / left X"
	status += "\n" + profile_summary
	if voice != null and voice.get("enabled") == true: status += "\n" + str(voice.get("status"))
	var diagnostics := "%s FPS · %s · Tracking %s\nPosition %s\nRound %s / 5 · %ss" % [Engine.get_frames_per_second(), network_mode, player.tracked, player.global_position.snapped(Vector3.ONE * 0.1), score, ceili(remaining)]
	if diagnostics_enabled and not account_is_developer: diagnostics_enabled = false
	if diagnostics_board != null:
		diagnostics_board.visible = diagnostics_enabled and player.xr_running
		diagnostics_board.text = diagnostics
	var text := "PRIMAL MONKE\n%s\n%s / 5 TAGGED     %ss\n%s" % [title, score, ceili(remaining), status]
	if room_game_mode == "tag": text = "PRIMAL MONKE\n%s\n%s · %ss\n%s" % [title, session.call("player_tag_summary"), ceili(remaining), status]
	if text != last_board:
		board.text = text
		desktop_label.text = text
		last_board = text
	desktop_label.text = text + ("\n" + diagnostics if diagnostics_enabled else "")
	if is_instance_valid(presentation):
		var hud_status := "Round paused by developer · explore the forest" if developer_round_paused else ""
		if not active: hud_status = "Paused · close menu / restore headset tracking"
		if not play_mode_notice.is_empty(): hud_status += ("\n" if not hud_status.is_empty() else "") + play_mode_notice
		if voice != null and voice.get("enabled") == true: hud_status += ("\n" if not hud_status.is_empty() else "") + str(voice.get("status"))
		presentation.call("update_hud", {"visible": frontend_state == "playing" and show_hud and not player.xr_running, "mode": room_game_mode, "title": title, "score": score, "remaining": remaining, "finished": finished, "network": network_mode, "profile": profile_summary, "status": hud_status, "tag_summary": str(session.call("player_tag_summary")) if room_game_mode == "tag" else "", "diagnostics": diagnostics if diagnostics_enabled else ""})
