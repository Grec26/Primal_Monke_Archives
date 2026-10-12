extends SceneTree

# Player Tag decisions run locally with no accounts, microphone, or network clients.
const SessionScript = preload("res://scripts/crossplay.gd")
const AvatarScript = preload("res://scripts/remote_monkey.gd")
var failures := 0
var game: TestGame

class TestPlayer:
	extends Node3D
	var head := Node3D.new()
	var hand_visuals: Array = [Node3D.new(), Node3D.new()]
	var xr_running := false
	var tracked := true
	var input_allowed := true
	func _ready() -> void:
		add_child(head)
		head.position = Vector3(0, 1.65, 0)
		for hand in hand_visuals: add_child(hand)
	func reset_player() -> void: pass

class TestLobby:
	extends Node
	func set_open(_value: bool) -> void: pass

class TestBot:
	extends Node3D
	var tagged := false
	var active := false
	func reset_bot() -> void: tagged = false
	func tag() -> void: tagged = true

class TestGame:
	extends Node3D
	var player := TestPlayer.new()
	var lobby := TestLobby.new()
	var session: Node
	var bots: Array = []
	var remaining := 90.0
	var score := 0
	var finished := false
	var profile: Node
	var voice: Node
	var events: Array = []
	var bot_events: Array = []
	func _ready() -> void:
		add_child(player)
		add_child(lobby)
	func restart() -> void:
		score = 0
		finished = false
		if session != null: session.round_restarted()
	func on_player_tagged(tagger: int, target: int, key: String) -> void:
		events.append([tagger, target, key])
	func on_bot_tagged(tagger: int, index: int, key: String) -> void:
		bot_events.append([tagger, index, key])

func _initialize() -> void: call_deferred("run")

func check(value: bool, description: String) -> void:
	if value: print("PASS: " + description)
	else:
		push_error("FAIL: " + description)
		failures += 1

func pose(position: Vector3, vr := false, pressed := false) -> Dictionary:
	var head := position + Vector3.UP * 1.65
	return {"body": position, "head": head, "rotation": Vector3.ZERO,
		"left": head + Vector3(-0.3, -0.5, 0), "right": head + Vector3(0.3, -0.5, 0),
		"vr": vr, "active": true, "tag": pressed, "seen": Time.get_ticks_msec()}

func configure_poses(source: Dictionary, target: Dictionary) -> void:
	game.session.members[1] = source
	game.session.members[42] = target
	game.session.tagger_id = 1
	game.session.tag_cooldown_until = 0

