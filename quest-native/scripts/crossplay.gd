extends Node

# One protocol for the Windows and standalone Quest ports. The host owns the round.
const PORT := 7777
const MAX_PLAYERS := 8
const PROTOCOL := 1
const GAME_VERSION := "0.3.0"
const STALE_MS := 2000
const AvatarScript = preload("res://scripts/remote_monkey.gd")
var game: Node3D
var mode := "offline"
var status := "Solo — host or join to play together"
var address := ""
var members: Dictionary = {}
var avatars: Dictionary = {}
var pose_clock := 0.0
var snapshot_clock := 0.0
var join_clock := 0.0
var round_id := 0
var snapshot_sequence := 0
var received_sequence := -1
var received_round := -1
var bot_targets: Array = []

func _ready() -> void:
	name = "Crossplay"
	var addresses: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."): continue
		addresses.append(ip)
	address = ", ".join(addresses) if not addresses.is_empty() else "127.0.0.1"
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): leave("Connection failed — check IP, Wi-Fi and UDP 7777"))
	multiplayer.server_disconnected.connect(func(): leave("Host disconnected — returned to solo"))

func is_host() -> bool:
	return mode == "hosting"

func is_client() -> bool:
	return mode == "joining" or mode == "connected"

func host() -> void:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS - 1, 3)
	if error != OK:
		status = "Cannot host on UDP %s (error %s)" % [PORT, error]
		return
	multiplayer.multiplayer_peer = peer
	mode = "hosting"
	status = "Hosting — share IP %s, UDP %s" % [address, PORT]
	round_id += 1
	game.restart()
	members[1] = local_pose()

func join(ip: String) -> void:
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address() or ip.contains(":"):
		status = "Enter the host's IPv4 address (example: 192.168.1.25)"
		return
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, PORT, 3)
	if error != OK:
		status = "Cannot connect (error %s)" % error
		return
	multiplayer.multiplayer_peer = peer
	mode = "joining"
	status = "Connecting to %s:%s…" % [ip, PORT]
	join_clock = 0
	for bot in game.bots: bot.active = false

func leave(message := "Solo — host or join to play together") -> void:
	var was_online := mode != "offline"
	mode = "offline"
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	members.clear()
	for avatar in avatars.values(): avatar.queue_free()
	avatars.clear()
	bot_targets.clear()
	received_sequence = -1
	received_round = -1
	status = message
	if was_online: game.restart()

func _connected() -> void:
	if mode == "joining": _hello.rpc_id(1, PROTOCOL, GAME_VERSION)

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(protocol: int, version: String) -> void:
	if not is_host(): return
	var sender := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL or version != GAME_VERSION:
		_rejected.rpc_id(sender, "Version mismatch — install matching PC and Quest 0.3.0 builds")
		return
	members[sender] = {"active": false, "seen": Time.get_ticks_msec()}
	_welcome.rpc_id(sender, make_snapshot())

@rpc("authority", "call_remote", "reliable", 0)
func _rejected(message: String) -> void:
	leave(message)

@rpc("authority", "call_remote", "reliable", 0)
func _welcome(state: Dictionary) -> void:
	if mode != "joining": return
	mode = "connected"
	status = "Connected — PC + Quest co-op (%s/%s players)" % [state.players.size(), MAX_PLAYERS]
	game.player.reset_player()
	apply_snapshot(state)
	game.lobby.set_open(false)

func local_pose() -> Dictionary:
	var player = game.player
	var head_position: Vector3 = player.head.global_position
	var left: Vector3 = player.hand_visuals[0].global_position if player.xr_running else head_position + Vector3(-0.3, -0.5, 0)
	var right: Vector3 = player.hand_visuals[1].global_position if player.xr_running else head_position + Vector3(0.3, -0.5, 0)
	return {"body": player.global_position, "head": head_position, "rotation": player.head.global_rotation,
		"left": left, "right": right, "vr": player.xr_running,
		"active": player.tracked and player.input_allowed,
		"tag": not player.xr_running and player.input_allowed and Input.is_physical_key_pressed(KEY_E),
		"seen": Time.get_ticks_msec()}

