extends SceneTree

# Three real ENet processes. Files synchronize stages; game state travels by RPC.
const Fixtures = preload("res://tests/tag_mode_check.gd")
const SessionScript = preload("res://scripts/crossplay.gd")
var role := ""
var signals_dir := ""
var game: Node3D
var failures := 0
var first_id := 0
var second_id := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="): role = argument.trim_prefix("--role=")
		if argument.begins_with("--signals="): signals_dir = argument.trim_prefix("--signals=")
	call_deferred("run")

func check(value: bool, description: String) -> void:
	if value: print("PASS [%s]: %s" % [role, description])
	else:
		push_error("FAIL [%s]: %s" % [role, description])
		failures += 1

func write_signal(label: String, values: Dictionary = {}) -> void:
	var file := FileAccess.open(signals_dir.path_join(label + ".json"), FileAccess.WRITE)
	if file == null:
		check(false, "create stage " + label)
		return
	file.store_string(JSON.stringify(values))
	file.close()

func read_signal(label: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(signals_dir.path_join(label + ".json")))
	return value if value is Dictionary else {}

func wait_for(predicate: Callable, description: String, seconds := 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await create_timer(0.025).timeout
	var result: bool = predicate.call()
	check(result, description)
	return result

func wait_signal(label: String) -> bool:
	return await wait_for(func(): return FileAccess.file_exists(signals_dir.path_join(label + ".json")), "stage " + label)

func pause(seconds: float) -> void: await create_timer(seconds).timeout

func e_key(value: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = value
	Input.parse_input_event(event)

func park(position: Vector3) -> void:
	game.player.global_position = position
	game.player.head.position = Vector3.UP * 1.65
	game.player.hand_visuals[0].global_position = game.player.head.global_position + Vector3(-0.3, -0.5, 0)
	game.player.hand_visuals[1].global_position = game.player.head.global_position + Vector3(0.3, -0.5, 0)

func public_profile(display_name: String, color: Color) -> Dictionary:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return {"name": display_name, "xp": 900, "level": 4, "avatar": image.save_png_to_buffer(), "developer": true, "id": 1}

func run() -> void:
	if role not in ["host", "client1", "client2"] or signals_dir.is_empty():
		quit(2)
		return
	game = Fixtures.TestGame.new()
	root.add_child(game)
	game.bots = [Fixtures.TestBot.new()]
	game.add_child(game.bots[0])
	game.session = SessionScript.new()
	game.session.game = game
	game.session.port = 7790
	game.add_child(game.session)
	game.session.publish_profile(public_profile({"host": "Tree Keeper", "client1": "Desktop Ranger", "client2": "VR Climber"}[role], Color("79d1a4")))
	game.player.xr_running = role == "client2"
	park(Vector3(0 if role == "host" else (-10 if role == "client1" else 10), 0, -5))
	if role == "host": await run_host()
	else: await run_client()
	e_key(false)
	game.session.leave()
	game.queue_free()
	await process_frame
	write_signal(role + "-result", {"failures": failures})
	print("Player Tag crossplay %s complete; failures: %s" % [role, failures])
	quit(0 if failures == 0 else 1)

func run_host() -> void:
	check(game.session.set_game_mode("tag"), "host selects Player Tag before opening the room")
	game.session.host()
	check(game.session.is_host() and game.session.phase == "lobby", "host listens on isolated UDP 7790")
	write_signal("host-ready")
	if not await wait_for(func(): return game.session.members.size() == 3 and game.session.profiles.size() == 3, "host receives both clients and reliable profiles"): return
	await wait_signal("client1-ready")
	await wait_signal("client2-ready")
	first_id = int(read_signal("client1-ready").get("id", 0))
	second_id = int(read_signal("client2-ready").get("id", 0))
	check(first_id > 1 and second_id > 1 and first_id != second_id, "transport binds distinct player identities")
	check(game.session.profiles.get(1, {}).get("name") == "Tree Keeper" and game.session.profiles.get(first_id, {}).get("name") == "Desktop Ranger", "client's cosmetic ID field cannot overwrite host profile")
	check(not game.session.profiles[first_id].has("developer") and not game.session.profiles[first_id].has("id"), "cosmetic profiles strip role and account claims")
	check(game.session.profiles[first_id].avatar.size() > 0 and game.session.room_roster().size() == 3, "bounded PNG portraits and public roster arrive")
	write_signal("profiles-checked")
	await wait_signal("client1-profiles-checked")
	await wait_signal("client2-profiles-checked")
	check(game.session.start_round() and game.session.complete_loading(), "host alone loads and starts the tag round")
	write_signal("playing", {"round": game.session.round_id})
	await wait_signal("client1-playing")
	await wait_signal("client2-playing")
	await pause(1.3)
	e_key(true)
	await pause(0.2)
	check(game.session.tag_transfers == 0, "far-away desktop E cannot transfer IT over real ENet")
	write_signal("host-near")
	await wait_for(func(): return game.session.tagger_id == first_id, "host E transfers IT to nearby desktop player")
	e_key(false)
	write_signal("first-tag", {"tagger": first_id})
	await wait_signal("client1-first-tag")
	await wait_signal("client2-first-tag")
	await pause(0.15)
	check(game.session.tagger_id == first_id and game.session.tag_transfers == 1, "cooldown blocks the desktop player's immediate tag back")
	write_signal("cooldown-done")
	await wait_signal("client1-far-input")
	await pause(1.3)
	check(game.session.tagger_id == first_id and game.session.tag_transfers == 1, "far-away current IT input does not tag another player")
	write_signal("desktop-near")
	await wait_for(func(): return game.session.tagger_id == second_id and game.session.tag_transfers == 2, "desktop client E transfers IT to the VR player through the host")
	write_signal("second-tag")
	await wait_signal("client1-second-tag")
	await wait_signal("client2-second-tag")
	await pause(1.3)
	write_signal("vr-near")
	await wait_for(func(): return game.session.tagger_id == 1 and game.session.tag_transfers == 3, "VR client's tracked hand transfers IT to the host")
	write_signal("third-tag")
	await wait_signal("client1-third-tag")
	await wait_signal("client2-third-tag")
	check(game.events.size() == 3 and game.session.tag_scores.get(1, 0) == 1 and game.session.tag_scores.get(first_id, 0) == 1 and game.session.tag_scores.get(second_id, 0) == 1, "host records one attributed event and tag for each transport member")
	game.session._player_tagged.rpc(game.session.round_id, 3, second_id, 1)
	write_signal("duplicate")
	await wait_signal("client1-duplicate")
	await wait_signal("client2-duplicate")
	write_signal("forge")
	await wait_signal("client1-forged")
	await pause(0.2)
	check(game.events.size() == 3 and game.session.game_mode == "tag" and game.session.profiles.get(1, {}).get("name") == "Tree Keeper" and game.session.tag_scores.get(first_id, 0) == 1, "forged client RPCs and repeated handshake cannot change host state or erase a tag score")
	write_signal("forge-done")
	await wait_signal("client1-forge-done")
	await wait_signal("client2-forge-done")
	game.session.round_restarted()
	write_signal("restart", {"round": game.session.round_id})
	await wait_signal("client1-restarted")
	await wait_signal("client2-restarted")
	check(game.session.tagger_id == 1 and game.session.tag_transfers == 0, "host restart resets tag generation and totals")
	game.session._set_phase("lobby")
	check(game.session.set_game_mode("co_op") and game.session.start_round() and game.session.complete_loading(), "host returns to lobby and starts a co-op round")
	game.bots[0].tag()
	game.session.notify_bot_tag(first_id, 0)
	game.session.notify_bot_tag(first_id, 0)
	game.session.notify_bot_tag(999999, 0)
	game.session.notify_bot_tag(first_id, 999)
	check(game.bot_events.size() == 1 and game.bot_events[0][0] == first_id, "host emits one co-op bot event for the accepted transport player")
	write_signal("coop-tag", {"tagger": first_id})
	await wait_signal("client1-coop-tag")
	await wait_signal("client2-coop-tag")
	write_signal("disconnect")
	await wait_signal("client1-left")
	await wait_signal("client2-left")
	await wait_for(func(): return game.session.members.size() == 1 and game.session.profiles.size() == 1 and game.session.avatars.is_empty(), "disconnect cleans profiles, roster, and remote avatars")
	game.session.leave()
	write_signal("done")

func run_client() -> void:
	if not await wait_signal("host-ready"): return
	game.session.join("127.0.0.1")
	if not await wait_for(func(): return game.session.mode == "connected" and game.session.profiles.size() == 3, "client joins and receives all reliable profiles"): return
	check(game.session.game_mode == "tag" and game.session.phase == "lobby", "welcome snapshot conveys Player Tag in the waiting lobby")
	check(not game.session.set_game_mode("co_op") and not game.session.start_round(), "client cannot choose mode or start the room")
	write_signal(role + "-ready", {"id": game.multiplayer.get_unique_id()})
	await wait_signal("profiles-checked")
	check(game.session.room_roster().size() == 3 and game.session.room_roster()[0].name == "Tree Keeper", "cosmetic names decorate the authority's roster")
	await wait_for(func(): return game.session.avatars.size() == 2, "client has two remote avatars")
	check(game.session.profiles.get(1, {}).avatar.size() > 0, "client receives the host's bounded portrait")
	write_signal(role + "-profiles-checked")
	await wait_signal("playing")
	await wait_for(func(): return game.session.phase == "playing", "client receives host's playing phase")
	write_signal(role + "-playing")
	await wait_signal("host-near")
	if role == "client1": park(Vector3(0.8, 0, -5))
	await wait_signal("first-tag")
	await wait_for(func(): return game.session.tag_transfers == 1 and game.events.size() == 1, "client observes first authoritative tag and one event")
	if role == "client1":
		check(game.session.is_local_tagger(), "desktop client recognizes its own IT status")
		e_key(true)
	write_signal(role + "-first-tag")
	await wait_signal("cooldown-done")
	if role == "client1":
		park(Vector3(-10, 0, -5))
		write_signal("client1-far-input")
	await wait_signal("desktop-near")
	if role == "client1": park(Vector3(9.2, 0, -5))
	await wait_signal("second-tag")
	await wait_for(func(): return game.session.tag_transfers == 2 and game.events.size() == 2, "client observes desktop tag transfer to VR")
	if role == "client1":
		e_key(false)
		park(Vector3(-10, 0, -5))
	else: check(game.session.is_local_tagger(), "VR client recognizes its own IT status")
	write_signal(role + "-second-tag")
	await wait_signal("vr-near")
	if role == "client2":
		park(Vector3(0.5, 0, -5))
		game.player.hand_visuals[1].global_position = Vector3(0, 1.05, -5)
	await wait_signal("third-tag")
	await wait_for(func(): return game.session.tag_transfers == 3 and game.events.size() == 3, "client observes VR tag transfer and three events")
	if role == "client2": park(Vector3(10, 0, -5))
	write_signal(role + "-third-tag")
	await wait_signal("duplicate")
	await pause(0.15)
	check(game.events.size() == 3, "repeated authority event does not replay XP or sound")
	write_signal(role + "-duplicate")
	await wait_signal("forge")
	if role == "client1":
		print("Expected permission rejection follows: client attempts authority-only profile/tag RPCs.")
		game.session._hello.rpc_id(1, SessionScript.PROTOCOL, SessionScript.GAME_VERSION)
		for id in game.multiplayer.get_peers():
			game.session._player_tagged.rpc_id(id, game.session.received_round, 100, 1, game.multiplayer.get_unique_id())
			game.session._sync_profiles.rpc_id(id, {1: public_profile("Forged Host", Color.RED)})
		write_signal("client1-forged")
	await wait_signal("forge-done")
	check(game.events.size() == 3 and game.session.profiles.get(1, {}).get("name") == "Tree Keeper", "client rejects another peer's forged authority events and profiles")
	write_signal(role + "-forge-done")
	await wait_signal("restart")
	await wait_for(func(): return game.session.received_round == int(read_signal("restart").get("round", -1)) and game.session.tag_transfers == 0, "client receives restart generation and cleared tag totals")
	check(game.session.tagger_id == 1, "restart selects the host as IT consistently")
	write_signal(role + "-restarted")
	await wait_signal("coop-tag")
	await wait_for(func(): return game.session.game_mode == "co_op" and game.bot_events.size() == 1, "client receives a reliable attributed co-op bot event")
	check(game.bot_events[0][0] == int(read_signal("coop-tag").get("tagger", 0)) and game.bot_events[0][1] == 0, "co-op event preserves the accepted peer and bot index")
	await pause(0.15)
	check(game.bot_events.size() == 1, "repeated co-op notification cannot double-count tutorial or XP")
	write_signal(role + "-coop-tag")
	await wait_signal("disconnect")
	game.session.leave()
	check(game.session.mode == "offline" and game.session.profiles.is_empty(), "leave clears public profiles and returns offline")
	write_signal(role + "-left")
	await wait_signal("done")
