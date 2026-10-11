extends SceneTree

# Real player, audio, and overlay controls with isolated local preferences.
# Headless startup never contacts an account service or opens a microphone.
var checks := 0
var failures := 0
var scratch := ""
var backups: Dictionary = {}

class ScratchSettings:
	extends "res://scripts/settings_state.gd"
	var path := ""
	func _preference_path() -> String:
		return path

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func settle(frames := 3) -> void:
	for index in range(frames): await physics_frame

func replace_settings(game: Node3D) -> ScratchSettings:
	var old: Node = game.settings
	var settings := ScratchSettings.new()
	settings.path = scratch
	settings.game = game
	game.settings = settings
	game.add_child(settings)
	old.queue_free()
	return settings

func backup_preferences() -> void:
	for path in ["user://primal_monke_settings.cfg", "user://primal_monke_audio.cfg"]:
		backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null

func restore_preferences() -> void:
	for path in backups:
		if backups[path] is PackedByteArray:
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null: file.store_buffer(backups[path])
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func open_count(game: Node3D) -> int:
	var count := 0
	for menu in [game.main_menu, game.lobby, game.account_menu, game.profile_menu, game.voice_menu, game.tutorial, game.settings_menu, game.dev_menu]:
		if is_instance_valid(menu) and menu.is_open: count += 1
	return count

