extends SceneTree

# No provider traffic or persistent device credential is used by these checks.
const DEV_ID := "AABBCCDDEEFF0011"
const PLAYER_ID := "1122334455667788"
const TEST_TICKET := "test-only-session-ticket"
const TEST_IDENTITY := "PM-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const TEST_USERNAME := "test_player"
const TEST_EMAIL := "player@example.invalid"
const TEST_PASSWORD := "  test-only-password  "
const ModeScript = preload("res://scripts/play_mode.gd")
var failures := 0

class MockAccount:
	extends "res://scripts/playfab_account.gd"
	var replies: Array[Dictionary] = []
	var calls: Array[Dictionary] = []
	var suspend_api := ""
	var blocked := false
	signal release_reply

	func _device_identity() -> String:
		return "PM-" + "0123456789abcdef".repeat(4)

	func _request(api: String, payload: Dictionary, ticket := "") -> Dictionary:
		calls.append({"api": api, "payload": payload.duplicate(true), "ticket": ticket})
		var reply: Dictionary = replies.pop_front() if not replies.is_empty() else {"ok": false}
		if api == suspend_api:
			suspend_api = ""
			blocked = true
			await release_reply
			blocked = false
		else:
			await get_tree().process_frame
		return reply

class StorageAccount:
	extends "res://scripts/playfab_account.gd"
	var storage_path := ""
	var requests := 0
	func _identity_path() -> String:
		return storage_path
	func _request(_api: String, _payload: Dictionary, _ticket := "") -> Dictionary:
		requests += 1
		await get_tree().process_frame
		return {"ok": false}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func fresh_account() -> MockAccount:
	var account := MockAccount.new()
	root.add_child(account)
	account.title_id = "1A7D9B"
	account.set_process(false)
	return account

func proof(id: String, username := "") -> Dictionary:
	return {"ok": true, "data": {"AccountInfo": {"PlayFabId": id, "Username": username}}}

func permissions(raw: Variant) -> Dictionary:
	return {"ok": true, "data": {"Data": {"PrimalMonkeDeveloperIds": raw}}}

func login_replies(id: String, raw: Variant) -> Array[Dictionary]:
	return [
		{"ok": true, "data": {"PlayFabId": id, "SessionTicket": TEST_TICKET}},
		proof(id), permissions(raw)
	]

func credential_replies(id: String, username: String, raw: Variant) -> Array[Dictionary]:
	var result := login_replies(id, raw)
	result[1] = proof(id, username)
	return result

func password_is_transient(account: MockAccount) -> bool:
	for property in account.get_property_list():
		if property.type == TYPE_STRING:
			var value: String = account.get(property.name)
			if value.contains(TEST_PASSWORD): return false
	return true

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func wait_blocked(account: MockAccount) -> void:
	var deadline := Time.get_ticks_msec() + 1000
	while not account.blocked and Time.get_ticks_msec() < deadline: await process_frame
	check(account.blocked, "mock provider suspends " + account.calls.back().api)

func run() -> void:
	await test_identity_and_role_proof()
	await test_private_identity_storage()
	await test_registration_and_credentials()
	await test_credential_generation_guards()
	await test_async_generation_guards()
	test_play_mode_selection()
	await test_game_handlers()
	print("Developer access checks complete; failures: %s" % failures)
	quit(0 if failures == 0 else 1)

