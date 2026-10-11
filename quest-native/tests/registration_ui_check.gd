extends SceneTree

# Drive the real scene and account controls. Provider replies are mocked;
# this suite never creates remote accounts or sends credentials over a network.
const PLAYER_ID := "AABB001122334455"
const DEVICE_ID := "FFEEDD0011223344"
const USERNAME := "ui_test_player"
const EMAIL := "player@example.invalid"
const PASSWORD := "  ui-test-password  "
const TICKET := "test-only-ui-session-ticket"
var checks := 0
var failures := 0

class MockAccount:
	extends "res://scripts/playfab_account.gd"
	var replies: Array[Dictionary] = []
	var calls: Array[Dictionary] = []
	var block_api := ""
	var blocked := false
	var password_clear_at_request := true
	signal release_reply

	func client_request(_api: String, _payload: Dictionary) -> Dictionary:
		# Profile initialization runs beside the account UI in the real scene.
		# Keep its independent read out of the ordered authentication replies.
		await get_tree().process_frame
		return {"ok": true, "data": {"Data": {}}}

	func _request(api: String, payload: Dictionary, ticket := "") -> Dictionary:
		calls.append({"api": api, "payload": payload.duplicate(true), "ticket": ticket})
		var menu = get_parent().get("account_menu")
		password_clear_at_request = password_clear_at_request and menu._password.is_empty() and menu._password_edit.text.is_empty()
		var reply: Dictionary = replies.pop_front() if not replies.is_empty() else {"ok": false}
		if api == block_api:
			block_api = ""
			blocked = true
			await release_reply
			blocked = false
		else:
			await get_tree().process_frame
		return reply

class MenuHarness:
	extends Node3D
	var player: Node3D
	var frontend_state := "main_menu"
	var frontend_status := "Choose your forest adventure."
	var play_mode_notice := ""
	var profile_summary := "Test Monke · Level 12"
	var account_status := "Signed out"
	var account_error_code := ""
	var account_id := ""
	var account_configured := true
	var account_busy := false
	var account_signed_in := false
	var account_is_developer := false
	var account_has_credentials := false
	var lobby_is_staging := true
	var lobby_can_start := true
	var lobby_members: Array = [{"name": "Forest Monke", "level": 12, "is_host": true, "is_self": true}]
	var network_mode := "offline"
	var network_status := "Choose Host to invite your friends."
	var session_address := "127.0.0.1"
	var room_game_mode := "coop"
	var room_mode_label := "Co-op chase"
	var host := true
	var callbacks: Dictionary = {}
	func called(action: String) -> void: callbacks[action] = int(callbacks.get(action, 0)) + 1
	func can_open_account_menu() -> bool: return true
	func on_account_menu_open() -> void: called("account_open")
	func on_account_menu_closed() -> void: called("account_close")
	func on_first_time_account_closed() -> void: called("first_close")
	func open_profile_menu() -> void: called("profile")
	func open_tutorial_menu() -> void: called("tutorial")
	func open_voice_menu() -> void: called("voice")
	func open_account_menu() -> void: called("account")
	func open_multiplayer_lobby() -> void: called("lobby")
	func can_open_lobby_menu() -> bool: return true
	func can_resume_play() -> bool: return false
	func can_switch_play_mode(_mode: String) -> bool: return false
	func is_session_host() -> bool: return host
	func cycle_room_mode() -> void:
		called("mode")
		room_game_mode = "tag" if room_game_mode == "coop" else "coop"
		room_mode_label = "Player tag" if room_game_mode == "tag" else "Co-op chase"

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func settle(frames := 4) -> void:
	for index in range(frames): await process_frame

func enter_text(control: LineEdit, value: String) -> void:
	control.text = value
	control.text_changed.emit(value)

func fill(menu: Node, username := USERNAME, email := EMAIL, password := PASSWORD) -> void:
	enter_text(menu._username_edit, username)
	enter_text(menu._email_edit, email)
	enter_text(menu._password_edit, password)

