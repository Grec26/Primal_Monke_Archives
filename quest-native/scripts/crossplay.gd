extends Node

# One protocol for the Windows and standalone Quest ports. The host owns the round.
const PORT := 7777
const MAX_PLAYERS := 8
const PROTOCOL := 2
const GAME_VERSION := "0.7.1"
const MAX_DESKTOP_HAND_DISTANCE := 1.6
# Virtual monkey hands reach the ground while standing; allow 5 cm of
# physics/contact tolerance beyond the player's bounded 2.3 m reach.
const MAX_VR_HAND_DISTANCE := 2.35
const STALE_MS := 2000
const TAG_COOLDOWN_MS := 1250
const PROFILE_INTERVAL_MS := 1000
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
var phase := "playing"
var phase_generation := 0
var game_mode := "co_op"
var tagger_id := 0
var tag_scores: Dictionary = {}
var tag_transfers := 0
var tag_cooldown_until := 0
var profiles: Dictionary = {}
var profile_received_at: Dictionary = {}
var local_profile: Dictionary = {}
var _tag_events: Dictionary = {}
var port := PORT # Integration checks use a separate port; shipping defaults to 7777.

func set_game_mode(value: String) -> bool:
	if value not in ["co_op", "tag"]: return false
	if mode != "offline" and not (is_host() and phase == "lobby"):
		status = "The host can change modes while everyone is in the lobby"
		return false
	game_mode = value
	_reset_player_tags()
	_send_phase_snapshot()
	return true

func cycle_game_mode() -> bool:
	return set_game_mode("tag" if game_mode == "co_op" else "co_op")

func is_local_tagger() -> bool:
	return game_mode == "tag" and phase == "playing" and tagger_id == multiplayer.get_unique_id()

func local_tag_total() -> int:
	return int(tag_scores.get(multiplayer.get_unique_id(), 0))

func player_tag_summary() -> String:
	if game_mode != "tag": return "Co-op forest chase"
	if members.size() < 2: return "Player Tag needs at least two players"
	var profile: Dictionary = profiles.get(tagger_id, {})
	var player_name := str(profile.get("name", "Host" if tagger_id == 1 else "Player %s" % tagger_id))
	return "%s is IT · %s tags · your tags: %s" % [player_name, tag_transfers, tag_scores.get(multiplayer.get_unique_id(), 0)]

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

func room_roster() -> Array:
	var roster: Array = []
	var ids := members.keys()
	ids.sort()
	for id in ids:
		# Profiles are cosmetic. Host and local flags always come from transport IDs.
		var profile: Dictionary = profiles.get(id, {})
		roster.append({"id": int(id), "label": "Host" if int(id) == 1 else "Player %s" % id,
			"host": int(id) == 1, "local": int(id) == multiplayer.get_unique_id(),
			"name": str(profile.get("name", "Host" if int(id) == 1 else "Player %s" % id)),
			"level": int(profile.get("level", 1)), "avatar": profile.get("avatar", PackedByteArray()),
			"tagger": game_mode == "tag" and int(id) == tagger_id})
	return roster

func can_start_round() -> bool:
	return is_host() and phase == "lobby"

func start_round() -> bool:
	if not can_start_round():
		if is_client(): status = "Only the host can start the room"
		return false
	if game_mode == "tag" and members.size() < 2:
		status = "Player Tag needs at least two players — invite a friend first"
		return false
	_set_phase("loading")
	status = "Loading — preparing the shared round"
	_send_phase_snapshot()
	return true

func complete_loading(expected_generation := -1) -> bool:
	if not is_host() or phase != "loading": return false
	if expected_generation >= 0 and expected_generation != phase_generation: return false
	game.restart()
	_set_phase("playing")
	status = "Playing — PC + Quest %s (%s/%s players)" % [_mode_label(), members.size(), MAX_PLAYERS]
	_send_phase_snapshot()
	return true

func _set_phase(next_phase: String) -> void:
	if next_phase not in ["lobby", "loading", "playing"] or next_phase == phase: return
	phase = next_phase
	phase_generation += 1
	if game != null and game.has_method("on_lobby_phase_changed"):
		game.on_lobby_phase_changed(phase)