func test_private_identity_storage() -> void:
	var account := StorageAccount.new()
	account.storage_path = "/tmp/primal-monke-test-identity-%s-%s.txt" % [OS.get_process_id(), Time.get_ticks_usec()]
	root.add_child(account)
	account.set_process(false)
	var credential := account._device_identity()
	var pattern := RegEx.new()
	pattern.compile("^PM-[0-9a-f]{64}$")
	check(pattern.search(credential) != null, "device identity uses 256 bits of cryptographic random credential data")
	check(FileAccess.file_exists(account.storage_path) and FileAccess.get_file_as_string(account.storage_path) == credential, "private device credential persists only to overridden temporary user-storage file")
	check(account._device_identity() == credential, "subsequent sign-in preserves existing device account credential")
	var restarted := StorageAccount.new()
	restarted.storage_path = account.storage_path
	root.add_child(restarted)
	restarted.set_process(false)
	check(restarted._device_identity() == credential, "new account node reuses stored identity across application sessions")
	var file := FileAccess.open(account.storage_path, FileAccess.WRITE)
	file.store_string(DEV_ID)
	file.close()
	var replacement := account._device_identity()
	check(pattern.search(replacement) != null and replacement != credential and replacement != DEV_ID, "malformed or claimed public ID cache is replaced by fresh private credential")
	DirAccess.remove_absolute(account.storage_path)
	account.storage_path += "/missing/identity.txt"
	account.title_id = "1A7D9B"
	await account.login_device()
	check(account.requests == 0 and not account.is_signed_in(), "unsavable identity blocks automatic account registration before provider request")
	restarted.queue_free()
	account.queue_free()
	await process_frame

