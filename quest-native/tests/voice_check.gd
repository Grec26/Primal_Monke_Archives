extends SceneTree

const Voice = preload("res://scripts/voice_chat.gd")
const VoiceMenu = preload("res://scripts/voice_menu.gd")
var checks := 0
var failures := 0

class FakeSession extends Node:
	var mode := "offline"
	var phase := "lobby"
	var members: Dictionary = {}
	func room_roster() -> Array:
		var result: Array = []
		for id in members:
			result.append({"id": id, "label": "Player %s" % id, "local": id == 1})
		return result

class FakePlayer extends Node3D:
	var head: Node3D
	var xr_running := false
	var hands: Array = []
	func _ready() -> void:
		head = Node3D.new()
		add_child(head)
		head.position = Vector3(0, 1.6, 0)
	func reset_tracking_history() -> void: pass

class FakeGame extends Node3D:
	var session: Node
	var player: Node3D
	var voice: Node
	var frontend_state := "playing"
	var xr_focused := true
	var opened := 0
	var closed := 0
	func on_feature_menu_open(_menu: Node) -> void: opened += 1
	func close_feature_menu(_menu: Node) -> void: closed += 1

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if value: print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func frame(value := 0.25) -> PackedByteArray:
	var samples := PackedFloat32Array()
	samples.resize(Voice.SAMPLES_PER_FRAME)
	samples.fill(value)
	return Voice.encode_pcm(samples)

