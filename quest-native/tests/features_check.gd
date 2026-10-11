extends SceneTree

# Integrate the real forest and menu controls. Provider calls are overridden;
# profile/onboarding writes use unique files in /tmp, and no UDP port is used.
var checks := 0
var failures := 0
var scratch_prefix := ""
var account: MockAccount
var profile: ScratchProfile

class MockAccount:
	extends "res://scripts/playfab_account.gd"
	var calls: Array[String] = []
	func _device_identity() -> String:
		return "PM-" + "1234567890abcdef".repeat(4)
	func _request(api: String, _payload: Dictionary, _ticket := "") -> Dictionary:
		calls.append(api)
		await get_tree().process_frame
		return {"ok": false}

class ScratchProfile:
	extends "res://scripts/profile_state.gd"
	var storage_prefix := ""
	func _storage_path(identity: String) -> String:
		return storage_prefix + "_" + ("guest" if identity.is_empty() else identity.sha256_text().left(16)) + ".json"

class ScratchOnboarding:
	extends "res://scripts/onboarding.gd"
	var preference_path := ""
	func _preference_path() -> String:
		return preference_path
	func _can_present() -> bool:
		return true

class MockSession:
	extends "res://scripts/crossplay.gd"
	var next_game_mode := "co_op"
	func join(_ip: String) -> void:
		leave()
		mode = "connected"
		phase = "lobby"
		var state: Array = []
		for bot in game.bots: state.append([bot.global_position, bot.rotation.y, false])
		apply_snapshot({"sequence": 1, "round": 7, "remaining": 80.0, "score": 1 if next_game_mode == "co_op" else 0,
			"finished": false, "bots": state, "players": {}, "phase": "playing", "game_mode": next_game_mode})
	func publish_profile(value: Dictionary) -> bool:
		local_profile = value.duplicate(true)
		return true
	func _physics_process(_delta: float) -> void:
		# Transport-only work is covered by the real multi-process suites.
		pass

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func settle(frames := 4) -> void:
	for index in range(frames): await physics_frame

func wait_state(game: Node, expected: String) -> bool:
	for index in range(120):
		if game.get("frontend_state") == expected: return true
		await process_frame
	return false

func open_count(game: Node3D) -> int:
	var total := 0
	for menu in [game.main_menu, game.lobby, game.account_menu, game.profile_menu, game.voice_menu, game.tutorial, game.dev_menu]:
		if is_instance_valid(menu) and menu.get("is_open") == true: total += 1
	return total

func replace_isolated_state(game: Node3D) -> void:
	var old_account = game.account
	var old_profile = game.profile
	var old_onboarding = game.onboarding
	old_account.state_changed.disconnect(game._account_changed)
	old_profile.public_profile_changed.disconnect(game._profile_changed)
	account = MockAccount.new()
	game.account = account
	game.add_child(account)
	account.state_changed.connect(game._account_changed)
	profile = ScratchProfile.new()
	profile.storage_prefix = scratch_prefix
	profile.game = game
	game.profile = profile
	game.add_child(profile)
	profile.public_profile_changed.connect(game._profile_changed)
	profile.account_changed()
	old_account.queue_free()
	old_profile.queue_free()
	old_onboarding.queue_free()
	var flow := ScratchOnboarding.new()
	flow.preference_path = scratch_prefix + ".cfg"
	flow.game = game
	game.onboarding = flow
	game.add_child(flow)
	await process_frame

