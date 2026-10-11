extends SceneTree

const TutorialScript = preload("res://scripts/tutorial_menu.gd")
const SoundsScript = preload("res://scripts/game_sounds.gd")
var checks := 0
var failures := 0

class TestOnboarding:
	extends "res://scripts/onboarding.gd"
	func _preference_path() -> String:
		return "user://primal_monke_onboarding_test.cfg"
	func _can_present() -> bool:
		return true

class MockAccount:
	extends Node
	signal state_changed
	var has_credentials := false
	var busy := false
	var signed_in := false
	func is_signed_in() -> bool:
		return signed_in

class MockAccountMenu:
	extends Node
	var first_time := false
	var mode := "register"
	func set_first_time(value: bool) -> void:
		first_time = value
	func select_mode(value: String) -> void:
		mode = value

class MockPlayer:
	extends Node3D
	var head: Node3D
	var xr_running := false
	var input_allowed := true
	var contacts := false
	var velocity := Vector3.ZERO
	var hands: Array = []
	func reset_tracking_history() -> void:
		pass

class MockGame:
	extends Node3D
	var player: MockPlayer
	var account: MockAccount
	var account_menu: MockAccountMenu
	var frontend_state := "main_menu"
	var frontend_status := ""
	var network_mode := "offline"
	var score := 0
	var local_tag_count := 0
	var finished := false
	var xr_focused := true
	var account_opens := 0
	var tutorial_opens := 0
	var solo_starts := 0
	var cues: Array[String] = []
	func _ready() -> void:
		player = MockPlayer.new()
		player.head = Node3D.new()
		player.add_child(player.head)
		add_child(player)
		account = MockAccount.new()
		add_child(account)
		account_menu = MockAccountMenu.new()
		add_child(account_menu)
	func open_account_menu() -> void:
		account_opens += 1
	func open_tutorial_menu() -> void:
		tutorial_opens += 1
	func on_feature_menu_open(_menu: Node) -> void:
		player.input_allowed = false
	func close_feature_menu(_menu: Node) -> void:
		player.input_allowed = true
	func can_resume_play() -> bool:
		return frontend_state == "playing"
	func resume_play() -> void:
		player.input_allowed = true
	func start_solo() -> void:
		solo_starts += 1
		finished = false
		score = 0
		frontend_state = "playing"
		player.input_allowed = true
	func play_ui_sound(cue: String) -> void:
		cues.append(cue)

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func run() -> void:
	var backups := {}
	for path in [SoundsScript.PREFERENCE_PATH, TutorialScript.PREFERENCE_PATH]:
		if FileAccess.file_exists(path): backups[path] = FileAccess.get_file_as_bytes(path)
	var onboarding_path := "user://primal_monke_onboarding_test.cfg"
	DirAccess.remove_absolute(onboarding_path)
	var game := MockGame.new()
	root.add_child(game)
	await process_frame
	await check_onboarding(game)
	await check_tutorial(game)
	await check_sounds(game)
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(onboarding_path)
	for path in [SoundsScript.PREFERENCE_PATH, TutorialScript.PREFERENCE_PATH]:
		if backups.has(path):
			var restore := FileAccess.open(path, FileAccess.WRITE)
			restore.store_buffer(backups[path])
		else:
			DirAccess.remove_absolute(path)
	print("Tutorial and sound checks complete: %s checks, %s failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check_onboarding(game: MockGame) -> void:
	var flow := TestOnboarding.new()
	flow.game = game
	game.add_child(flow)
	check(flow.should_skip_auto_device_login(), "first launch skips automatic anonymous account creation")
	flow.begin_if_needed()
	check(game.account_opens == 1 and game.account_menu.first_time, "first launch presents Create account before opening account menu")
	flow.begin_if_needed()
	check(game.account_opens == 1, "welcome prompt cannot duplicate itself")
	game.account.busy = true
	game.account.has_credentials = true
	game.account.signed_in = true
	game.account.state_changed.emit()
	check(not flow.completed, "onboarding waits for registration verification to finish")
	game.account.busy = false
	game.account.state_changed.emit()
	check(flow.completed and flow.registered and not game.account_menu.first_time, "verified credential account completes first-launch onboarding")
	var saved := FileAccess.get_file_as_string(flow._preference_path())
	check(saved.contains("completed=true") and saved.contains("registered=true") and not saved.to_lower().contains("password") and not saved.contains("SessionTicket") and not saved.contains("CustomId"), "onboarding persists UI choices without account credentials")
	flow.queue_free()
	await process_frame
	flow = TestOnboarding.new()
	flow.game = game
	game.add_child(flow)
	check(flow.completed and flow.should_skip_auto_device_login(), "registered preference survives relaunch and prevents a new anonymous login")
	game.account.signed_in = false
	flow.begin_if_needed()
	check(game.account_opens == 2 and game.account_menu.mode == "login" and not game.account_menu.first_time, "returning registered player receives Sign in instead of repeated registration")
	flow.begin_if_needed()
	check(game.account_opens == 2, "returning sign-in prompt is shown only once")
	flow.continue_as_guest(false)
	check(flow.completed and flow.registered and not game.account.signed_in, "returning player can continue offline without losing registered preference")
	flow.queue_free()
	await process_frame
	DirAccess.remove_absolute("user://primal_monke_onboarding_test.cfg")
	game.account.has_credentials = false
	game.account.signed_in = false
	flow = TestOnboarding.new()
	flow.game = game
	game.add_child(flow)
	flow.begin_if_needed()
	flow.continue_as_guest()
	await process_frame
	check(flow.completed and not flow.registered and not game.account.signed_in, "guest choice completes welcome without creating or claiming an account")
	check(game.tutorial_opens == 1, "guest is offered a replayable tutorial")
	flow.continue_as_guest()
	await process_frame
	check(game.tutorial_opens == 1, "repeated guest callback cannot reopen tutorial")
	check(flow.should_skip_auto_device_login(), "guest choice never permits automatic device account creation")
	flow.queue_free()
	await process_frame
	flow = TestOnboarding.new()
	flow.game = game
	game.add_child(flow)
	var previous_opens := game.account_opens
	flow.begin_if_needed()
	check(flow.completed and not flow.registered and flow.should_skip_auto_device_login() and not game.account.signed_in and game.account_opens == previous_opens, "returning guest stays offline without a new login prompt or profile identity switch")
	game.account.has_credentials = true
	game.account.signed_in = true
	game.account.state_changed.emit()
	check(flow.registered and flow.should_skip_auto_device_login(), "later credential sign-in records returning registered behavior")
	flow.queue_free()
	await process_frame
	DirAccess.remove_absolute("user://primal_monke_onboarding_test.cfg")
	game.account.has_credentials = false
	game.account.signed_in = false
	flow = TestOnboarding.new()
	flow.game = game
	game.add_child(flow)
	flow.begin_if_needed()
	flow.continue_as_guest(false)
	await process_frame
	check(flow.completed and not flow.registered and game.tutorial_opens == 1, "programmatic account closure can record guest choice without interrupting another menu")
	flow.queue_free()
	await process_frame

func check_tutorial(game: MockGame) -> void:
	var tutorial := TutorialScript.new()
	tutorial.game = game
	game.add_child(tutorial)
	tutorial.set_process(false)
	tutorial.begin()
	check(tutorial.lesson == 0 and tutorial.is_open and not game.player.input_allowed, "tutorial opens as a local menu and pauses player input")
	check(tutorial.toggle_key == KEY_F4 and tutorial._world_buttons.size() == 5, "tutorial provides desktop replay key and interactive VR controls")
	tutorial._dispatch("next")
	check(tutorial.lesson == 1 and not tutorial._action_enabled("next"), "movement lesson requires actual practice before Next")
	tutorial._dispatch("try")
	check(game.solo_starts == 1 and tutorial.practice_active and not tutorial.is_open and game.player.input_allowed, "practice starts a playable solo round instead of keeping movement paused")
	tutorial._observe_exercise()
	game.player.position.x += 0.8
	tutorial._observe_exercise()
	game.player.position.x += 0.8
	tutorial._observe_exercise()
	check(not tutorial._exercise_done, "short walk does not complete a two-metre exercise")
	game.player.position.x += 0.5
	tutorial._observe_exercise()
	check(tutorial._exercise_done and tutorial.is_open and tutorial._action_enabled("next"), "two metres of actual movement completes and reopens instructions")
	tutorial._dispatch("next")
	tutorial._dispatch("try")
	tutorial._observe_exercise()
	game.player.position.y += 0.1
	tutorial._observe_exercise()
	check(not tutorial._exercise_done, "small height changes do not complete jump practice")
	game.player.position.y += 0.3
	tutorial._observe_exercise()
	check(tutorial._exercise_done, "real vertical movement completes desktop jump practice")
	tutorial._dispatch("next")
	tutorial._dispatch("try")
	tutorial._observe_exercise()
	tutorial._observe_exercise()
	check(not tutorial._exercise_done, "tag practice waits for a real score change")
	game.score += 1
	game.local_tag_count += 1
	tutorial._observe_exercise()
	check(tutorial._exercise_done and game.cues.has("success"), "successful tag completes practice with a success cue")
	tutorial._dispatch("next")
	check(tutorial.lesson == 4 and tutorial._action_enabled("next") and tutorial._lesson_body().contains("same Wi-Fi"), "multiplayer lesson explains actual LAN crossplay without requiring a session")
	tutorial._dispatch("next")
	tutorial._dispatch("next")
	check(tutorial.completed and not tutorial.is_open, "finishing saves tutorial completion and closes the overlay")
	tutorial.begin()
	tutorial.lesson = 3
	game.score = 5
	game.finished = true
	tutorial._dispatch("try")
	check(game.solo_starts == 2 and not game.finished and game.score == 0, "replaying tag exercise after a win starts fresh taggable solo monkeys")
	tutorial._observe_exercise()
	game.local_tag_count += 1
	tutorial._observe_exercise()
	check(tutorial._exercise_done, "fresh tag exercise after a won round completes on an accepted local tag")
	game.finished = true
	game.score = 0
	tutorial._dispatch("try")
	check(game.solo_starts == 3 and not game.finished, "tag exercise after a timed-out solo round also starts fresh")
	tutorial._observe_exercise()
	game.local_tag_count += 1
	tutorial._observe_exercise()
	check(tutorial._exercise_done, "fresh tag exercise after time expires remains completable")
	tutorial.begin()
	check(tutorial.lesson == 0 and tutorial.is_open, "completed tutorial can be replayed from the beginning")
	tutorial._dispatch("next")
	game.network_mode = "client"
	game.frontend_state = "lobby"
	check(not tutorial._action_enabled("try"), "tutorial never starts or leaves an online staging session")
	game.frontend_state = "playing"
	tutorial._dispatch("try")
	check(game.solo_starts == 3 and game.network_mode == "client", "online practice preserves existing multiplayer session")
	tutorial.set_open(true)
	tutorial.lesson = 3
	game.finished = true
	tutorial._dispatch("try")
	check(game.solo_starts == 3 and game.finished, "online finished-round tag practice never restarts another player's session")
	tutorial._observe_exercise()
	game.score += 1
	tutorial._observe_exercise()
	check(not tutorial._exercise_done, "a teammate's shared score cannot complete local tag practice")
	game.local_tag_count += 1
	tutorial._observe_exercise()
	check(tutorial._exercise_done, "online tag practice requires a locally attributed accepted tag")
	tutorial.set_open(true)
	tutorial._dispatch("skip")
	check(tutorial.completed and not tutorial.is_open and not tutorial.practice_active, "Skip exits replay while preserving previously completed tutorial history")
	tutorial.completed = false
	tutorial.begin()
	tutorial._dispatch("skip")
	check(not tutorial.completed and not tutorial.is_open, "skipping an unfinished tutorial never invents completion")
	game.network_mode = "offline"
	game.finished = false
	game.player.xr_running = true
	tutorial.begin()
	tutorial.lesson = 2
	tutorial._dispatch("try")
	tutorial._observe_exercise()
	game.player.contacts = false
	tutorial._observe_exercise()
	check(not tutorial._exercise_done, "VR climb exercise cannot complete without hand contact")
	game.player.contacts = true
	tutorial._observe_exercise()
	check(tutorial._exercise_done and tutorial._lesson_body().contains("hand"), "tracked hand contact completes VR climb practice")
	tutorial.set_open(false)
	game.player.xr_running = false
	tutorial.queue_free()
	await process_frame

func check_sounds(game: MockGame) -> void:
	var sounds := SoundsScript.new()
	sounds.game = game
	game.add_child(sounds)
	sounds.set_process(false)
	check(sounds._flat_voices.size() == 8 and sounds._spatial_voices.size() == 8, "sound voices use a fixed bounded pool")
	var bus := AudioServer.get_bus_index(SoundsScript.EFFECTS_BUS)
	check(bus >= 0 and AudioServer.get_bus_effect_count(bus) == 1 and AudioServer.get_bus_effect(bus, 0) is AudioEffectLimiter, "dedicated effects limiter prevents overlapping cues from clipping the mix")
	for cue in SoundsScript.CUES:
		check(sounds._streams[cue] is AudioStreamWAV, "%s original cue loads as a native WAV" % cue)
		var samples := inspect_wave(SoundsScript.CUES[cue])
		check(samples.duration > 0.025 and samples.duration <= 1.1 and samples.peak > 100 and samples.peak < 32767, "%s cue is short, audible and free of clipped samples" % cue)
	var ambience := inspect_wave(SoundsScript.AMBIENCE)
	check(ambience.duration == 8.0 and ambience.peak < 32767 and ambience.peak > 100, "original ambience has bounded duration and no clipping")
	sounds.set_gain(-10)
	check(sounds.gain == 0, "audio volume clamps negative input")
	sounds.set_gain(5)
	check(sounds.gain == 1, "audio volume clamps excessive input")
	sounds.set_muted(true)
	sounds.play_cue("tag", Vector3.ZERO)
	check(not sounds._ambience.playing and not sounds._flat_voices[0].playing and not sounds._spatial_voices[0].playing, "mute stops ambience and one-shot playback")
	sounds.set_muted(false)
	sounds.play_cue("unknown")
	sounds.play_cue("success")
	check(not sounds._ambience.playing and not sounds._flat_voices[0].playing, "headless tests never play or capture audio")
	sounds.queue_free()
	await process_frame

func inspect_wave(path: String) -> Dictionary:
	var stream := load(path) as AudioStreamWAV
	if stream == null:
		return {"duration": 0.0, "peak": 0}
	# Decode the actual imported stream, including export QOA compression.
	# Mixing into memory does not open a speaker or capture the microphone.
	var playback := stream.instantiate_playback()
	playback.start()
	var frames := ceili(stream.get_length() * AudioServer.get_mix_rate())
	var samples := playback.mix_audio(1.0, frames)
	playback.stop()
	var peak := 0
	for sample in samples:
		peak = maxi(peak, roundi(maxf(absf(sample.x), absf(sample.y)) * 32767.0))
	return {"duration": stream.get_length(), "peak": peak}
