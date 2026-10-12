extends SceneTree

# Exercise the real forest, verified-account flow and desktop/VR menu controls.
# Provider requests are mocked; local profile writes use unique scratch files.
const DEV_ID := "481C2D175D5672D9"
const PLAYER_ID := "1122334455667788"
const TEST_TICKET := "test-only-session-ticket"
var checks := 0
var failures := 0
var scratch_prefix := ""

class MockAccount:
	extends "res://scripts/playfab_account.gd"
	var provider_id := PLAYER_ID
	var title_data := {"PrimalMonkeDeveloperIds": JSON.stringify([DEV_ID])}
	var calls: Array[Dictionary] = []
	func _device_identity() -> String:
		return "PM-" + "1234567890abcdef".repeat(4)
	func _request(api: String, payload: Dictionary, ticket := "") -> Dictionary:
		calls.append({"api": api, "payload": payload.duplicate(true), "ticket": ticket})
		await get_tree().process_frame
		match api:
			"LoginWithCustomID":
				return {"ok": true, "data": {"PlayFabId": provider_id, "SessionTicket": TEST_TICKET}}
			"GetAccountInfo":
				return {"ok": true, "data": {"AccountInfo": {"PlayFabId": provider_id}}}
			"GetTitleData":
				return {"ok": true, "data": {"Data": title_data.duplicate(true)}}
			"GetUserData":
				return {"ok": true, "data": {"Data": {}}}
			"UpdateUserData":
				return {"ok": true, "data": {"DataVersion": 1}}
		return {"ok": false}

class ScratchProfile:
	extends "res://scripts/profile_state.gd"
	var storage_prefix := ""
	func _storage_path(identity: String) -> String:
		return storage_prefix + "_" + ("guest" if identity.is_empty() else identity.sha256_text().left(16)) + ".json"

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func settle(frames := 4) -> void:
	for index in range(frames): await process_frame

func replace_isolated_state(game: Node3D) -> MockAccount:
	var old_account: Node = game.account
	var old_profile: Node = game.profile
	old_account.state_changed.disconnect(game._account_changed)
	old_profile.public_profile_changed.disconnect(game._profile_changed)
	# This flow uses device login, so no registration preferences are written.
	game.onboarding.queue_free()
	game.onboarding = null
	var account := MockAccount.new()
	game.account = account
	game.add_child(account)
	account.state_changed.connect(game._account_changed)
	account.set_process(false)
	var profile := ScratchProfile.new()
	profile.storage_prefix = scratch_prefix
	profile.game = game
	game.profile = profile
	game.add_child(profile)
	profile.public_profile_changed.connect(game._profile_changed)
	profile.account_changed()
	old_account.queue_free()
	old_profile.queue_free()
	return account

func developer_world_index(menu: Node) -> int:
	for index in range(menu._world_buttons.size()):
		if menu._world_buttons[index].action == "developer": return index
	return -1

func developer_world_hit(menu: Node) -> Dictionary:
	var index := developer_world_index(menu)
	if index < 0: return {}
	menu._place_world_panel()
	var center: Vector2 = menu._world_buttons[index].rect.get_center()
	var target: Vector3 = menu._world_panel.to_global(Vector3(center.x, center.y, 0))
	var normal: Vector3 = menu._world_panel.global_basis.z
	return menu._intersect_panel(target + normal, -normal)

func check_button_access(game: Node3D, expected: bool, context: String) -> void:
	for menu in [game.main_menu, game.account_menu]:
		menu.refresh_status()
		var label := "%s %s" % [context, menu.name]
		check(menu._desktop_buttons.has("developer"), label + " has a desktop Dev tools control")
		if menu._desktop_buttons.has("developer"):
			var button: Button = menu._desktop_buttons.developer
			check(button.visible == expected and button.disabled != expected, label + " desktop access follows the verified developer role")
		var index := developer_world_index(menu)
		check(index >= 0, label + " has a VR Dev tools control")
		if index >= 0:
			var button: Dictionary = menu._world_buttons[index]
			var mesh: MeshInstance3D = button.get("mesh")
			var text: Label3D = button.label
			check(mesh != null and mesh.visible == expected and text.visible == expected, label + " VR mesh and label follow the verified developer role")
			var hit := developer_world_hit(menu)
			check((hit.get("button", -1) == index) == expected, label + " controller ray selects Dev tools only when its control is visible")
		check(menu._action_enabled("developer") == expected, label + " action independently enforces verified developer access")

