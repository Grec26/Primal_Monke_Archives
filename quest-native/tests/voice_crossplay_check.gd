extends SceneTree

# Real ENet transport using synthetic PCM; no microphone or audio output.
const Voice = preload("res://scripts/voice_chat.gd")
const PORT := 7780
var role := "host"
var game: TestGame
var checks := 0
var failures := 0
var stage := "waiting"
var reports: Dictionary = {}
var speaker_id := 0
var listener_id := 0
var baseline := 0
var disabled_baseline := 0
var proximity_baseline := 0
var last_packet := 0
var flooded := false
var deadline := 0

class TestPlayer extends Node3D:
	var head: Node3D
	func _ready() -> void:
		head = Node3D.new()
		add_child(head)
		head.position = Vector3(0, 1.6, 0)

class TestGame extends Node3D:
	var session: Node
	var player: Node3D
	var voice: Node
	var xr_focused := true

class TestSession extends Node:
	var owner_tree: SceneTree
	var mode := "offline"
	var phase := "lobby"
	var members: Dictionary = {}
	var roles: Dictionary = {1: "host"}
	func _ready() -> void:
		multiplayer.connected_to_server.connect(func(): _hello.rpc_id(1, owner_tree.role))
		multiplayer.peer_disconnected.connect(func(id: int): members.erase(id))
	@rpc("any_peer", "call_remote", "reliable", 0)
	func _hello(client_role: String) -> void:
		if mode != "hosting" or client_role not in ["speaker", "listener"]: return
		var sender := multiplayer.get_remote_sender_id()
		members[sender] = {"head": Vector3(2 if client_role == "speaker" else 0, 1.6, 0), "seen": Time.get_ticks_msec()}
		roles[sender] = client_role
		_roster.rpc(members, roles)
	@rpc("authority", "call_remote", "reliable", 0)
	func _roster(new_members: Dictionary, new_roles: Dictionary) -> void:
		members = new_members
		roles = new_roles
		mode = "connected"
	@rpc("authority", "call_remote", "reliable", 0)
	func _stage(value: String) -> void: owner_tree.apply_stage(value)
	@rpc("any_peer", "call_remote", "reliable", 0)
	func _report(result: Dictionary) -> void:
		if mode == "hosting": owner_tree.reports[multiplayer.get_remote_sender_id()] = result

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("voice-role="): role = argument.trim_prefix("voice-role=")
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS [%s]: %s" % [role, label])
	else:
		push_error("FAIL [%s]: %s" % [role, label])
		failures += 1

func pcm() -> PackedByteArray:
	var samples := PackedFloat32Array()
	samples.resize(Voice.SAMPLES_PER_FRAME)
	samples.fill(0.1)
	return Voice.encode_pcm(samples)

func run() -> void:
	game = TestGame.new()
	game.name = "VoiceRoom"
	root.add_child(game)
	game.player = TestPlayer.new()
	game.add_child(game.player)
	game.session = TestSession.new()
	game.session.name = "Crossplay"
	game.session.owner_tree = self
	game.add_child(game.session)
	game.voice = Voice.new()
	game.voice.game = game
	game.add_child(game.voice)
	game.voice.set_process(false)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, 7, 4) if role == "host" else peer.create_client("127.0.0.1", PORT, 4)
	check(error == OK, "ENet opens four independent channels")
	get_multiplayer().multiplayer_peer = peer
	game.session.mode = "hosting" if role == "host" else "joining"
	if role == "host":
		game.session.members[1] = {"head": Vector3(0, 1.6, 0), "seen": Time.get_ticks_msec()}
		await host_run()
	else:
		deadline = Time.get_ticks_msec() + 12000
		while stage != "done" and Time.get_ticks_msec() < deadline:
			client_tick()
			await process_frame
		check(stage == "done", "host completes the real voice transport scenario")
		await wait_ms(350) # Let the authority close before clients tear down ENet.
	print("Voice ENet [%s]: %s checks, failures: %s" % [role, checks, failures])
	peer.close()
	get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func wait_ms(milliseconds: int) -> void:
	var until := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < until: await process_frame

func host_stage(value: String) -> void:
	apply_stage(value)
	game.session._stage.rpc(value)
	await wait_ms(450 if value != "lobby" else 900)