func test_registration_and_credentials() -> void:
	var account := fresh_account()
	for values in [["ab", TEST_EMAIL, TEST_PASSWORD], ["x".repeat(21), TEST_EMAIL, TEST_PASSWORD], [TEST_USERNAME, "invalid-email", TEST_PASSWORD], [TEST_USERNAME, "a@@example.invalid", TEST_PASSWORD], [TEST_USERNAME, TEST_EMAIL, "short"], [TEST_USERNAME, TEST_EMAIL, "p".repeat(101)]]:
		await account.register(values[0], values[1], values[2])
		check(account.calls.is_empty() and not account.busy and not account.is_signed_in(), "invalid registration username/email/password stops before provider request")
	for values in [["", TEST_PASSWORD], ["ab", TEST_PASSWORD], [TEST_USERNAME, "short"], [TEST_EMAIL, "p".repeat(101)]]:
		await account.login_credentials(values[0], values[1])
		check(account.calls.is_empty() and not account.is_signed_in(), "invalid credential login stops before provider request")
	account.replies = credential_replies(PLAYER_ID, DEV_ID, JSON.stringify([DEV_ID]))
	await account.register(" " + DEV_ID + " ", " " + TEST_EMAIL + " ", TEST_PASSWORD)
	check(account.is_signed_in() and account.has_credentials and account.account_id == PLAYER_ID and not account.is_developer(), "ordinary registration cannot grant developer access by choosing developer ID as username")
	check(account.calls.size() == 3 and account.calls[0].api == "RegisterPlayFabUser" and account.calls[0].ticket.is_empty(), "signed-out registration uses public PlayFab signup followed by authenticated account proof")
	check(account.calls[0].payload == {"TitleId": "1A7D9B", "Username": DEV_ID, "Email": TEST_EMAIL, "Password": TEST_PASSWORD, "RequireBothUsernameAndEmail": true}, "signup payload trims identifier fields and preserves password without secret key or claimed account ID")
	check(password_is_transient(account), "registration leaves password out of account fields and status text")
	var calls_before := account.calls.size()
	await account.register(TEST_USERNAME, TEST_EMAIL, TEST_PASSWORD)
	check(account.calls.size() == calls_before and account.has_credentials and account.account_id == PLAYER_ID, "already registered account rejects second registration without replacing identity")
	account.sign_out()
	check(not account.has_credentials, "sign-out clears verified credential status")
	account.calls.clear()
	account.replies = credential_replies(PLAYER_ID, TEST_USERNAME, JSON.stringify([DEV_ID]))
	await account.login_credentials(" " + TEST_USERNAME + " ", TEST_PASSWORD)
	check(account.is_signed_in() and account.has_credentials and not account.is_developer(), "username/password login verifies provider account and ordinary role")
	check(account.calls[0].api == "LoginWithPlayFab" and account.calls[0].payload == {"TitleId": "1A7D9B", "Username": TEST_USERNAME, "Password": TEST_PASSWORD} and account.calls[0].ticket.is_empty(), "username login uses correct endpoint with no account creation or secret key")
	account.calls.clear()
	account.replies = credential_replies(PLAYER_ID, TEST_USERNAME, JSON.stringify([DEV_ID]))
	await account.login_credentials(" " + TEST_EMAIL + " ", TEST_PASSWORD)
	check(account.calls[0].api == "LoginWithEmailAddress" and account.calls[0].payload == {"TitleId": "1A7D9B", "Email": TEST_EMAIL, "Password": TEST_PASSWORD}, "email login selects separate official endpoint and exact credential fields")
	check(password_is_transient(account), "credential login retains no password in account fields or status")
	account.replies = [{"ok": false}]
	await account.login_credentials(TEST_USERNAME, TEST_PASSWORD)
	check(not account.is_signed_in() and not account.has_credentials and not account.is_developer() and not account.busy, "failed credential authentication revokes prior identity and access")
	account.replies = [{"ok": false}]
	await account.register(TEST_USERNAME, TEST_EMAIL, TEST_PASSWORD)
	check(not account.is_signed_in() and not account.has_credentials and not account.is_developer(), "provider signup rejection grants neither account nor developer privileges")
	account.replies = [{"ok": true, "data": {"PlayFabId": PLAYER_ID, "SessionTicket": TEST_TICKET, "Username": TEST_USERNAME}}, proof(DEV_ID, TEST_USERNAME)]
	await account.register(TEST_USERNAME, TEST_EMAIL, TEST_PASSWORD)
	check(not account.is_signed_in() and not account.has_credentials and not account.is_developer(), "signup result username cannot override mismatched authenticated ticket owner")
	account.replies = login_replies(PLAYER_ID, JSON.stringify([DEV_ID]))
	await account.login_device()
	check(account.is_signed_in() and not account.has_credentials, "automatic anonymous device account is eligible for credential upgrade")
	account.calls.clear()
	account.replies = [{"ok": true, "data": {"Username": TEST_USERNAME}}, proof(PLAYER_ID, TEST_USERNAME), permissions(JSON.stringify([DEV_ID]))]
	await account.register(TEST_USERNAME, TEST_EMAIL, TEST_PASSWORD)
	check(account.is_signed_in() and account.has_credentials and account.account_id == PLAYER_ID and not account.is_developer(), "anonymous account upgrade preserves public provider ID and normal role")
	check(account.calls[0].api == "AddUsernamePassword" and account.calls[0].ticket == TEST_TICKET and account.calls[0].payload == {"Username": TEST_USERNAME, "Email": TEST_EMAIL, "Password": TEST_PASSWORD}, "account upgrade uses existing authenticated ticket and sends no new title or claimed ID")
	check(account.calls[1].api == "GetAccountInfo" and account.calls[1].payload.is_empty() and account.calls[1].ticket == TEST_TICKET, "upgrade rechecks owner of unchanged session ticket")
	account.replies = login_replies(PLAYER_ID, JSON.stringify([DEV_ID]))
	await account.login_device()
	account.replies = [{"ok": false}]
	await account.register(TEST_USERNAME, TEST_EMAIL, TEST_PASSWORD)
	check(account.is_signed_in() and account.account_id == PLAYER_ID and not account.has_credentials and not account.busy, "failed credential upgrade preserves original anonymous account")
	account.replies = [{"ok": true, "data": {"Username": TEST_USERNAME}}, proof(PLAYER_ID)]
	await account.register(TEST_USERNAME, TEST_EMAIL, TEST_PASSWORD)
	check(not account.is_signed_in() and not account.has_credentials and not account.is_developer(), "upgrade response alone cannot prove credentials without authenticated account username")
	account.replies = login_replies(DEV_ID, JSON.stringify([DEV_ID]))
	await account.login_device()
	account.replies = [{"ok": true, "data": {"Username": TEST_USERNAME}}, proof(DEV_ID, TEST_USERNAME), permissions(JSON.stringify([DEV_ID]))]
	await account.register(TEST_USERNAME, TEST_EMAIL, TEST_PASSWORD)
	check(account.account_id == DEV_ID and account.has_credentials and account.is_developer(), "verified developer upgrade preserves identity and reloads server-owned role")
	account.sign_out()
	account.queue_free()
	await process_frame