func run() -> void:
	game = TestGame.new()
	root.add_child(game)
	game.session = SessionScript.new()
	game.session.game = game
	game.session.port = 7792
	game.add_child(game.session)
	game.session.set_physics_process(false)
	check(game.session.game_mode == "co_op", "existing rooms default to co-op")
	check(not game.session.set_game_mode("injected"), "unknown room modes are rejected")
	check(game.session.set_game_mode("tag"), "offline host can select Player Tag")
	game.session.host()
	check(game.session.mode == "hosting" and game.session.phase == "lobby", "tag host starts in a waiting lobby")
	check(not game.session.start_round() and game.session.status.contains("two players"), "one-player tag room explains why start is blocked")
	game.session.members[42] = pose(Vector3(1, 0, 0))
	check(game.session.start_round() and game.session.phase == "loading", "two-player tag room enters the loading phase")
	check(game.session.complete_loading() and game.session.phase == "playing", "host completes a player tag round")
	check(not game.session.set_game_mode("co_op"), "mode cannot change while a round is playing")
	check(game.session.tagger_id == 1 and game.session.tag_transfers == 0, "new round deterministically selects the host and clears tag totals")
	# A standing avatar's longer arms must remain usable for tags while
	# malformed or overlong poses are rejected on both hands.
	for vr in [false, true]:
		var reach: float = SessionScript.MAX_VR_HAND_DISTANCE if vr else SessionScript.MAX_DESKTOP_HAND_DISTANCE
		for side in ["left", "right"]:
			var bounded := pose(Vector3.ZERO, vr)
			bounded[side] = bounded.head + Vector3.DOWN * (reach - 0.001)
			check(game.session._usable_tag_pose(bounded), "%s %s hand at bounded reach is accepted" % ["VR" if vr else "desktop", side])
			bounded[side] = bounded.head + Vector3.DOWN * (reach + 0.001)
			check(not game.session._usable_tag_pose(bounded), "%s %s hand beyond reach is rejected" % ["VR" if vr else "desktop", side])
	var standing := pose(Vector3.ZERO, true)
	standing.head.y = 1.80
	standing.left = Vector3(-0.2, 0.09, 0)
	standing.right = Vector3(0.2, 0.09, 0)
	check(game.session._usable_tag_pose(standing), "standing virtual hands touching the floor remain usable in crossplay")
	standing.vr = false
	check(not game.session._usable_tag_pose(standing), "longer VR arm reach does not expand desktop poses")

	configure_poses(pose(Vector3.ZERO, false, true), pose(Vector3(7, 0, 0)))
	game.session._advance_player_tags()
	check(game.session.tagger_id == 1, "desktop E cannot tag a far player")
	configure_poses(pose(Vector3.ZERO), pose(Vector3(0.8, 0, 0), false, true))
	game.session._advance_player_tags()
	check(game.session.tagger_id == 1, "E input from a player who is not IT cannot transfer IT")
	configure_poses(pose(Vector3.ZERO, false, true), pose(Vector3(0.8, 0, 0)))
	game.session.tag_cooldown_until = Time.get_ticks_msec() + 1250
	game.session._advance_player_tags()
	check(game.session.tagger_id == 1, "cooldown prevents immediate tag backs")
	game.session.tag_cooldown_until = 0
	game.session._advance_player_tags()
	check(game.session.tagger_id == 42 and game.session.tag_scores.get(1, 0) == 1 and game.session.tag_transfers == 1, "nearby IT player's E transfers IT and increments the authoritative tag total")
	check(game.events.size() == 1 and game.events[0][0] == 1 and game.events[0][1] == 42, "valid transfer emits one attribution event")
	game.session._emit_player_tag(game.session.round_id, 1, 1, 42)
	check(game.events.size() == 1, "duplicate tag event cannot award XP or replay sound twice")
	check(not game.session.is_local_tagger(), "local IT status follows the transferred transport ID")

	for corrupt in ["stale_target", "stale_source", "inactive", "bounds", "nan", "hands"]:
		var source := pose(Vector3.ZERO, false, true)
		var target := pose(Vector3(0.8, 0, 0))
		match corrupt:
			"stale_target": target.seen = Time.get_ticks_msec() - 2001
			"stale_source": source.seen = Time.get_ticks_msec() - 2001
			"inactive": target.active = false
			"bounds": source.body = Vector3(99, 0, 0)
			"nan": source.head = Vector3(NAN, 0, 0)
			"hands": source.left = Vector3(10, 0, 0)
		configure_poses(source, target)
		game.session._advance_player_tags()
		check(game.session.tagger_id == 1, "tag rejects " + corrupt + " pose")
	configure_poses(pose(Vector3.ZERO, true), pose(Vector3(0.5, 0, 0)))
	game.session.members[1].right = game.session.members[42].head + Vector3.DOWN * 0.6
	game.session._advance_player_tags()
	check(game.session.tagger_id == 42 and game.session.tag_transfers == 2, "fresh VR hand touching the target body transfers IT without E")
	check(game.session.make_snapshot().game_mode == "tag" and game.session.make_snapshot().tagger == 42, "snapshots carry shared tag state without profile image payloads")
	check(not game.session.make_snapshot().has("profiles"), "profile PNGs stay out of frequent pose snapshots")
	game.session.round_restarted()
	check(game.session.tagger_id == 1 and game.session.tag_transfers == 0 and game.session.tag_scores.get(1, -1) == 0, "restart clears previous score, IT, and event generation")
	game.session.tagger_id = 42
	game.session._peer_left(42)
	check(game.session.tagger_id == 1 and not game.session.tag_scores.has(42), "disconnecting IT selects a remaining member and clears their score")

	var avatar := AvatarScript.new()
	game.add_child(avatar)
	avatar.apply_pose(pose(Vector3.ZERO), 42)
	avatar.apply_profile({"name": "Forest Friend", "level": 12, "avatar": PackedByteArray()})
	avatar.set_tagged(true)
	check(avatar.label.text.contains("Forest Friend") and avatar.label.text.contains("Lv 12") and avatar.label.text.contains("IT"), "remote avatar displays public name, level, and IT marker")
	check((avatar.body.material_override as StandardMaterial3D).albedo_color == Color("ff772c"), "IT avatar uses the original orange lava color")
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color("70ccaa"))
	avatar.apply_profile({"name": "Forest Friend", "level": 12, "avatar": image.save_png_to_buffer()})
	check(avatar.portrait.visible and avatar.portrait.texture != null, "bounded PNG profile portrait creates a remote billboard")
	avatar.apply_profile({"name": "Forest Friend", "avatar": PackedByteArray([1, 2, 3])})
	check(not avatar.portrait.visible, "malformed portrait bytes never reach image decoding")
	check(game.session.publish_profile({"name": "Monke Guide", "xp": 900, "level": 99999, "developer": true, "id": 42, "avatar": image.save_png_to_buffer()}), "host publishes a bounded public profile")
	check(game.session.profiles[1].name == "Monke Guide" and game.session.profiles[1].level == 4, "public level is derived from bounded cosmetic XP")
	check(not game.session.profiles[1].has("developer") and not game.session.profiles[1].has("id"), "profile schema strips account and developer claims")
	var oversized := PackedByteArray()
	oversized.resize(6001)
	check(not game.session.publish_profile({"name": "Monke", "avatar": oversized}) and game.session.profiles[1].name == "Monke Guide", "oversized avatar payload cannot replace the accepted profile")
	check(not game.session.publish_profile({"name": "a".repeat(129)}), "profile name payload is bounded before sanitizing")
	game.session._submit_profile({"name": "Forged Owner", "xp": 900})
	check(game.session.profiles[1].name == "Monke Guide", "a submit without a transport sender cannot claim an existing profile")
	game.session.leave()
	check(game.session.local_pose().peer_id == 1, "local poses bind attribution to the transport peer ID")
	game.session.set_game_mode("co_op")
	game.bots = [TestBot.new()]
	game.add_child(game.bots[0])
	game.session.notify_bot_tag(1, 0)
	game.session.notify_bot_tag(1, 0)
	check(game.bot_events.size() == 1 and game.bot_events[0][0] == 1, "accepted co-op bot tag attributes a single local event")
	game.session.round_restarted()
	game.session.notify_bot_tag(1, 0)
	check(game.bot_events.size() == 2 and game.bot_events[0][2] != game.bot_events[1][2], "new solo round uses a fresh bot event key")
	game.queue_free()
	await process_frame
	print("Player Tag checks complete; failures: %s" % failures)
	quit(0 if failures == 0 else 1)