func apply_stage(value: String) -> void:
	stage = value
	for id in game.session.roles:
		if game.session.roles[id] == "speaker": speaker_id = int(id)
		if game.session.roles[id] == "listener": listener_id = int(id)
	for id in game.session.members:
		game.session.members[id].seen = Time.get_ticks_msec()
	game.session.phase = "playing" if value in ["far", "near"] else "lobby"
	if game.session.members.has(speaker_id):
		game.session.members[speaker_id].head = Vector3(30 if value == "far" else 2, 1.6, 0)
	if role == "speaker": game.player.head.position.x = 30 if value == "far" else 2
	match value:
		"lobby":
			game.voice.set_enabled(true)
			game.voice.set_mic_muted(false)
		"muted":
			if role == "listener":
				check(game.voice.received_frames >= 10, "authority relays multiple speaker PCM frames to the listener")
				check(game.voice._queues.has(speaker_id), "listener identifies voice by the authenticated sender")
				game.voice.set_peer_muted(speaker_id, true)
				baseline = game.voice.received_frames
		"disabled":
			if role == "listener":
				check(game.voice.received_frames == baseline, "per-player mute blocks live relay playback")
				game.voice.set_enabled(false)
				disabled_baseline = game.voice.received_frames
		"far":
			if role == "listener":
				check(game.voice.received_frames == disabled_baseline and game.voice._queues.is_empty(), "opt-out blocks live voice and clears bounded queues")
				game.voice.set_enabled(true)
				game.voice.set_peer_muted(speaker_id, false)
				proximity_baseline = game.voice.received_frames
		"near":
			if role == "listener": check(game.voice.received_frames == proximity_baseline, "host filters distant speaker packets before relay")
		"flood":
			if role == "listener": check(game.voice.received_frames > proximity_baseline, "nearby speaker resumes through the same host relay")
		"finish":
			if role != "host":
				check(game.voice._microphone == null, "synthetic transport never requests or opens the microphone")
				check(game.voice._queues.size() <= 7, "live transport retains at most seven playback queues")
				for queue in game.voice._queues.values(): check(queue.size() <= Voice.MAX_QUEUE, "live transport jitter buffer remains bounded")
				var frames_before: int = game.voice.received_frames
				game.voice._relay_voice(99999, 99999, pcm())
				check(game.voice.received_frames == frames_before, "relay handler rejects a call without authority transport identity")
				game.voice.set_enabled(false)
				check(not game.voice.submit_frame(pcm()), "disabled sender cannot transmit a frame")
				game.session._report.rpc_id(1, {"checks": checks, "failures": failures, "received": frames_before})
		"done": pass

func client_tick() -> void:
	if role != "speaker": return
	if stage in ["lobby", "muted", "disabled", "far", "near"]:
		var now := Time.get_ticks_msec()
		if now - last_packet >= 20:
			last_packet = now
			game.voice.submit_frame(pcm())
	elif stage == "flood" and not flooded:
		flooded = true
		for index in range(100): game.voice.submit_frame(pcm())

func host_run() -> void:
	deadline = Time.get_ticks_msec() + 6000
	while game.session.members.size() < 3 and Time.get_ticks_msec() < deadline: await process_frame
	check(game.session.members.size() == 3, "three real peers finish their room handshake")
	if game.session.members.size() < 3: return
	await host_stage("lobby")
	check(game.voice.received_frames >= 10, "host accepts and receives remote PCM on channel 3")
	check(game.voice.relayed_frames >= 10, "host forwards authenticated frames to the other registered peer")
	await host_stage("muted")
	await host_stage("disabled")
	await host_stage("far")
	await host_stage("near")
	var before_flood: int = game.voice.rejected_frames
	await host_stage("flood")
	check(game.voice.rejected_frames > before_flood, "host rate limiter rejects a real channel-3 flood")
	await host_stage("finish")
	deadline = Time.get_ticks_msec() + 2000
	while reports.size() < 2 and Time.get_ticks_msec() < deadline: await process_frame
	check(reports.size() == 2, "both clients return their voice transport results")
	for result in reports.values(): check(int(result.get("failures", 1)) == 0, "remote voice assertions passed")
	check(game.voice._microphone == null, "host transport uses synthetic PCM without opening capture")
	game.voice.shutdown()
	check(game.voice._queues.is_empty() and game.voice._senders.is_empty() and game.voice.mic_muted, "real room shutdown drops PCM, sender state, and microphone intent")
	game.session._stage.rpc("done")
	stage = "done"
	await wait_ms(200)