func check_exclusive_developer(game: Node3D, label: String) -> void:
	var exclusive: bool = is_instance_valid(game.dev_menu) and game.dev_menu.is_open
	for menu in [game.main_menu, game.lobby, game.account_menu, game.profile_menu, game.voice_menu, game.tutorial]:
		exclusive = exclusive and not menu.is_open
	check(exclusive and not game.player.input_allowed, label + " opens only developer tools and pauses player input")

func check_vr_layout(menu: Node) -> void:
	var bounds := Rect2(-menu.panel_size * 0.5, menu.panel_size)
	var inside := true
	var separate := true
	for index in range(menu._world_buttons.size()):
		var button: Dictionary = menu._world_buttons[index]
		if not button.mesh.visible: continue
		inside = inside and bounds.encloses(button.rect)
		for other in range(index):
			var previous: Dictionary = menu._world_buttons[other]
			if previous.mesh.visible: separate = separate and not button.rect.intersects(previous.rect)
	check(inside and separate, menu.name + " visible VR controls fit the panel without overlapping after developer access")

func run() -> void:
	scratch_prefix = "/tmp/primal-monke-developer-buttons-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var game = load("res://forest.tscn").instantiate()
	root.add_child(game)
	await settle()
	var account := replace_isolated_state(game)
	await settle()
	check(game.frontend_state == "main_menu" and game.main_menu.is_open, "real forest begins at its main menu")
	check(account.title_id == "1A7D9B", "developer-button account fixture uses the configured production title")
	check_button_access(game, false, "Signed out")
	game.open_developer_menu()
	game.main_menu._desktop_buttons.developer.pressed.emit()
	game.account_menu._dispatch("developer")
	check(not game.can_open_developer_menu() and not is_instance_valid(game.dev_menu) and game.main_menu.is_open, "direct calls and desktop signals cannot open tools while signed out")

	await account.login_device()
	check(account.is_signed_in() and account.account_id == PLAYER_ID and not account.is_developer(), "verified ordinary player remains outside the server-owned developer list")
	check_button_access(game, false, "Ordinary player")
	game.open_account_menu()
	game.account_menu._desktop_buttons.developer.pressed.emit()
	check(game.account_menu.is_open and not is_instance_valid(game.dev_menu), "ordinary-player Account button cannot replace the account overlay with private tools")
	game.account_menu.set_open(false)

	account.provider_id = DEV_ID
	account.title_data = {"PMDID": JSON.stringify([DEV_ID])}
	await account.login_device()
	await settle()
	check(account.account_id == DEV_ID and account.is_developer() and is_instance_valid(game.dev_menu), "verified selected account under PMDID opens the private developer menu")
	check_button_access(game, true, "Verified PMDID developer")
	game.main_menu._desktop_buttons.developer.pressed.emit()
	check_exclusive_developer(game, "Legacy PMDID Main button")
	account.title_data = {"PrimalMonkeDeveloperIds": "[]", "PMDID": JSON.stringify([DEV_ID])}
	await account.refresh_permissions()
	await settle()
	check(not account.is_developer() and not is_instance_valid(game.dev_menu), "canonical revocation closes a legacy-opened developer menu despite stale PMDID")
	check_button_access(game, false, "Canonical revocation over legacy list")
	account.title_data = {"PrimalMonkeDeveloperIds": JSON.stringify([DEV_ID])}
	await account.refresh_permissions()
	await settle()
	check(account.is_developer() and is_instance_valid(game.dev_menu), "authenticated exact developer ID unlocks tools after verified Title Data refresh")
	var requested_role := false
	for call in account.calls:
		if call.api == "GetTitleData":
			requested_role = requested_role or (call.payload == {"Keys": ["PrimalMonkeDeveloperIds", "PMDID"]} and call.ticket == TEST_TICKET)
	check(requested_role, "developer-button access comes from the existing authenticated developer-list request")
	check_button_access(game, true, "Verified developer")
	game.main_menu._desktop_buttons.developer.pressed.emit()
	check_exclusive_developer(game, "Main menu desktop button")
	game.dev_menu._dispatch("close")
	check(game.frontend_state == "main_menu" and game.main_menu.is_open and not game.dev_menu.is_open, "closing tools opened from Main restores the main screen")
	game.open_profile_menu()
	game.open_account_menu()
	game.account_menu._desktop_buttons.developer.pressed.emit()
	check_exclusive_developer(game, "Account desktop button")
	game.dev_menu._dispatch("close")
	check(game.main_menu.is_open and not game.account_menu.is_open and not game.profile_menu.is_open, "closing tools opened from Account restores the underlying main frontend")
	game.open_multiplayer_lobby()
	game.open_account_menu()
	game.account_menu._desktop_buttons.developer.pressed.emit()
	check_exclusive_developer(game, "Lobby Account desktop button")
	game.dev_menu._dispatch("close")
	check(game.frontend_state == "lobby" and game.lobby.is_open and not game.account_menu.is_open, "closing tools opened through lobby Account restores the staging lobby")
	game.return_to_main_menu()

	game.player.xr_running = true
	await settle()
	for menu in [game.main_menu, game.account_menu]:
		check_vr_layout(menu)
		if menu == game.account_menu: game.open_account_menu()
		var hit := developer_world_hit(menu)
		var index: int = hit.get("button", -1)
		check(index == developer_world_index(menu), menu.name + " simulated front-facing controller ray hits its developer button")
		if index >= 0: menu._dispatch(menu._world_buttons[index].action)
		check_exclusive_developer(game, menu.name + " VR developer button")
		check(game.dev_menu._world_panel.visible and not game.dev_menu._canvas.visible, menu.name + " VR route displays the world developer panel")
		game.dev_menu._dispatch("close")
	game.player.xr_running = false
	await settle()
	check(game.dev_menu.toggle_key == KEY_F2 and game.dev_menu.toggle_hand == 0 and game.dev_menu.toggle_button == "by_button", "developer F2 and left-Y shortcuts remain available alongside the new buttons")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F2
	key.pressed = true
	game.dev_menu._input(key)
	check_exclusive_developer(game, "Existing F2 shortcut")
	game.dev_menu._input(key)
	check(game.main_menu.is_open and not game.dev_menu.is_open, "F2 still closes developer tools and restores Main")

	game._set_frontend_state("loading")
	for menu in [game.main_menu, game.account_menu]:
		menu.refresh_status()
		check(not menu._action_enabled("developer") and menu._desktop_buttons.developer.disabled, menu.name + " developer button is blocked while loading")
		menu._desktop_buttons.developer.pressed.emit()
		menu._dispatch("developer")
	game.open_developer_menu()
	game.dev_menu.set_open(true)
	check(not game.can_open_developer_menu() and not game.dev_menu.is_open and game.frontend_state == "loading", "loading blocks root calls, menu dispatch, signals and direct private-panel opening")
	game._set_frontend_state("main_menu")
	game.open_developer_menu()
	game.developer_action("diagnostics")
	account.title_data = {"PrimalMonkeDeveloperIds": "[]"}
	await account.refresh_permissions()
	await settle()
	check(not is_instance_valid(game.dev_menu) and game.main_menu.is_open and not game.diagnostics_enabled, "server-side role revocation closes tools, restores Main and clears active developer toggles")
	check_button_access(game, false, "Revoked developer")

	account.title_data = {"PrimalMonkeDeveloperIds": JSON.stringify([DEV_ID])}
	await account.refresh_permissions()
	game.open_developer_menu()
	account._access_until_ms = Time.get_ticks_msec() - 1
	check(not game.can_open_developer_menu(), "expired lease rejects direct opening before background account cleanup")
	check_button_access(game, false, "Expired developer lease")
	account._process(0)
	await settle()
	check(not is_instance_valid(game.dev_menu) and game.main_menu.is_open, "lease expiration removes the open tools panel and restores Main")
	await account.refresh_permissions()
	game.open_developer_menu()
	account.sign_out()
	await settle()
	check(not is_instance_valid(game.dev_menu) and game.main_menu.is_open and not game.can_open_developer_menu(), "sign-out removes private tools and restores the frontend")
	check_button_access(game, false, "Signed out after developer access")

	game.voice.shutdown()
	game.queue_free()
	await settle()
	for name in DirAccess.get_files_at("/tmp"):
		if name.begins_with(scratch_prefix.get_file()): DirAccess.remove_absolute("/tmp/" + name)
	print("Developer button checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)