func press_key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func password_enter(menu: Node) -> void:
	menu._password_edit.grab_focus()
	# Emit the actual LineEdit Enter signal so this checks its connected route
	# independently of headless operating-system keyboard event accumulation.
	menu._password_edit.text_submitted.emit(menu._password_edit.text)
	await process_frame

func proof(id: String, username: String) -> Dictionary:
	return {"ok": true, "data": {"AccountInfo": {"PlayFabId": id, "Username": username}}}

func credential_replies(id: String) -> Array[Dictionary]:
	return [
		{"ok": true, "data": {"PlayFabId": id, "SessionTicket": TICKET}},
		proof(id, USERNAME),
		{"ok": true, "data": {"Data": {}}}
	]

func reset_signed_out(game: Node, account: MockAccount) -> void:
	game.account_menu.set_open(false)
	account.sign_out()
	account.calls.clear()
	account.replies.clear()
	account.password_clear_at_request = true
	game.open_account_menu()
	game.account_menu.refresh_status()

func run() -> void:
	var game = load("res://forest.tscn").instantiate()
	root.add_child(game)
	await settle()
	var original = game.account
	original.state_changed.disconnect(game._account_changed)
	var account := MockAccount.new()
	game.add_child(account)
	account.set_process(false)
	game.account = account
	account.state_changed.connect(game._account_changed)
	original.queue_free()
	game.main_menu._dispatch("account")
	var menu = game.account_menu
	check(menu.is_open and not game.main_menu.is_open and menu._submission_action == "register", "main-menu Account opens a fresh Create account form")
	check(menu._desktop_buttons["mode:register"].button_pressed and not menu._desktop_buttons["mode:login"].button_pressed, "desktop mode selectors mark Create account as selected")
	fill(menu)
	menu._username_edit.grab_focus()
	press_key(KEY_TAB)
	await settle(1)
	check(root.get_viewport().gui_get_focus_owner() == menu._email_edit and menu.is_open and menu._password == PASSWORD, "Tab moves to Email without closing Account or clearing the password")
	check(menu._password_edit.secret and not menu._world_fields["password"].text.contains(PASSWORD), "desktop and VR controls mask the password")
	await test_invalid_details(menu, account)
	await test_enter_registration(menu, account)
	await test_existing_account_modes(game, menu, account)
	await test_selected_sign_in(game, menu, account)
	await test_device_upgrade(game, menu, account)
	await test_vr_controls(game, menu, account)
	menu.set_open(false)
	check(menu._password.is_empty() and menu._password_edit.text.is_empty() and game.main_menu.is_open, "closing Account clears credentials and restores its main menu")
	game.queue_free()
	await process_frame
	await test_polished_menu_routes()
	print("Registration UI checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_invalid_details(menu: Node, account: MockAccount) -> void:
	for fields in [["a@b", EMAIL, PASSWORD], [USERNAME, "invalid@example", PASSWORD], [USERNAME, EMAIL, "short"]]:
		fill(menu, fields[0], fields[1], fields[2])
		check(menu._desktop_buttons["submit"].disabled and not menu._action_enabled("register"), "locally invalid registration disables its submit control")
		var before := account.calls.size()
		await password_enter(menu)
		check(account.calls.size() == before and menu._password == fields[2] and menu._password_edit.text == fields[2], "invalid Enter preserves the password and makes no provider request")
		check(not menu._desktop_status.text.is_empty() and menu._desktop_status.text == menu._world_status.text, "local validation feedback appears on desktop and VR")
		check(menu._desktop_status.text.contains("PM-A01") and menu._desktop_code.text.contains("PM-A01"), "local form validation includes a stable support code")
	fill(menu)
	check(not menu._desktop_buttons["submit"].disabled, "corrected registration details enable submit without reopening the form")

func test_enter_registration(menu: Node, account: MockAccount) -> void:
	account.replies = credential_replies(PLAYER_ID)
	account.block_api = "RegisterPlayFabUser"
	await password_enter(menu)
	check(account.blocked and account.calls.size() == 1 and account.calls[0].api == "RegisterPlayFabUser", "Enter in Create account mode submits registration rather than a login")
	if account.calls.is_empty():
		return
	check(account.calls[0].payload.Username == USERNAME and account.calls[0].payload.Email == EMAIL and account.calls[0].payload.Password == PASSWORD, "registration sends all entered fields and preserves password whitespace")
	check(account.password_clear_at_request and menu._password.is_empty() and menu._password_edit.text.is_empty(), "a real registration submission immediately clears transient password controls")
	check(not menu._username_edit.editable and not menu._email_edit.editable and not menu._password_edit.editable and menu._desktop_buttons["submit"].disabled, "pending registration locks fields and submit")
	check(menu._desktop_buttons["mode:login"].disabled and menu._desktop_buttons["mode:register"].disabled and not menu._desktop_buttons["logout"].disabled, "pending registration locks mode switches while keeping cancellation available")
	await password_enter(menu)
	check(account.calls.size() == 1, "Enter during a pending registration cannot submit a duplicate request")
	account.release_reply.emit()
	await settle(5)
	check(account.has_credentials and account.account_id == PLAYER_ID and menu._submission_action == "login", "verified registration changes the default form to Sign in")

func test_existing_account_modes(game: Node, menu: Node, account: MockAccount) -> void:
	menu.set_open(false)
	game.open_account_menu()
	check(menu._submission_action == "login" and menu._desktop_buttons["mode:login"].button_pressed, "reopening a registered account defaults to Sign in")
	menu._desktop_buttons["mode:register"].pressed.emit()
	fill(menu)
	check(menu._submission_action == "register" and menu._desktop_buttons["submit"].disabled and menu._desktop_help.text.contains("Sign out"), "registered players can select Create account and see why they must sign out")
	var before := account.calls.size()
	await password_enter(menu)
	check(account.calls.size() == before and menu._password == PASSWORD, "already registered account cannot be upgraded again or lose its entered password")
	menu._desktop_buttons["mode:login"].pressed.emit()
	account.replies = credential_replies(PLAYER_ID)
	await password_enter(menu)
	await settle(5)
	check(account.calls[before].api == "LoginWithEmailAddress" and account.has_credentials, "choosing Sign in submits the existing registered account")

func test_selected_sign_in(game: Node, menu: Node, account: MockAccount) -> void:
	reset_signed_out(game, account)
	menu._desktop_buttons["mode:login"].pressed.emit()
	fill(menu)
	account.status = "Device sign-in status refreshed"
	menu.refresh_status()
	check(menu._submission_action == "login", "an unrelated account refresh preserves the player's selected Sign in mode")
	await password_enter(menu)
	await settle()
	check(account.calls.size() == 1 and account.calls[0].api == "LoginWithEmailAddress" and not account.calls[0].payload.has("CreateAccount"), "selected Sign in never guesses registration from a completely filled form")
	check(menu._password.is_empty() and menu._password_edit.text.is_empty(), "failed provider login still clears the submitted password")
	account.calls.clear()
	fill(menu, USERNAME, "", PASSWORD)
	await password_enter(menu)
	await settle()
	check(account.calls.size() == 1 and account.calls[0].api == "LoginWithPlayFab" and account.calls[0].payload.Username == USERNAME, "selected Sign in accepts Username when Email is empty")
	menu.set_open(false)
	game.open_account_menu()
	check(menu._submission_action == "register" and menu._desktop_buttons["mode:register"].button_pressed and menu._desktop_buttons["submit"].text == "Register account", "reopening a signed-out form resets its default and submit caption to Create account")

func test_device_upgrade(game: Node, menu: Node, account: MockAccount) -> void:
	reset_signed_out(game, account)
	account._ticket = TICKET
	account.account_id = DEVICE_ID
	account.status = "Signed in with a device account"
	account.state_changed.emit()
	menu.refresh_status()
	check(menu._submission_action == "register" and menu._desktop_help.text.contains("stays the same"), "anonymous device accounts default to registration with ID preservation guidance")
	fill(menu)
	account.replies = [{"ok": true, "data": {"Username": USERNAME}}, proof(DEVICE_ID, USERNAME), {"ok": true, "data": {"Data": {}}}]
	menu._desktop_buttons["submit"].pressed.emit()
	await settle(6)
	check(account.calls.size() == 3 and account.calls[0].api == "AddUsernamePassword" and account.calls[0].ticket == TICKET, "actual Register button upgrades a signed-in device account using its ticket")
	check(account.account_id == DEVICE_ID and account.has_credentials and account.password_clear_at_request, "device upgrade preserves the public ID and clears submitted password")

func test_vr_controls(game: Node, menu: Node, account: MockAccount) -> void:
	reset_signed_out(game, account)
	game.player.xr_running = true
	menu._update_visibility()
	fill(menu)
	check(menu._world_panel.visible and not menu._canvas.visible, "VR presents the world account form instead of the desktop overlay")
	var panel_bounds: Rect2 = Rect2(-menu.panel_size * 0.5, menu.panel_size)
	var bounds_ok := true
	var no_overlap := true
	var actions: Array[String] = []
	for index in range(menu._world_buttons.size()):
		var button: Dictionary = menu._world_buttons[index]
		var rect: Rect2 = button.rect
		bounds_ok = bounds_ok and panel_bounds.encloses(rect)
		for other in range(index):
			no_overlap = no_overlap and not rect.intersects(menu._world_buttons[other].rect)
		var center := rect.get_center()
		var hit: Dictionary = menu._intersect_panel(menu._world_panel.to_global(Vector3(center.x, center.y, 1)), -menu._world_panel.global_basis.z)
		bounds_ok = bounds_ok and hit.get("button", -1) == (index if button.mesh.visible else -1)
		actions.append(button.action)
	check(bounds_ok and no_overlap, "VR controls stay inside the original panel with distinct controller-ray targets")
	check(actions.has("mode:register") and actions.has("mode:login") and actions.has("submit") and actions.has("device") and actions.has("logout") and actions.has("close"), "VR exposes both account modes, selected submit, device account, sign-out and close")
	menu._dispatch("mode:login")
	check(menu._submission_action == "login" and menu._action_enabled("submit"), "VR can deliberately select Sign in with valid credentials")
	menu._dispatch("mode:register")
	check(menu._submission_action == "register" and menu._action_enabled("submit"), "VR can switch back to valid registration")
	check(not menu._world_fields["password"].text.contains(PASSWORD), "VR mode changes never reveal the plaintext password")
	account._ticket = TICKET
	account.account_id = DEVICE_ID
	menu._dispatch("logout")
	check(menu._password.is_empty() and menu._password_edit.text.is_empty(), "VR sign-out clears the password fields")
	game.player.xr_running = false
	menu._update_visibility()

func test_polished_menu_routes() -> void:
	var harness := MenuHarness.new()
	root.add_child(harness)
	var account = load("res://scripts/account_menu.gd").new()
	account.game = harness
	harness.add_child(account)
	account.set_first_time(true)
	account.set_open(true)
	check(account.first_time and account._desktop_heading.text.contains("Welcome") and account._submission_action == "register", "first-time registration shows its Welcome heading and Create account mode")
	check(account._desktop_buttons["close"].text == "Continue as guest" and account._desktop_help.text.contains("guest"), "first-time registration clearly offers guest play without mandatory account creation")
	account.select_mode("login")
	check(account._submission_action == "login" and account._desktop_buttons["mode:login"].button_pressed, "public mode selector lets returning players explicitly choose Sign in")
	fill(account)
	account._desktop_buttons["close"].pressed.emit()
	check(not account.first_time and harness.callbacks.get("first_close", 0) == 1 and harness.callbacks.get("account_close", 0) == 1 and account._password.is_empty(), "first-time Close clears the password and calls the guest flow once")
	account.set_open(true)
	check(account._desktop_heading.text == "Your account" and account._desktop_buttons["close"].text == "Back", "later account visits use the regular heading and Back action")
	harness.account_status = "PlayFab rejected this request. [PF-5847]"
	harness.account_error_code = "PF-5847"
	account.refresh_status()
	check(account._desktop_status.text.contains("PF-5847") and account._desktop_code.text.contains("PF-5847") and account._world_role.text.contains("PF-5847"), "provider support codes stay visible without inventing a meaning for unknown codes")
	account.set_open(false)
	var main = load("res://scripts/main_menu.gd").new()
	main.game = harness
	harness.add_child(main)
	main.set_open(true)
	for action in ["profile", "tutorial", "voice"]:
		check(main._desktop_buttons.has(action) and main._action_enabled(action), "main menu exposes the " + action + " destination")
		main._desktop_buttons[action].pressed.emit()
		check(harness.callbacks.get(action, 0) == 1, "actual main-menu button forwards the " + action + " callback")
	check(main._desktop_profile.text == harness.profile_summary and main._world_profile.text == harness.profile_summary, "main menu shows the player's level summary on desktop and VR")
	harness.frontend_state = "loading"
	main.refresh_status()
	main._desktop_buttons["profile"].pressed.emit()
	check(harness.callbacks.get("profile", 0) == 1 and main._desktop_buttons["profile"].disabled, "loading prevents a conflicting profile destination")
	harness.frontend_state = "lobby"
	main.set_open(false)
	var lobby = load("res://scripts/multiplayer_lobby.gd").new()
	lobby.game = harness
	harness.add_child(lobby)
	lobby.set_open(true)
	check(lobby._desktop_members[0].text.contains("Forest Monke") and lobby._desktop_members[0].text.contains("Lv 12") and lobby._desktop_members[0].text.contains("HOST"), "lobby roster shows public display names, levels and host markers")
	lobby._desktop_buttons["room_mode"].pressed.emit()
	check(harness.room_game_mode == "tag" and lobby._desktop_buttons["room_mode"].text.contains("Player tag"), "host mode button chooses Player tag and updates its visible label")
	harness.network_mode = "connected"
	harness.host = false
	lobby.refresh_status()
	lobby._desktop_buttons["room_mode"].pressed.emit()
	check(harness.callbacks.get("mode", 0) == 1 and lobby._desktop_buttons["room_mode"].disabled, "joining players cannot change the host's selected room mode")
	harness.host = true
	harness.lobby_is_staging = false
	lobby.refresh_status()
	check(not lobby._action_enabled("room_mode"), "room mode cannot change after the match starts")
	for menu in [main, lobby]:
		var bounds: Rect2 = Rect2(-menu.panel_size * 0.5, menu.panel_size)
		var targets_ok := true
		for index in range(menu._world_buttons.size()):
			var rect: Rect2 = menu._world_buttons[index].rect
			var center := rect.get_center()
			var hit: Dictionary = menu._intersect_panel(menu._world_panel.to_global(Vector3(center.x, center.y, 1)), -menu._world_panel.global_basis.z)
			targets_ok = targets_ok and bounds.encloses(rect) and hit.get("button", -1) == (index if menu._world_buttons[index].mesh.visible else -1)
			for other in range(index): targets_ok = targets_ok and not rect.intersects(menu._world_buttons[other].rect)
		check(targets_ok, menu.name + " updated VR actions fit distinct controller-ray targets")
	await test_responsive_forms(account, main, lobby)
	harness.queue_free()
	await process_frame

func test_responsive_forms(account: Node, main: Node, lobby: Node) -> void:
	var original_size: Vector2i = root.size
	var original_scale: Vector2i = root.content_scale_size
	for size in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(520, 640), Vector2i(360, 640)]:
		root.size = size
		root.content_scale_size = size
		await settle(6)
		var width := root.get_visible_rect().size.x
		for menu in [account, main, lobby]:
			menu._adapt_desktop_layout()
		await settle(3)
		check(account._desktop_fields.columns == (2 if width >= 700 else 1) and main._desktop_utilities.columns == (2 if width >= 600 else 1) and lobby._desktop_body.columns == (2 if width >= 820 else 1), "responsive account, utility and lobby grids adapt at width " + str(width))
		for menu in [account, main, lobby]:
			for other in [account, main, lobby]: other.set_open(other == menu)
			await settle(10)
			var frame: Dictionary = menu._desktop_frame
			check(frame.panel.size.x <= width - 47 and frame.scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and frame.scroll.follow_focus, menu.name + " fits the viewport width and keeps tall content accessible by scrolling")
	root.size = original_size
	root.content_scale_size = original_scale
	await settle()