func host() -> void:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1, 4)
	if error != OK:
		status = "Cannot host on UDP %s (error %s)" % [port, error]
		return
	multiplayer.multiplayer_peer = peer
	mode = "hosting"
	_set_phase("lobby")
	status = "Lobby — share IP %s, UDP %s; host starts the round" % [address, port]
	round_id += 1
	game.restart()
	members[1] = local_pose()
	if not local_profile.is_empty(): profiles[1] = local_profile.duplicate(true)
	_reset_player_tags()

func join(ip: String) -> void:
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address() or ip.contains(":"):
		status = "Enter the host's IPv4 address (example: 192.168.1.25)"
		return
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, port, 4)
	if error != OK:
		status = "Cannot connect (error %s)" % error
		return
	multiplayer.multiplayer_peer = peer
	mode = "joining"
	_set_phase("lobby")
	status = "Connecting to %s:%s…" % [ip, port]
	join_clock = 0
	for bot in game.bots: bot.active = false

func leave(message := "Solo — host or join to play together") -> void:
	var was_online := mode != "offline"
	var voice: Node = game.get("voice") if game != null else null
	if voice != null and voice.has_method("shutdown"): voice.shutdown()
	mode = "offline"
	phase_generation += 1
	_set_phase("playing")
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	members.clear()
	profiles.clear()
	profile_received_at.clear()
	_reset_player_tags()
	for avatar in avatars.values(): avatar.queue_free()
	avatars.clear()
	bot_targets.clear()
	received_sequence = -1
	received_round = -1
	status = message
	if was_online: game.restart()
	# Leaving can occur after the playing phase arrived but before local loading
	# finished. Notify even when the phase string did not change.
	if game != null and game.has_method("on_network_left"):
		game.on_network_left()

func _connected() -> void:
	if mode == "joining": _hello.rpc_id(1, PROTOCOL, GAME_VERSION)

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(protocol: int, version: String) -> void:
	if not is_host(): return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1: return
	if protocol != PROTOCOL or version != GAME_VERSION:
		_rejected.rpc_id(sender, "Version mismatch — install matching PC and Quest " + GAME_VERSION + " builds")
		return
	if members.has(sender):
		# Repeating a handshake cannot reset a member's pose or match score.
		_welcome.rpc_id(sender, make_snapshot())
		_sync_profiles.rpc_id(sender, profiles)
		return
	if not members.has(sender) and members.size() >= MAX_PLAYERS:
		_rejected.rpc_id(sender, "Room full — up to %s players" % MAX_PLAYERS)
		return
	members[sender] = {"active": false, "seen": Time.get_ticks_msec()}
	tag_scores[sender] = 0
	_welcome.rpc_id(sender, make_snapshot())
	# Reliable membership reaches existing peers before later reliable profiles.
	_send_phase_snapshot()
	_sync_profiles.rpc_id(sender, profiles)
	_send_snapshot()

@rpc("authority", "call_remote", "reliable", 0)
func _rejected(message: String) -> void:
	leave(message)

@rpc("authority", "call_remote", "reliable", 0)
func _welcome(state: Dictionary) -> void:
	if mode != "joining": return
	mode = "connected"
	game.player.reset_player()
	apply_snapshot(state)
	if not local_profile.is_empty():
		profile_received_at[0] = Time.get_ticks_msec()
		_submit_profile.rpc_id(1, local_profile)
	if phase == "playing": game.lobby.set_open(false)

func local_pose() -> Dictionary:
	var player = game.player
	var head_position: Vector3 = player.head.global_position
	var left: Vector3 = player.hand_visuals[0].global_position if player.xr_running else head_position + Vector3(-0.3, -0.5, 0)
	var right: Vector3 = player.hand_visuals[1].global_position if player.xr_running else head_position + Vector3(0.3, -0.5, 0)
	return {"body": player.global_position, "head": head_position, "rotation": player.head.global_rotation,
		"left": left, "right": right, "vr": player.xr_running,
		"peer_id": multiplayer.get_unique_id(),
		"active": player.tracked and player.input_allowed,
		"tag": not player.xr_running and player.input_allowed and Input.is_physical_key_pressed(KEY_E),
		"seen": Time.get_ticks_msec()}

func valid_vector(value: Vector3) -> bool:
	return value.is_finite()

func _mode_label() -> String:
	return "Player Tag" if game_mode == "tag" else "co-op"