func test_credential_generation_guards() -> void:
	for api in ["RegisterPlayFabUser", "GetAccountInfo", "GetTitleData"]:
		var account := fresh_account()
		account.replies = credential_replies(DEV_ID, TEST_USERNAME, JSON.stringify([DEV_ID]))
		account.suspend_api = api
		account.register(TEST_USERNAME, TEST_EMAIL, TEST_PASSWORD)
		await wait_blocked(account)
		account.sign_out()
		account.release_reply.emit()
		await settle()
		check(not account.is_signed_in() and not account.has_credentials and not account.is_developer() and not account.busy, "logout prevents stale signup " + api + " reply from restoring access")
		account.queue_free()
		await process_frame
	for api in ["AddUsernamePassword", "GetAccountInfo", "GetTitleData"]:
		var account := fresh_account()
		account.replies = login_replies(DEV_ID, JSON.stringify([DEV_ID]))
		await account.login_device()
		account.replies = [{"ok": true, "data": {"Username": TEST_USERNAME}}, proof(DEV_ID, TEST_USERNAME), permissions(JSON.stringify([DEV_ID]))]
		account.suspend_api = api
		account.register(TEST_USERNAME, TEST_EMAIL, TEST_PASSWORD)
		await wait_blocked(account)
		account.sign_out()
		account.release_reply.emit()
		await settle()
		check(not account.is_signed_in() and not account.has_credentials and not account.is_developer() and not account.busy, "logout prevents stale upgrade " + api + " reply from restoring access")
		account.queue_free()
		await process_frame
	for api in ["LoginWithPlayFab", "GetAccountInfo", "GetTitleData"]:
		var account := fresh_account()
		account.replies = credential_replies(DEV_ID, TEST_USERNAME, JSON.stringify([DEV_ID]))
		account.suspend_api = api
		account.login_credentials(TEST_USERNAME, TEST_PASSWORD)
		await wait_blocked(account)
		account.sign_out()
		account.release_reply.emit()
		await settle()
		check(not account.is_signed_in() and not account.has_credentials and not account.is_developer() and not account.busy, "logout prevents stale credential " + api + " reply from restoring access")
		account.queue_free()
		await process_frame
	var account := fresh_account()
	account.replies = [{"ok": true, "data": {"Username": TEST_USERNAME}}, proof(DEV_ID, TEST_USERNAME), permissions(JSON.stringify([DEV_ID]))]
	# Upgrade callbacks from a former developer must not affect a newer login.
	account.replies = login_replies(DEV_ID, JSON.stringify([DEV_ID]))
	await account.login_device()
	account.replies = [{"ok": true, "data": {"Username": TEST_USERNAME}}, proof(DEV_ID, TEST_USERNAME), permissions(JSON.stringify([DEV_ID]))]
	account.suspend_api = "GetTitleData"
	account.register(TEST_USERNAME, TEST_EMAIL, TEST_PASSWORD)
	await wait_blocked(account)
	account.sign_out()
	account.replies = credential_replies(PLAYER_ID, TEST_USERNAME, JSON.stringify([DEV_ID]))
	await account.login_credentials(TEST_EMAIL, TEST_PASSWORD)
	account.release_reply.emit()
	await settle()
	check(account.account_id == PLAYER_ID and account.has_credentials and not account.is_developer(), "stale upgraded developer role cannot overwrite newer normal credential login")
	account.queue_free()
	await process_frame