func valid_vector(value: Vector3) -> bool:
	return value.is_finite()

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_pose(pose_round: int, body: Vector3, head: Vector3, rotation: Vector3, left: Vector3, right: Vector3, vr: bool, active: bool, tag: bool) -> void:
	if not is_host(): return
	var sender := multiplayer.get_remote_sender_id()
	if not members.has(sender) or pose_round != round_id: return
	if not valid_vector(body) or not valid_vector(head) or not valid_vector(rotation) or not valid_vector(left) or not valid_vector(right): return
	if absf(body.x) > 18 or absf(body.z) > 18 or body.y < -12 or body.y > 30: return
	if head.distance_to(body) > 3.5 or left.distance_to(head) > 1.6 or right.distance_to(head) > 1.6: return
	members[sender] = {"body": body, "head": head, "rotation": rotation, "left": left, "right": right,
		"vr": vr, "active": active, "tag": tag, "seen": Time.get_ticks_msec()}

func participant_poses() -> Array:
	var result: Array = []
	if is_host():
		members[1] = local_pose()
		for pose in members.values():
			if pose.get("active", false) and Time.get_ticks_msec() - pose.get("seen", 0) < STALE_MS: result.append(pose)
	else:
		var pose := local_pose()
		if pose.active: result.append(pose)
	return result

func round_restarted() -> void:
	if is_host():
		round_id += 1
		for id in members:
			if id != 1: members[id]["active"] = false
		_send_snapshot()

func make_snapshot() -> Dictionary:
	var bot_state: Array = []
	for bot in game.bots: bot_state.append([bot.global_position, bot.rotation.y, bot.tagged])
	var players: Dictionary = {}
	for id in members:
		var pose: Dictionary = members[id].duplicate()
		pose["active"] = pose.get("active", false) and Time.get_ticks_msec() - pose.get("seen", 0) < STALE_MS
		players[id] = pose
	snapshot_sequence += 1
	return {"sequence": snapshot_sequence, "round": round_id, "remaining": game.remaining,
		"score": game.score, "finished": game.finished, "bots": bot_state, "players": players}

func _send_snapshot() -> void:
	if is_host() and not multiplayer.get_peers().is_empty(): _snapshot.rpc(make_snapshot())

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _snapshot(state: Dictionary) -> void:
	if mode == "connected": apply_snapshot(state)

func apply_snapshot(state: Dictionary) -> void:
	if state.sequence <= received_sequence or state.round < received_round: return
	received_sequence = state.sequence
	var new_round: bool = state.round != received_round
	received_round = state.round
	game.remaining = state.remaining
	game.score = state.score
	game.finished = state.finished
	bot_targets = state.bots
	for i in range(game.bots.size()):
		var bot = game.bots[i]
		bot.active = false
		if new_round:
			bot.reset_bot()
			bot.active = false
			bot.global_position = bot_targets[i][0]
		if bot_targets[i][2] and not bot.tagged: bot.tag()
		bot.rotation.y = bot_targets[i][1]
	if new_round: game.player.reset_player()
	update_avatars(state.players)
	status = "Connected — PC + Quest co-op (%s/%s players)" % [state.players.size(), MAX_PLAYERS]

func update_avatars(players: Dictionary) -> void:
	var local_id := multiplayer.get_unique_id()
	for id in players:
		if id == local_id or not players[id].has("head"): continue
		if not avatars.has(id):
			var avatar := AvatarScript.new()
			avatar.name = "Peer%s" % id
			game.add_child(avatar)
			avatars[id] = avatar
		avatars[id].apply_pose(players[id], id)
	for id in avatars.keys():
		if not players.has(id):
			avatars[id].queue_free()
			avatars.erase(id)

func _peer_left(id: int) -> void:
	members.erase(id)
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)
	_send_snapshot()

func _physics_process(delta: float) -> void:
	if mode == "joining":
		join_clock += delta
		if join_clock > 10: leave("Connection timed out — check host IP and UDP 7777")
	if mode == "offline": return
	pose_clock += delta
	snapshot_clock += delta
	if mode == "connected" and pose_clock >= 0.05:
		pose_clock = 0
		var p := local_pose()
		_submit_pose.rpc_id(1, received_round, p.body, p.head, p.rotation, p.left, p.right, p.vr, p.active, p.tag)
	if is_host() and snapshot_clock >= 0.1:
		snapshot_clock = 0
		members[1] = local_pose()
		update_avatars(make_snapshot().players)
		_send_snapshot()
	if mode == "connected":
		for i in range(bot_targets.size()):
			game.bots[i].global_position = game.bots[i].global_position.lerp(bot_targets[i][0], 1.0 - exp(-15 * delta))