func run() -> void:
	scratch_prefix = "/tmp/primal-monke-features-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var game = load("res://forest.tscn").instantiate()
	root.add_child(game)
	await settle()
	check(is_instance_valid(game.profile) and is_instance_valid(game.profile_menu) and is_instance_valid(game.voice) and is_instance_valid(game.voice_menu) and is_instance_valid(game.tutorial) and is_instance_valid(game.sounds) and is_instance_valid(game.onboarding), "forest instantiates profile, voice, tutorial, sound, and onboarding components")
	check(game.main_menu.is_open and not game.account.busy and not game.account.is_signed_in() and not game.onboarding._prompting, "headless startup stays at main without automatic account creation or onboarding input")
	check(not game.voice.enabled and game.voice.mic_muted and game.voice._capture == null and game.voice._microphone == null, "voice starts off without opening microphone capture")
	var audio_idle: bool = not game.sounds._ambience.playing
	var audio_loaded := true
	for player in game.sounds._flat_voices + game.sounds._spatial_voices:
		audio_idle = audio_idle and not player.playing
	for stream in game.sounds._streams.values(): audio_loaded = audio_loaded and stream != null
	check(audio_idle and audio_loaded, "headless forest loads original cues without starting sound playback")
	await replace_isolated_state(game)
	await check_climbables(game)
	await check_menu_routes(game)
	await check_progress_and_tutorial(game)
	await check_tag_world_and_solo_reset(game)
	await check_cross_room_rewards(game)
	await check_loading_guards(game)
	await check_onboarding_routes(game)
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	for name in DirAccess.get_files_at("/tmp"):
		if name.begins_with(scratch_prefix.get_file()): DirAccess.remove_absolute("/tmp/" + name)
	print("Feature integration checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check_climbables(game: Node3D) -> void:
	var deck_query := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 9), Vector3(0, 2, 9), 1)
	var deck: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(deck_query)
	check(not deck.is_empty() and deck.collider.name == "TreehouseDeck" and deck.position.y > 2.8, "treehouse deck provides a real elevated collision surface")
	var step_query := PhysicsRayQueryParameters3D.create(Vector3(5, 5, 7.6), Vector3(5, 1, 7.6), 1)
	var step: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(step_query)
	check(not step.is_empty() and str(step.collider.name).begins_with("ClimbStep"), "new stepping route has colliders the player can climb")

func check_menu_routes(game: Node3D) -> void:
	for action in ["profile", "voice", "tutorial"]:
		var menu: Node3D = game.get("tutorial" if action == "tutorial" else action + "_menu")
		game.main_menu._desktop_buttons[action].pressed.emit()
		await settle()
		check(menu.is_open and open_count(game) == 1 and not game.player.input_allowed, "main %s button opens one overlay and pauses player input" % action)
		menu._desktop_buttons["close"].pressed.emit()
		check(game.main_menu.is_open and not menu.is_open and open_count(game) == 1, "closing %s restores the underlying main menu" % action)
	game.main_menu._desktop_buttons["profile"].pressed.emit()
	game.profile_menu._set_name("Feature Monke")
	game.profile_menu._desktop_buttons["save"].pressed.emit()
	check(profile.display_name == "Feature Monke" and game.session.local_profile.get("name") == "Feature Monke" and game.profile_summary.contains("Feature Monke"), "profile save updates the forest summary and public room profile")
	game.open_voice_menu()
	check(game.voice_menu.is_open and not game.profile_menu.is_open and open_count(game) == 1, "voice replaces an open profile overlay without sharing input")
	game.voice_menu._desktop_buttons["enable"].pressed.emit()
	game.voice_menu._desktop_buttons["mic"].pressed.emit()
	await settle()
	check(game.voice.enabled and not game.voice.mic_muted and game.voice._capture == null and game.voice._microphone == null, "explicit voice controls remain unable to capture a microphone in an offline headless run")
	game.voice_menu._desktop_buttons["enable"].pressed.emit()
	game.open_account_menu()
	check(game.account_menu.is_open and not game.voice_menu.is_open and open_count(game) == 1 and game.voice.mic_muted, "account replaces voice while disabling voice remutes the microphone")
	game.account_menu.set_open(false)
	game.start_solo()
	check(await wait_state(game, "playing"), "feature-menu checks can start solo through the real loading path")
	await settle()
	var paused_time: float = game.remaining
	game.open_profile_menu()
	await settle(8)
	check(game.profile_menu.is_open and not game.player.input_allowed and game.remaining == paused_time, "profile overlay pauses the current solo countdown")
	game.profile_menu.set_open(false)
	await settle(8)
	check(game.frontend_state == "playing" and game.player.input_allowed and game.remaining < paused_time, "closing a feature overlay restores input and resumes the same solo round")