func test_identity_and_role_proof() -> void:
	var account := fresh_account()
	account.title_id = ""
	await account.login_device()
	check(not account.is_signed_in() and not account.is_developer() and account.calls.is_empty(), "unconfigured account sign-in fails closed without contacting provider")
	account.account_id = DEV_ID
	check(not account.is_signed_in() and not account.is_developer(), "typing a public developer ID does not establish account or developer access")
	account.title_id = "1A7D9B"
	account.replies = [{"ok": false}]
	await account.login_device()
	check(not account.busy and not account.is_signed_in() and not account.is_developer(), "network failure leaves no signed-in identity or access")
	account.replies = [{"ok": true, "data": {"PlayFabId": DEV_ID}}]
	await account.login_device()
	check(not account.is_signed_in() and not account.is_developer(), "missing provider session ticket cannot grant access")
	account.calls.clear()
	account.replies = [{"ok": true, "data": {"PlayFabId": DEV_ID, "SessionTicket": TEST_TICKET}}, proof(PLAYER_ID), permissions(JSON.stringify([DEV_ID]))]
	await account.login_device()
	check(not account.is_signed_in() and not account.is_developer() and account.calls.size() == 2, "ticket owner mismatch rejects login before reading developer role")
	account.replies = login_replies(PLAYER_ID, JSON.stringify([DEV_ID]))
	await account.login_device()
	check(account.is_signed_in() and account.account_id == PLAYER_ID and not account.is_developer(), "verified normal player account remains outside developer allowlist")
	for raw in ["", "{}", JSON.stringify(DEV_ID), JSON.stringify([DEV_ID, 42]), [DEV_ID]]:
		account.replies = login_replies(DEV_ID, raw)
		await account.login_device()
		check(account.is_signed_in() and not account.is_developer(), "missing or malformed provider role list grants nobody access")
	account.calls.clear()
	account.replies = login_replies(DEV_ID, JSON.stringify([DEV_ID]))
	await account.login_device()
	check(account.is_signed_in() and account.is_developer() and account.account_id == DEV_ID, "provider-verified account in server-owned allowlist obtains leased access")
	check(account.calls.size() == 3 and account.calls[0].api == "LoginWithCustomID" and account.calls[1].api == "GetAccountInfo" and account.calls[2].api == "GetTitleData", "automatic device login verifies ticket ownership before loading role")
	check(account.calls[0].payload == {"TitleId": "1A7D9B", "CustomId": TEST_IDENTITY, "CreateAccount": true}, "device login sends a private generated credential rather than a claimed public account ID")
	check(account.calls[1].payload.is_empty() and account.calls[1].ticket == TEST_TICKET, "account proof requests authenticated ticket owner with no lookup identifier")
	check(account.calls[2].payload == {"Keys": ["PrimalMonkeDeveloperIds"]} and account.calls[2].ticket == TEST_TICKET, "role check reads only intended title-owned data key")
	check(not account.status.contains(TEST_TICKET) and not account.status.contains(TEST_IDENTITY), "account status exposes neither ticket nor device credential")
	account._access_until_ms = Time.get_ticks_msec() - 1
	check(not account.is_developer(), "expired role lease is rejected immediately without waiting for process callback")
	account.replies = [proof(DEV_ID), permissions(JSON.stringify([DEV_ID]))]
	await account.refresh_permissions()
	check(account.is_developer(), "explicit refresh can renew independently verified developer access")
	account.replies = [proof(DEV_ID), permissions("[]")]
	await account.refresh_permissions()
	check(account.is_signed_in() and not account.is_developer(), "provider allowlist revocation clears existing developer access")
	account.replies = [proof(DEV_ID), permissions(JSON.stringify([DEV_ID]))]
	await account.refresh_permissions()
	account.replies = [proof(DEV_ID), {"ok": false}]
	await account.refresh_permissions()
	check(account.is_signed_in() and not account.is_developer(), "failed role refresh preserves normal account while locking tools")
	account.replies = [proof(PLAYER_ID)]
	await account.refresh_permissions()
	check(not account.is_signed_in() and not account.is_developer(), "changed ticket owner on refresh invalidates account and role")
	account.sign_out()
	check(account.account_id.is_empty() and account._ticket.is_empty() and not account.busy and not account.is_developer(), "sign-out clears account, session ticket and privileged lease")
	account.queue_free()
	await process_frame