func _sanitize_profile(value: Dictionary) -> Dictionary:
	# The shared sanitizer validates PNG metadata before any texture decoding.
	if not ResourceLoader.exists("res://scripts/profile_state.gd"): return {}
	var raw_name: Variant = value.get("name", "Monke")
	var raw_avatar: Variant = value.get("avatar", PackedByteArray())
	if not raw_name is String or raw_name.length() > 128: return {}
	if not raw_avatar is PackedByteArray or raw_avatar.size() > 6000: return {}
	var script: Script = load("res://scripts/profile_state.gd")
	var clean: Variant = script.call("sanitize_public_profile", {"name": raw_name, "xp": value.get("xp", 0), "avatar": raw_avatar})
	return clean if clean is Dictionary else {}

func publish_profile(value: Dictionary) -> bool:
	var clean := _sanitize_profile(value)
	if clean.is_empty(): return false
	local_profile = clean
	if is_host():
		profiles[1] = clean.duplicate(true)
		_send_profiles()
	elif mode == "connected":
		# Queue the newest edit. Repeated edits cannot flood the room, and the last
		# edit still arrives after the interval instead of silently disappearing.
		_flush_local_profile()
	return true

func _flush_local_profile() -> void:
	if mode != "connected" or local_profile.is_empty(): return
	var now := Time.get_ticks_msec()
	if now - int(profile_received_at.get(0, -PROFILE_INTERVAL_MS)) < PROFILE_INTERVAL_MS: return
	if profiles.get(multiplayer.get_unique_id(), {}) == local_profile: return
	profile_received_at[0] = now
	_submit_profile.rpc_id(1, local_profile)

@rpc("any_peer", "call_remote", "reliable", 0)
func _submit_profile(value: Dictionary) -> void:
	if not is_host(): return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not members.has(sender): return
	var now := Time.get_ticks_msec()
	if now - int(profile_received_at.get(sender, -PROFILE_INTERVAL_MS)) < PROFILE_INTERVAL_MS: return
	# Charge rejected attempts too, so malformed avatars cannot force decoding.
	profile_received_at[sender] = now
	var clean := _sanitize_profile(value)
	if clean.is_empty(): return
	profiles[sender] = clean
	_send_profiles()

func _send_profiles() -> void:
	if not is_host(): return
	if not multiplayer.get_peers().is_empty(): _sync_profiles.rpc(profiles)
	update_avatars(members)

@rpc("authority", "call_remote", "reliable", 0)
func _sync_profiles(value: Dictionary) -> void:
	if mode != "connected": return
	var clean: Dictionary = {}
	# Never trust an entry to grant roles or replace the transport's membership.
	for id in value:
		if not id is int or not members.has(id) or not value[id] is Dictionary: continue
		var profile := _sanitize_profile(value[id])
		if not profile.is_empty(): clean[id] = profile
	profiles = clean
	update_avatars(members)

func _reset_player_tags() -> void:
	tag_scores.clear()
	for id in members: tag_scores[id] = 0
	tag_transfers = 0
	tagger_id = 0
	if game_mode == "tag" and not members.is_empty():
		var ids := members.keys()
		ids.sort()
		tagger_id = int(ids[0])
	tag_cooldown_until = Time.get_ticks_msec() + TAG_COOLDOWN_MS
	_tag_events.clear()

func _usable_tag_pose(pose: Dictionary) -> bool:
	if not pose.get("active", false) or Time.get_ticks_msec() - int(pose.get("seen", 0)) >= STALE_MS: return false
	for key in ["body", "head", "rotation", "left", "right"]:
		if not pose.get(key) is Vector3 or not valid_vector(pose[key]): return false
	var body: Vector3 = pose.body
	var head: Vector3 = pose.head
	var reach := MAX_VR_HAND_DISTANCE if pose.get("vr", false) else MAX_DESKTOP_HAND_DISTANCE
	return absf(body.x) <= 18 and absf(body.z) <= 18 and body.y >= -12 and body.y <= 30 \
		and head.distance_to(body) <= 3.5 and pose.left.distance_to(head) <= reach and pose.right.distance_to(head) <= reach

func _distance_to_body(point: Vector3, head: Vector3) -> float:
	var top := head + Vector3.DOWN * 0.3
	var bottom := head + Vector3.DOWN * 1.12
	var axis := bottom - top
	var closest := top + axis * clampf((point - top).dot(axis) / axis.length_squared(), 0, 1)
	return point.distance_to(closest)