func check_progress_and_tutorial(game: Node3D) -> void:
	game.restart()
	await settle()
	var initial_xp: int = profile.xp
	var initial_tags: int = game.local_tag_count
	game.tag_bot(game.bots[0])
	game.tag_bot(game.bots[0])
	await settle()
	check(game.score == 1 and game.local_tag_count == initial_tags + 1 and profile.xp == initial_xp + 10, "one accepted solo tag awards ten XP and increments local tutorial tags exactly once")
	for index in range(1, game.bots.size()): game.tag_bot(game.bots[index])
	await settle()
	check(game.finished and game.score == 5 and profile.xp == initial_xp + 75, "five tags award fifty XP plus one completion reward")
	await settle(8)
	game._update_progress()
	check(profile.xp == initial_xp + 75, "finished round frames cannot duplicate XP or the win reward")
	game.restart()
	await settle()
	check(game.score == 0 and not game.finished and profile.xp == initial_xp + 75, "round restart resets gameplay without granting old rewards again")
	game.tag_bot(game.bots[0])
	await settle()
	check(profile.xp == initial_xp + 85 and game.local_tag_count == initial_tags + 6, "new solo round receives fresh tag rewards after event-cache reset")
	game.restart()
	game.open_tutorial_menu()
	game.tutorial.lesson = 3
	game.tutorial.refresh_status()
	game.tutorial._desktop_buttons["try"].pressed.emit()
	await settle()
	var lesson_tags: int = game.local_tag_count
	game.tag_bot(game.bots[0], 2)
	await settle()
	check(game.score == 1 and game.local_tag_count == lesson_tags and game.tutorial.practice_active and not game.tutorial._exercise_done, "a teammate's accepted tag changes shared score but does not complete local tag practice")
	game.tag_bot(game.bots[1])
	await settle()
	check(game.local_tag_count == lesson_tags + 1 and game.tutorial._exercise_done and game.tutorial.is_open and not game.tutorial.practice_active, "locally attributed accepted tag completes the real tutorial exercise")
	game.tutorial._desktop_buttons["close"].pressed.emit()
	game.return_to_main_menu()

func check_tag_world_and_solo_reset(game: Node3D) -> void:
	game.open_multiplayer_lobby()
	game.cycle_room_mode()
	check(game.room_game_mode == "tag" and game.room_mode_label.contains("Player Tag"), "offline lobby mode action selects player tag")
	game.restart()
	game._set_frontend_state("playing")
	await settle(8)
	var bots_hidden := true
	for bot in game.bots: bots_hidden = bots_hidden and not bot.visible and not bot.active
	check(bots_hidden and game.remaining < 90.0, "player-tag world hides chase bots while advancing its round clock")
	var prior_score: int = game.score
	game.tag_bot(game.bots[0])
	check(game.score == prior_score and not game.bots[0].tagged, "player-tag rounds cannot accept co-op bot tags")
	var initial_xp: int = profile.xp
	var initial_tags: int = game.local_tag_count
	var local_id: int = game.multiplayer.get_unique_id()
	game.session._emit_player_tag(game.session.round_id, 1, local_id, 2)
	game.session._emit_player_tag(game.session.round_id, 1, local_id, 2)
	game.session._emit_player_tag(game.session.round_id, 2, 2, local_id)
	check(profile.xp == initial_xp + 20 and game.local_tag_count == initial_tags + 1, "accepted player-tag event awards only its local tagger once")
	game.finished = true
	game._update_progress()
	game._update_progress()
	check(profile.xp == initial_xp + 35, "non-tagger survival reward is granted once when player-tag time ends")
	game.return_to_main_menu()
	game.main_menu._desktop_buttons["solo"].pressed.emit()
	check(await wait_state(game, "playing"), "solo starts after leaving player-tag selection")
	await settle()
	var bots_restored := true
	for bot in game.bots: bots_restored = bots_restored and bot.visible and not bot.tagged
	check(game.room_game_mode == "co_op" and bots_restored and game.score == 0 and game.remaining > 89.0, "solo explicitly restores co-op bots and a fresh round after player tag")
	game.return_to_main_menu()