func test_async_generation_guards() -> void:
	for api in ["LoginWithCustomID", "GetAccountInfo", "GetTitleData"]:
		var account := fresh_account()
		account.replies = login_replies(DEV_ID, JSON.stringify([DEV_ID]))
		account.suspend_api = api
		account.login_device()
		await wait_blocked(account)
		account.sign_out()
		account.release_reply.emit()
		await settle()
		check(account.account_id.is_empty() and account._ticket.is_empty() and not account.busy and not account.is_developer(), "logout prevents stale " + api + " response from restoring identity or privilege")
		account.queue_free()
		await process_frame
	var account := fresh_account()
	account.replies = login_replies(DEV_ID, JSON.stringify([DEV_ID]))
	account.suspend_api = "GetTitleData"
	account.login_device()
	await wait_blocked(account)
	account.sign_out()
	account.replies = login_replies(PLAYER_ID, JSON.stringify([DEV_ID]))
	await account.login_device()
	check(account.account_id == PLAYER_ID and account.is_signed_in() and not account.is_developer(), "new login completes while former account role request is suspended")
	account.release_reply.emit()
	await settle()
	check(account.account_id == PLAYER_ID and account.is_signed_in() and not account.is_developer(), "stale developer response cannot overwrite newer normal-player login")
	account.replies = login_replies(DEV_ID, JSON.stringify([DEV_ID]))
	await account.login_device()
	account.replies = [proof(DEV_ID), permissions(JSON.stringify([DEV_ID]))]
	account.suspend_api = "GetTitleData"
	account.refresh_permissions()
	await wait_blocked(account)
	account.sign_out()
	account.release_reply.emit()
	await settle()
	check(not account.is_signed_in() and not account.is_developer(), "logout during role renewal cannot revive prior developer lease")
	account.queue_free()
	await process_frame