func run() -> void:
	var game := FakeGame.new()
	root.add_child(game)
	game.session = FakeSession.new()
	game.add_child(game.session)
	game.player = FakePlayer.new()
	game.add_child(game.player)
	var voice := Voice.new()
	voice.game = game
	game.voice = voice
	game.add_child(voice)
	voice.set_process(false)
	voice._clock_ms = 1000
	var pcm := frame()
	check(not voice.enabled and voice.mic_muted and voice._microphone == null, "startup leaves voice and microphone off")
	voice.set_mic_muted(false)
	check(voice.mic_muted and voice._microphone == null, "unmute cannot enable a disabled microphone")
	voice.set_enabled(true)
	voice.set_mic_muted(false)
	check(not voice.submit_frame(pcm) and voice._microphone == null, "offline opt-in cannot transmit or start capture")
	voice._start_capture()
	check(voice._microphone == null, "headless mode never opens a microphone")
	check(pcm.size() == 640 and Voice.decode_pcm(pcm).size() == 320, "PCM encoding has exactly 20 ms at 16 kHz mono")
	check(absf(Voice.decode_pcm(pcm)[0].x - 0.25) < 0.0001, "PCM roundtrip preserves samples to 16-bit precision")
	check(Voice.decode_pcm(PackedByteArray([1, 2])).is_empty(), "malformed PCM is rejected before decoding")
	check(Voice.encode_pcm(PackedFloat32Array([0.1])).is_empty(), "partial capture frames cannot be sent")
	check(frame(INF).is_empty(), "nonfinite microphone values are rejected")
	var clipped := Voice.decode_pcm(frame(5.0))
	check(clipped[0].x < 1.0 and clipped[0].x > 0.99, "capture values clip to the 16-bit range")
	game.session.mode = "hosting"
	game.session.members = {1: {"head": Vector3(0, 1.6, 0), "seen": 1000}, 2: {"head": Vector3(2, 1.6, 0), "seen": 1000}, 3: {"head": Vector3(30, 1.6, 0), "seen": 1000}}
	check(not voice._ingest_submission(999, 1, pcm), "unregistered sender cannot submit voice before handshake")
	check(not voice._ingest_submission(2, -1, pcm), "negative voice sequence is rejected")
	check(not voice._ingest_submission(2, Voice.MAX_SEQUENCE + 1, pcm), "overflow voice sequence is rejected")
	check(not voice._ingest_submission(2, 1, PackedByteArray([1])), "truncated voice packet is rejected")
	var oversized := pcm.duplicate()
	oversized.append(0)
	check(not voice._ingest_submission(2, 1, oversized), "oversized voice packet is rejected")
	check(voice._senders.is_empty(), "invalid frames allocate no per-peer rate or replay state")
	check(voice._ingest_submission(2, 1, pcm), "registered sender frame reaches host validation")
	check(voice.received_frames == 1 and voice._queues[2].size() == 1, "opted-in host queues a validated remote frame")
	check(not voice._ingest_submission(2, 1, pcm), "duplicate sequence cannot replay audio")
	check(not voice._ingest_submission(2, 0, pcm), "stale sequence cannot replay audio")
	for sequence in range(2, 13): check(voice._ingest_submission(2, sequence, pcm), "bounded rate permits frame %s" % sequence)
	check(not voice._ingest_submission(2, 13, pcm), "per-sender burst limit rejects a flood")
	check(voice._queues[2].size() == Voice.MAX_QUEUE, "jitter queue drops old frames instead of growing")
	voice._clock_ms += 1000
	check(voice._ingest_submission(2, 13, pcm), "monotonic rate window refills without permanently blocking voice")
	voice.set_peer_muted(2, true)
	check(not voice._queues.has(2), "muting a player immediately drops queued audio")
	check(not voice._accept_playback(2, 14, pcm), "muted player cannot restore playback")
	voice.set_peer_muted(2, false)
	check(voice._accept_playback(2, 14, pcm), "explicit unmute permits only a fresh validated frame")
	voice.set_mic_muted(true)
	check(not voice.submit_frame(pcm), "muting the microphone blocks outgoing synthetic packets")
	voice.set_mic_muted(false)
	check(voice.submit_frame(pcm), "explicit unmute permits host voice transmission")
	voice._ptt_active = true
	voice._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(voice.mic_muted and not voice._ptt_active, "focus loss releases push-to-talk even without a key-up event")
	voice.set_mic_muted(false)
	game.session.phase = "playing"
	game.session.members[2].seen = voice._clock_ms
	game.session.members[3].seen = voice._clock_ms
	check(voice._audible_between(2, 1), "nearby players are audible in a running game")
	check(not voice._audible_between(3, 1), "distant players are filtered before relay or playback")
	check(not voice._accept_playback(3, 1, pcm), "out-of-range voice cannot enter the jitter buffer")
	game.session.members[2].seen = voice._clock_ms - Voice.STALE_POSE_MS - 1
	check(not voice._audible_between(2, 1), "stale pose cannot bypass proximity validation")
	game.session.phase = "loading"
	check(not voice._audible_between(2, 1), "loading phase cannot relay location-independent voice")
	game.session.phase = "lobby"
	check(voice._audible_between(3, 1), "lobby voice allows all registered room members")
	voice._sequence = Voice.MAX_SEQUENCE
	check(not voice.submit_frame(pcm), "sequence rollover cannot silently replay a previous session")
	voice.set_volume(INF)
	check(voice.volume == 0.8, "invalid volume is ignored")
	voice.set_volume(-100)
	check(voice.volume == 0.0, "volume clamps to a safe lower bound")
	voice.set_volume(100)
	check(voice.volume == 1.0, "volume clamps to a safe upper bound")
	voice.set_enabled(false)
	check(voice._queues.is_empty() and voice.mic_muted and not voice._accept_playback(2, 15, pcm), "disabling voice drops buffers and prevents incoming playback")
	voice.set_enabled(true)
	voice.remove_peer(2)
	check(not voice._senders.has(2) and not voice._receivers.has(2), "disconnect removes replay and rate state")
	check(not voice.muted_peers.has(2), "disconnect removes peer mute state")
	voice.shutdown()
	check(voice._sequence == 0 and voice._senders.is_empty() and voice._receivers.is_empty() and voice._queues.is_empty() and voice.mic_muted, "room shutdown clears all audio and resets outgoing sequences")
	check(voice._microphone == null, "privacy tests never started microphone capture")
	var menu := VoiceMenu.new()
	menu.game = game
	game.add_child(menu)
	menu.set_open(true)
	check(menu.is_open and game.opened == 1, "voice panel uses the common overlay route")
	check(menu._desktop_buttons.enable.text == "Disable voice" and menu._desktop_buttons.mic.text == "Unmute microphone", "voice panel clearly displays independent listening and microphone controls")
	menu._dispatch("mic")
	check(not voice.mic_muted, "voice panel unmute forwards an explicit user action")
	menu._dispatch("peer:0")
	check(voice.muted_peers.has(2), "voice panel can mute a selected remote player")
	menu._dispatch("enable")
	check(not voice.enabled and voice.mic_muted, "voice panel disable immediately revokes microphone access")
	check(not menu._action_enabled("mic"), "disabled voice panel cannot unmute capture")
	menu._dispatch("close")
	check(not menu.is_open and game.closed == 1, "voice panel closes through its underlying frontend route")
	var inside := true
	var panel_bounds := Rect2(-menu.panel_size * 0.5, menu.panel_size)
	for button in menu._world_buttons:
		inside = inside and panel_bounds.encloses(button.rect)
	check(inside, "all VR voice controls fit inside their selectable panel")
	await test_responsive_panel(menu, game)
	game.queue_free()
	await process_frame
	print("Voice checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_responsive_panel(menu: Node, game: Node) -> void:
	# Real Control layout, including a full room and a short / narrow viewport.
	# Remove project stretching so each width exercises the responsive branches.
	root.content_scale_size = Vector2i.ZERO
	for id in range(4, 9): game.session.members[id] = {"head": Vector3.ZERO, "seen": 1000}
	menu.set_open(true)
	menu.refresh_status()
	for width in [1280, 960, 520]:
		root.size = Vector2i(width, 420)
		for index in range(8): await process_frame
		var expected_columns := 2 if width >= 640 else 1
		check(menu._desktop_controls.columns == expected_columns and menu._desktop_peers.columns == expected_columns, "%s px voice controls adapt to %s columns" % [width, expected_columns])
		var panel: PanelContainer = menu._desktop_frame.panel
		var bounds := panel.get_global_rect()
		check(bounds.position.x >= 0 and bounds.end.x <= float(width) + 0.1, "%s px voice card fits the viewport without horizontal clipping" % width)
		var buttons_inside := true
		for button in menu._desktop_buttons.values():
			if button.visible:
				var button_bounds: Rect2 = button.get_global_rect()
				buttons_inside = buttons_inside and button_bounds.position.x >= bounds.position.x and button_bounds.end.x <= bounds.end.x + 0.1
		check(buttons_inside, "%s px visible voice buttons fit inside the card" % width)
		var scroll: ScrollContainer = menu._desktop_frame.scroll
		var bar := scroll.get_v_scroll_bar()
		check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and scroll.follow_focus and bar.max_value > bar.page, "%s px short voice screen scrolls to every player and Back button" % width)
	game.session.members = {1: {"head": Vector3.ZERO, "seen": 1000}}
	menu.refresh_status()
	check(menu._desktop_empty.visible and not menu._desktop_buttons["peer:0"].visible, "empty room shows useful help instead of seven inactive player slots")