func _advance_player_tags() -> void:
	if not is_host() or game_mode != "tag" or phase != "playing" or game.finished or members.size() < 2: return
	if game.get("developer_round_paused") == true: return
	if Time.get_ticks_msec() < tag_cooldown_until or not members.has(tagger_id): return
	var source: Dictionary = members[tagger_id]
	if not _usable_tag_pose(source): return
	var ids := members.keys()
	ids.sort()
	for id in ids:
		if int(id) == tagger_id: continue
		var target: Dictionary = members[id]
		if not _usable_tag_pose(target): continue
		var touched: bool = (_distance_to_body(source.left, target.head) < 0.42 or _distance_to_body(source.right, target.head) < 0.42) if source.vr \
			else (source.tag and _distance_to_body(source.head, target.head) < 1.7)
		if not touched: continue
		var previous := tagger_id
		tagger_id = int(id)
		tag_scores[previous] = int(tag_scores.get(previous, 0)) + 1
		tag_transfers += 1
		tag_cooldown_until = Time.get_ticks_msec() + TAG_COOLDOWN_MS
		_emit_player_tag(round_id, tag_transfers, previous, tagger_id)
		if not multiplayer.get_peers().is_empty(): _player_tagged.rpc(round_id, tag_transfers, previous, tagger_id)
		_send_snapshot()
		return

func _emit_player_tag(event_round: int, event_sequence: int, tagger: int, target: int) -> void:
	var key := "%s:%s" % [event_round, event_sequence]
	if _tag_events.has(key): return
	_tag_events[key] = true
	# Bound the replay cache even if a long round is extended by a developer.
	if _tag_events.size() > 1024: _tag_events.erase(_tag_events.keys()[0])
	if game.has_method("on_player_tagged"): game.on_player_tagged(tagger, target, key)

@rpc("authority", "call_remote", "reliable", 0)
func _player_tagged(event_round: int, event_sequence: int, tagger: int, target: int) -> void:
	if mode != "connected" or game_mode != "tag" or event_round < received_round or event_sequence <= 0: return
	if not members.has(tagger) or not members.has(target) or tagger == target: return
	_emit_player_tag(event_round, event_sequence, tagger, target)

func notify_bot_tag(tagger: int, index: int) -> void:
	if is_client() or game_mode != "co_op" or index < 0 or index >= game.bots.size(): return
	if tagger == 0: tagger = multiplayer.get_unique_id()
	if is_host() and not members.has(tagger): return
	_emit_bot_tag(round_id, tagger, index)
	if is_host() and not multiplayer.get_peers().is_empty(): _bot_tagged.rpc(round_id, tagger, index)

func _emit_bot_tag(event_round: int, tagger: int, index: int) -> void:
	var key := "bot:%s:%s" % [event_round, index]
	if _tag_events.has(key): return
	_tag_events[key] = true
	if _tag_events.size() > 1024: _tag_events.erase(_tag_events.keys()[0])
	if game.has_method("on_bot_tagged"): game.on_bot_tagged(tagger, index, key)

@rpc("authority", "call_remote", "reliable", 0)
func _bot_tagged(event_round: int, tagger: int, index: int) -> void:
	if mode != "connected" or game_mode != "co_op" or event_round < received_round: return
	if not members.has(tagger) or index < 0 or index >= game.bots.size(): return
	_emit_bot_tag(event_round, tagger, index)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_pose(pose_round: int, body: Vector3, head: Vector3, rotation: Vector3, left: Vector3, right: Vector3, vr: bool, active: bool, tag: bool) -> void:
	if not is_host(): return
	var sender := multiplayer.get_remote_sender_id()
	if not members.has(sender) or pose_round != round_id: return
	if not valid_vector(body) or not valid_vector(head) or not valid_vector(rotation) or not valid_vector(left) or not valid_vector(right): return
	if absf(body.x) > 18 or absf(body.z) > 18 or body.y < -12 or body.y > 30: return
	var reach := MAX_VR_HAND_DISTANCE if vr else MAX_DESKTOP_HAND_DISTANCE
	if head.distance_to(body) > 3.5 or left.distance_to(head) > reach or right.distance_to(head) > reach: return
	members[sender] = {"body": body, "head": head, "rotation": rotation, "left": left, "right": right,
		"vr": vr, "active": active, "tag": tag, "seen": Time.get_ticks_msec(), "peer_id": sender}