func test_game_handlers() -> void:
	var game = load("res://forest.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	await physics_frame
	check(game.has_method("developer_action") and game.has_method("developer_action_allowed"), "game exposes protected developer action guard")
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot in game.bots: bot.set_physics_process(false)
	if game.requested_play_mode == "pcvr":
		check(not game.player.xr_running and not game.get_viewport().use_xr and game.play_mode_notice.contains("PC VR unavailable"), "explicit PC VR failure reports unavailable mode and uses desktop fallback")
	check(not game.can_switch_play_mode("pcvr"), "headless process cannot spawn an interactive VR restart")
	check(not game.account.is_signed_in() and not is_instance_valid(game.dev_menu), "public game starts with no verified developer identity or loaded developer menu")
	var original_account: Node = game.account
	original_account.state_changed.disconnect(game._account_changed)
	original_account.queue_free()
	var account := fresh_account()
	game.account = account
	account.state_changed.connect(game._account_changed)
	var world_actions := ["restart", "add_time", "freeze_bots", "tag_all"]
	var all_actions := world_actions + ["respawn", "diagnostics", "unknown_action"]
	game.remaining = 47.0
	game.player.global_position = Vector3(4, 0.1, 4)
	for action in all_actions:
		check(not game.developer_action_allowed(action), "unsigned public account cannot request " + action)
		game.developer_action(action)
	check(game.score == 0 and game.remaining == 47 and not game.developer_bots_frozen and not game.diagnostics_enabled and game.player.global_position == Vector3(4, 0.1, 4), "direct unsigned action calls leave player and authoritative game state unchanged")
	account.replies = login_replies(PLAYER_ID, JSON.stringify([DEV_ID]))
	await account.login_device()
	check(account.is_signed_in() and not account.is_developer() and not is_instance_valid(game.dev_menu), "normal verified account receives no developer menu")
	for action in all_actions: game.developer_action(action)
	check(game.score == 0 and game.remaining == 47 and not game.developer_bots_frozen and not game.diagnostics_enabled and game.player.global_position == Vector3(4, 0.1, 4), "direct normal-account calls cannot bypass menu access controls")
	account.replies = login_replies(DEV_ID, JSON.stringify([DEV_ID]))
	await account.login_device()
	check(account.is_developer() and is_instance_valid(game.dev_menu), "verified developer account dynamically loads private tools menu")
	check(not game.developer_action_allowed("unknown_action"), "verified developer cannot dispatch undefined actions")
	for action in world_actions: check(game.developer_action_allowed(action), "verified offline developer may request " + action)
	game.developer_action("add_time")
	check(game.remaining == 77, "offline developer add-time action updates round")
	game.remaining = 290
	game.developer_action("add_time")
	check(game.remaining == 300, "developer add-time action respects maximum round duration")
	game.developer_action("freeze_bots")
	game.developer_action("diagnostics")
	game.developer_action("respawn")
	check(game.developer_bots_frozen and game.diagnostics_enabled and game.player.global_position == Vector3(0, 0.1, -5), "verified local developer controls operate through guarded handler")
	game.developer_action("tag_all")
	check(game.score == 5 and game.finished and game.bots.all(func(bot): return bot.tagged), "offline developer tag-all completes shared round exactly once")
	game.developer_action("restart")
	check(game.score == 0 and game.remaining == 90 and not game.finished and not game.developer_bots_frozen, "offline developer restart resets shared game state")
	game.session.mode = "hosting"
	game.developer_action("add_time")
	game.developer_action("freeze_bots")
	game.developer_action("tag_all")
	check(game.remaining == 120 and game.developer_bots_frozen and game.score == 5 and game.finished, "verified session host may modify authoritative round")
	game.developer_action("restart")
	check(game.score == 0 and game.remaining == 90 and not game.finished, "verified session host restart uses authoritative generation path")
	game.session.mode = "connected"
	game.remaining = 42
	game.player.global_position = Vector3(5, 0.1, 5)
	for action in world_actions:
		check(not game.developer_action_allowed(action), "verified client lacks host authority for " + action)
		game.developer_action(action)
	check(game.score == 0 and game.remaining == 42 and not game.finished and not game.developer_bots_frozen, "verified developer client cannot directly change shared round state")
	check(game.developer_action_allowed("respawn") and game.developer_action_allowed("diagnostics"), "developer clients retain local-only respawn and diagnostics")
	var prior_diagnostics: bool = game.diagnostics_enabled
	game.developer_action("respawn")
	game.developer_action("diagnostics")
	check(game.player.global_position == Vector3(0, 0.1, -5) and game.diagnostics_enabled != prior_diagnostics and game.remaining == 42, "client developer local controls do not change authoritative round")
	game.session.mode = "offline"
	game.developer_action("freeze_bots")
	game.diagnostics_enabled = true
	account._access_until_ms = Time.get_ticks_msec() - 1
	game.developer_action("tag_all")
	check(game.score == 0 and not game.developer_action_allowed("add_time"), "expired developer lease blocks direct actions even before menu closes")
	account._process(0)
	check(not is_instance_valid(game.dev_menu) and not game.developer_bots_frozen and not game.diagnostics_enabled, "expired access removes private menu and clears ongoing developer toggles")
	account.replies = [proof(DEV_ID), permissions(JSON.stringify([DEV_ID]))]
	await account.refresh_permissions()
	game.developer_action("freeze_bots")
	game.diagnostics_enabled = true
	account.sign_out()
	check(not is_instance_valid(game.dev_menu) and not game.developer_bots_frozen and not game.diagnostics_enabled and not game.developer_action_allowed("tag_all"), "sign-out closes private tools and revokes previously enabled actions")
	account.queue_free()
	game.queue_free()
	await process_frame

func test_play_mode_selection() -> void:
	check(ModeScript.requested(PackedStringArray(["--play-mode=desktop"]), false) == "desktop", "desktop launcher selects keyboard/mouse mode explicitly")
	check(ModeScript.requested(PackedStringArray(["--play-mode=pcvr"]), false) == "pcvr", "PC VR launcher selects headset mode explicitly")
	check(ModeScript.requested(PackedStringArray(), false) == "auto", "unselected PC launch retains automatic mode")
	check(ModeScript.requested(PackedStringArray(["--play-mode=desktop"]), true) == "quest", "standalone Quest mode cannot be disabled by PC desktop selection")
	check(ModeScript.launch_arguments("desktop") == PackedStringArray(["--xr-mode", "off", "--", "--play-mode=desktop"]), "desktop restart suppresses engine XR before passing user mode")
	check(ModeScript.launch_arguments("pcvr") == PackedStringArray(["--xr-mode", "on", "--", "--play-mode=pcvr"]), "PC VR restart forces engine XR before passing user mode")
	check(ModeScript.launch_arguments("pcvr", "/tmp/Project With Spaces") == PackedStringArray(["--path", "/tmp/Project With Spaces", "--xr-mode", "on", "--", "--play-mode=pcvr"]), "editor restart preserves project path as one unshelled argument")