func run() -> void:
	scratch = "/tmp/primal-monke-settings-%s-%s.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	backup_preferences()
	var game = load("res://forest.tscn").instantiate()
	root.add_child(game)
	await settle()
	check(is_instance_valid(game.settings) and is_instance_valid(game.settings_menu), "forest creates local settings and both menu presentations")
	check(not game.voice.enabled and game.voice.mic_muted and not game.account.busy, "settings startup leaves microphone and account provider idle")
	# Absent settings file adopts the former audio preference values.
	game.sounds.set_gain(0.4)
	game.sounds.set_ambience_gain(0.25)
	game.sounds.set_muted(true)
	var settings := replace_settings(game)
	await settle()
	check(is_equal_approx(settings.effects_volume, 0.4) and is_equal_approx(settings.ambience_volume, 0.25) and settings.muted, "first settings launch preserves existing effect, ambience, and mute choices")
	check(FileAccess.file_exists(scratch), "migrated settings are saved to the local preference file")
	await test_actual_controls(game, settings)
	await test_restore_and_malformed(game)
	await test_menu_routes(game)
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(scratch)
	restore_preferences()
	print("Settings checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_actual_controls(game: Node3D, settings: ScratchSettings) -> void:
	settings.set_value("effects_volume", 0.8)
	settings.set_value("ambience_volume", 0.1)
	settings.set_value("muted", false)
	var expected_effects: float = game.sounds.MASTER_DB + linear_to_db(0.8)
	var expected_ambience: float = game.sounds.MASTER_DB + linear_to_db(0.1) - 15.0
	check(is_equal_approx(game.sounds.gain, 0.8) and is_equal_approx(game.sounds.ambience_gain, 0.1), "independent sound settings reach the actual audio component")
	check(is_equal_approx(game.sounds._flat_voices[0].volume_db, expected_effects) and is_equal_approx(game.sounds._spatial_voices[0].volume_db, expected_effects), "effects volume updates both flat and spatial cue players")
	check(is_equal_approx(game.sounds._ambience.volume_db, expected_ambience), "ambience volume uses its own gain rather than effects gain")
	var previous_ambience: float = game.sounds._ambience.volume_db
	settings.set_value("effects_volume", 0.0)
	check(is_equal_approx(game.sounds._ambience.volume_db, previous_ambience), "muting effect volume alone leaves forest ambience unchanged")
	settings.set_value("mouse_sensitivity", 1.8)
	settings.set_value("invert_y", true)
	settings.set_value("look_fov", 95.0)
	check(is_equal_approx(game.player.mouse_sensitivity, 1.8) and game.player.invert_y and is_equal_approx(game.player.head.fov, 95.0), "saved mouse settings and field of view reach the real player camera")
	game.player.input_allowed = true
	game.player.desktop_yaw = 0.0
	game.player.desktop_pitch = 0.0
	# The headless display cannot capture a system mouse. Exercise the real
	# player's mouse-look operation with the same relative motion input uses.
	game.player._apply_mouse_look(Vector2(10, 20))
	check(is_equal_approx(game.player.desktop_yaw, -0.072) and is_equal_approx(game.player.desktop_pitch, 0.144), "player mouse-look scales relative movement and respects inverted Y")
	settings.set_value("invert_y", false)
	game.player.desktop_pitch = 0.0
	game.player._apply_mouse_look(Vector2(0, 20))
	check(is_equal_approx(game.player.desktop_pitch, -0.144), "turning off inverted Y restores normal mouse-look direction")
	settings.set_value("invert_y", true)
	game.player.input_allowed = false
	game.start_solo()
	for index in range(120):
		if game.frontend_state == "playing": break
		await process_frame
	settings.set_value("hud_visible", false)
	await settle()
	check(not game.desktop_label.visible and not game.board.visible and not game.presentation._canvas.visible, "HUD preference hides the actual desktop and world round overlays")
	settings.set_value("hud_visible", true)
	await settle()
	check(game.presentation._canvas.visible and not game.desktop_label.visible and not game.board.visible, "HUD preference restores the desktop card without duplicate round overlays")
	game.return_to_main_menu()
	check(not settings.can_set_fullscreen() and not game.settings_menu._action_enabled("fullscreen"), "headless settings disable unsupported fullscreen changes")
	check(not game.voice.enabled and game.voice.mic_muted, "audio and display changes do not enable voice or unmute a microphone")
	var saved := FileAccess.get_file_as_string(scratch)
	check(not saved.contains("password") and not saved.contains("ticket") and not saved.contains("account_id"), "persisted preferences contain no account identity or credentials")

func test_restore_and_malformed(game: Node3D) -> void:
	var settings := replace_settings(game)
	await settle()
	check(is_equal_approx(settings.mouse_sensitivity, 1.8) and settings.invert_y and is_equal_approx(settings.look_fov, 95.0), "relaunch restores saved mouse and view preferences")
	check(is_equal_approx(settings.effects_volume, 0.0) and is_equal_approx(settings.ambience_volume, 0.1) and not settings.muted, "relaunch restores independent audio choices")
	check(is_equal_approx(game.player.head.fov, 95.0) and is_equal_approx(game.sounds.ambience_gain, 0.1), "restored settings are applied rather than only displayed")
	var malformed := ConfigFile.new()
	malformed.set_value("settings", "effects_volume", 250.0)
	malformed.set_value("settings", "ambience_volume", -15.0)
	malformed.set_value("settings", "mouse_sensitivity", "not a number")
	malformed.set_value("settings", "look_fov", 10000.0)
	malformed.set_value("settings", "muted", "false")
	malformed.set_value("settings", "invert_y", [true])
	malformed.set_value("settings", "hud_visible", 0)
	malformed.set_value("settings", "fullscreen", {"enabled": true})
	malformed.save(scratch)
	settings = replace_settings(game)
	await settle()
	check(settings.effects_volume == 1.0 and settings.ambience_volume == 0.0 and settings.look_fov == 100.0, "out of bounds persisted numbers clamp safely")
	check(settings.mouse_sensitivity == 1.0 and not settings.invert_y and settings.hud_visible and not settings.fullscreen and not settings.muted, "wrong persisted types fall back without casting strings or containers")
	settings.set_value("mouse_sensitivity", NAN)
	settings.set_value("look_fov", INF)
	settings.set_value("ambience_volume", "loud")
	settings.set_value("muted", "yes")
	check(settings.mouse_sensitivity == 1.0 and settings.look_fov == 100.0 and settings.ambience_volume == 0.0 and not settings.muted, "runtime nonfinite and wrong typed values cannot corrupt preferences")
	check(not settings.set_value("account_id", "ignored"), "unknown preference keys are rejected")
	settings.reset_defaults()
	check(settings.effects_volume == 1.0 and settings.ambience_volume == 1.0 and settings.mouse_sensitivity == 1.0 and settings.look_fov == 75.0 and settings.hud_visible and not settings.invert_y and not settings.muted, "restore defaults resets the full preference set")
	check(game.player.head.fov == 75.0 and game.player.mouse_sensitivity == 1.0 and game.sounds.gain == 1.0 and game.sounds.ambience_gain == 1.0, "restore defaults updates real controls and audio immediately")

func test_menu_routes(game: Node3D) -> void:
	var menu: Node3D = game.settings_menu
	game.main_menu._desktop_buttons.settings.pressed.emit()
	await settle()
	check(menu.is_open and open_count(game) == 1 and not game.player.input_allowed, "main settings button opens one overlay and pauses local input")
	menu._desktop_buttons.effects_down.pressed.emit()
	menu._desktop_buttons.ambience_down.pressed.emit()
	menu._desktop_buttons.sensitivity_up.pressed.emit()
	menu._desktop_buttons.invert.pressed.emit()
	check(is_equal_approx(game.settings.effects_volume, 0.9) and is_equal_approx(game.settings.ambience_volume, 0.9) and is_equal_approx(game.player.mouse_sensitivity, 1.1) and game.player.invert_y, "desktop settings buttons update real preferences and controls")
	menu._desktop_buttons.voice.pressed.emit()
	check(game.voice_menu.is_open and not menu.is_open and open_count(game) == 1 and not game.voice.enabled, "voice controls route replaces settings without enabling a microphone")
	game.voice_menu.set_open(false)
	var key := InputEventKey.new()
	key.keycode = KEY_F7
	key.physical_keycode = KEY_F7
	key.pressed = true
	menu._input(key)
	check(menu.is_open and open_count(game) == 1 and menu.toggle_hand == -1, "F7 opens settings without reusing a controller shortcut")
	menu._desktop_buttons.close.pressed.emit()
	check(game.main_menu.is_open and not menu.is_open, "settings Back action restores the underlying main screen")
	game.open_settings_menu()
	game.open_account_menu()
	check(game.account_menu.is_open and not menu.is_open and open_count(game) == 1, "account opening replaces settings rather than stacking overlays")
	game.account_menu.set_open(false)
	game.player.xr_running = true
	game.open_settings_menu()
	await settle()
	check(menu._world_panel.visible and not menu._canvas.visible, "headset settings use the world panel rather than desktop controls")
	check(not menu._action_enabled("sensitivity_up") and not menu._action_enabled("invert") and not menu._action_enabled("fov_up") and not menu._action_enabled("fullscreen"), "VR settings disable PC mouse, projection, and fullscreen actions")
	var old_fov: float = game.player.head.fov
	var old_sensitivity: float = game.player.mouse_sensitivity
	menu._dispatch("sensitivity_up")
	menu._dispatch("fov_up")
	check(game.player.mouse_sensitivity == old_sensitivity and game.player.head.fov == old_fov, "disabled PC actions cannot change controls through direct VR dispatch")
	var previous_effects: float = game.settings.effects_volume
	menu._dispatch("effects_down")
	check(game.settings.effects_volume < previous_effects, "headset settings retain working audio controls")
	var bounds := Rect2(-menu.panel_size * 0.5, menu.panel_size)
	var reachable := true
	var inside := true
	for index in range(menu._world_buttons.size()):
		var rect: Rect2 = menu._world_buttons[index].rect
		inside = inside and bounds.encloses(rect)
		var center := rect.get_center()
		var target: Vector3 = menu._world_panel.to_global(Vector3(center.x, center.y, 0))
		var normal: Vector3 = menu._world_panel.global_basis.z
		var hit: Dictionary = menu._intersect_panel(target + normal, -normal)
		reachable = reachable and hit.get("button", -1) == index
	check(inside and reachable, "all VR settings buttons fit the panel and accept front-facing controller rays")
	menu._dispatch("close")
	game.player.xr_running = false
	await settle()
	game.start_solo()
	game.open_settings_menu()
	menu.set_open(true)
	var previous_ambience: float = game.settings.ambience_volume
	menu._dispatch("ambience_down")
	check(game.frontend_state == "loading" and not menu.is_open and game.settings.ambience_volume == previous_ambience, "loading guards root, direct opening, and direct settings dispatch")
	game.return_to_main_menu()
	await settle(8)
	check(game.main_menu.is_open and not menu.is_open and not game.loading_screen._shown, "cancelled loading restores main without a stale settings overlay")