func participant_poses() -> Array:
	var result: Array = []
	if mode != "offline" and phase != "playing": return result
	if is_host():
		members[1] = local_pose()
		for pose in members.values():
			if pose.get("active", false) and Time.get_ticks_msec() - pose.get("seen", 0) < STALE_MS: result.append(pose)
	else:
		var pose := local_pose()
		if pose.active: result.append(pose)
	return result

func round_restarted() -> void:
	if mode == "offline":
		round_id += 1
		_reset_player_tags()
	if is_host():
		round_id += 1
		_reset_player_tags()
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
		"score": game.score, "finished": game.finished, "bots": bot_state, "players": players,
		"developer_paused": game.get("developer_round_paused") == true,
		"phase": phase, "ready": phase == "playing", "game_mode": game_mode,
		"tagger": tagger_id, "tag_scores": tag_scores.duplicate(), "tag_transfers": tag_transfers}

func _send_snapshot() -> void:
	if is_host() and not multiplayer.get_peers().is_empty(): _snapshot.rpc(make_snapshot())

func _send_phase_snapshot() -> void:
	if is_host() and not multiplayer.get_peers().is_empty(): _phase_snapshot.rpc(make_snapshot())

@rpc("authority", "call_remote", "reliable", 0)
func _phase_snapshot(state: Dictionary) -> void:
	if mode == "connected": apply_snapshot(state)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _snapshot(state: Dictionary) -> void:
	if mode == "connected": apply_snapshot(state)

func apply_snapshot(state: Dictionary) -> void:
	if state.sequence <= received_sequence or state.round < received_round: return
	received_sequence = state.sequence
	var new_round: bool = state.round != received_round
	received_round = state.round
	# Keys include the round. Keep the bounded cache across a snapshot arriving
	# after its reliable tag event so that event cannot award progress twice.
	game_mode = str(state.get("game_mode", "co_op"))
	if game_mode not in ["co_op", "tag"]: game_mode = "co_op"
	tagger_id = int(state.get("tagger", 0))
	tag_scores = state.get("tag_scores", {}).duplicate()
	tag_transfers = int(state.get("tag_transfers", 0))
	game.remaining = state.remaining
	game.score = state.score
	game.finished = state.finished
	game.set("developer_round_paused", state.get("developer_paused", false) == true)
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
	members = state.players.duplicate(true)
	update_avatars(state.players)
	_set_phase(str(state.get("phase", "playing")))
	var phase_label := "Waiting for host" if phase == "lobby" else ("Loading" if phase == "loading" else "Playing")
	status = "%s — PC + Quest %s (%s/%s players)" % [phase_label, _mode_label(), state.players.size(), MAX_PLAYERS]

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
		avatars[id].apply_profile(profiles.get(id, {}))
		avatars[id].set_tagged(game_mode == "tag" and int(id) == tagger_id)
	for id in avatars.keys():
		if not players.has(id):
			avatars[id].queue_free()
			avatars.erase(id)

func _peer_left(id: int) -> void:
	members.erase(id)
	profiles.erase(id)
	profile_received_at.erase(id)
	tag_scores.erase(id)
	var voice: Node = game.get("voice") if game != null else null
	if voice != null and voice.has_method("remove_peer"): voice.remove_peer(id)
	if tagger_id == id:
		var ids := members.keys()
		ids.sort()
		tagger_id = int(ids[0]) if not ids.is_empty() else 0
		tag_cooldown_until = Time.get_ticks_msec() + TAG_COOLDOWN_MS
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)
	# ENet can still list the closing peer during its disconnect signal.
	# Publish after that peer has been removed from the transport's peer list.
	call_deferred("_send_profiles")
	call_deferred("_send_snapshot")

func _physics_process(delta: float) -> void:
	if mode == "joining":
		join_clock += delta
		if join_clock > 10: leave("Connection timed out — check host IP and UDP 7777")
	if mode == "offline": return
	if mode == "connected": _flush_local_profile()
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
	if is_host() and game_mode == "tag" and phase == "playing":
		members[1] = local_pose()
		_advance_player_tags()
	if mode == "connected":
		for i in range(bot_targets.size()):
			game.bots[i].global_position = game.bots[i].global_position.lerp(bot_targets[i][0], 1.0 - exp(-15 * delta))