func check_cross_room_rewards(game: Node3D) -> void:
	var old_session = game.session
	old_session.queue_free()
	var session := MockSession.new()
	session.game = game
	game.session = session
	game.add_child(session)
	await process_frame
	var initial_xp: int = profile.xp
	game.join_session("192.0.2.1")
	check(await wait_state(game, "playing"), "first mocked room applies an authoritative round through local loading")
	await settle()
	var local_id: int = game.multiplayer.get_unique_id()
	game._update_progress()
	check(profile.xp == initial_xp + 10, "first co-op room score rewards once despite repeated progress updates")
	game.leave_session()
	game.join_session("192.0.2.2")
	check(await wait_state(game, "playing"), "second mocked room can reuse another host's authoritative round number")
	await settle()
	game._update_progress()
	check(profile.xp == initial_xp + 20, "different co-op rooms with matching round numbers each grant their own score reward")
	game.leave_session()
	session.next_game_mode = "tag"
	game.join_session("192.0.2.3")
	check(await wait_state(game, "playing"), "mocked player-tag room enters play through the same loading route")
	await settle()
	session._emit_player_tag(7, 1, local_id, 2)
	session._emit_player_tag(7, 1, local_id, 2)
	check(profile.xp == initial_xp + 40, "first player-tag room awards its accepted event once")
	game.leave_session()
	game.join_session("192.0.2.4")
	check(await wait_state(game, "playing"), "second player-tag room can reuse another host's event numbers")
	await settle()
	session._emit_player_tag(7, 1, local_id, 2)
	session._emit_player_tag(7, 1, local_id, 2)
	check(profile.xp == initial_xp + 60, "different player-tag rooms with matching round and event numbers each grant XP without duplicates")
	game.return_to_main_menu()

func check_loading_guards(game: Node3D) -> void:
	game.start_solo()
	game.open_profile_menu()
	game.open_voice_menu()
	game.open_tutorial_menu()
	game.profile_menu.set_open(true)
	game.voice_menu.set_open(true)
	game.tutorial.set_open(true)
	check(game.frontend_state == "loading" and not game.profile_menu.is_open and not game.voice_menu.is_open and not game.tutorial.is_open, "loading rejects both root feature actions and direct menu opening")
	game.return_to_main_menu()
	await settle(8)
	check(game.frontend_state == "main_menu" and game.main_menu.is_open and not game.loading_screen._shown and not game._feature_open(), "canceling loading restores main without delayed feature overlays")

func check_onboarding_routes(game: Node3D) -> void:
	var flow: ScratchOnboarding = game.onboarding
	flow.begin_if_needed()
	check(game.account_menu.is_open and game.account_menu.first_time and game.account_menu._submission_action == "register" and not game.main_menu.is_open, "fresh onboarding opens the real account form in create-account mode")
	check(game.account_menu._desktop_buttons["close"].text == "Continue as guest" and account.calls.is_empty(), "first-launch guest choice is available without registering an account")
	game.account_menu._desktop_buttons["close"].pressed.emit()
	await settle()
	check(flow.completed and not flow.registered and game.tutorial.is_open and not game.account_menu.is_open and account.calls.is_empty(), "guest choice persists onboarding and opens the replayable tutorial without provider requests")
	var saved := FileAccess.get_file_as_string(flow.preference_path)
	check(saved.contains("completed=true") and saved.contains("registered=false") and not saved.contains("password") and not saved.contains("SessionTicket") and not saved.contains("CustomId"), "scratch onboarding preferences contain UI choices without account credentials")
	game.tutorial.set_open(false)
	var preferences := ConfigFile.new()
	preferences.set_value("welcome", "completed", true)
	preferences.set_value("welcome", "registered", true)
	preferences.save(flow.preference_path)
	var path := flow.preference_path
	flow.queue_free()
	var returning := ScratchOnboarding.new()
	returning.preference_path = path
	returning.game = game
	game.onboarding = returning
	game.add_child(returning)
	returning.begin_if_needed()
	check(returning.should_skip_auto_device_login() and game.account_menu.is_open and not game.account_menu.first_time and game.account_menu._submission_action == "login", "returning registered player gets explicit sign-in rather than a new anonymous account")
	game.account_menu.set_open(false)
	check(returning.registered and account.calls.is_empty(), "closing returning sign-in preserves the registered preference without provider traffic")
	account._ticket = "feature-check-only-ticket"
	account.account_id = "AABBCCDDEEFF0011"
	account.username = "FeaturePlayer"
	account.has_credentials = true
	account.state_changed.emit()
	await settle()
	check(returning.completed and returning.registered and profile._bound_id == account.account_id and account.calls == ["GetUserData"], "verified account signal binds the isolated profile and completes returning onboarding through a mocked cloud read")
