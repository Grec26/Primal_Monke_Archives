extends SceneTree

const ProfileScript = preload("res://scripts/profile_state.gd")
const ProfileMenuScript = preload("res://scripts/profile_menu.gd")
const TEST_FOLDER := "/tmp/primal-monke-profile-tests"
var checks := 0
var failures := 0

class MockAccount:
	extends Node
	var account_id := ""
	var username := ""
	var busy := false
	var replies: Array[Dictionary] = []
	var calls: Array[Dictionary] = []
	var block_api := ""
	var blocked := false
	signal released
	func is_signed_in() -> bool:
		return not account_id.is_empty()
	func client_request(api: String, payload: Dictionary) -> Dictionary:
		calls.append({"api": api, "payload": payload.duplicate(true), "owner": account_id})
		var reply: Dictionary = replies.pop_front() if not replies.is_empty() else {"ok": true, "data": {}}
		if api == block_api:
			block_api = ""
			blocked = true
			await released
			blocked = false
		else:
			await get_tree().process_frame
		return reply

class MockGame:
	extends Node3D
	var account: MockAccount
	var profile: Node
	var player: Node3D
	var frontend_state := "main_menu"
	var opened := 0
	var closed := 0
	func on_feature_menu_open(_menu: Node) -> void:
		opened += 1
	func close_feature_menu(_menu: Node) -> void:
		closed += 1

class TestProfile:
	extends "res://scripts/profile_state.gd"
	var test_clock := 0
	func _now_ms() -> int:
		return test_clock
	func _storage_path(identity: String) -> String:
		return "/tmp/primal-monke-profile-tests/" + ("guest" if identity.is_empty() else identity.sha256_text()) + ".json"

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func frames(count := 3) -> void:
	for index in range(count):
		await process_frame

func png(size := 64) -> PackedByteArray:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color("b2e678"))
	return image.save_png_to_buffer()

func record(name: String, xp: int, picture := PackedByteArray()) -> Dictionary:
	return {"ok": true, "data": {"Data": {ProfileScript.CLOUD_KEY: {"Value": JSON.stringify({"version": 1, "name": name, "xp": xp, "avatar": "" if picture.is_empty() else Marshalls.raw_to_base64(picture)})}}}}

func run() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_FOLDER)
	for file in DirAccess.get_files_at(TEST_FOLDER):
		DirAccess.remove_absolute(TEST_FOLDER.path_join(file))
	var game := MockGame.new()
	game.account = MockAccount.new()
	game.profile = TestProfile.new()
	game.profile.game = game
	root.add_child(game)
	game.add_child(game.account)
	game.add_child(game.profile)
	game.profile.set_process(false)
	var profile: TestProfile = game.profile
	await profile.account_changed()
	check(profile.level == 1 and profile.xp == 0 and profile.display_name == "Monke", "fresh guests start at cosmetic level one")
	await test_public_bounds()
	await test_rewards(profile)
	await test_pictures(profile)
	await test_account_storage(game, profile)
	await test_cloud_races(game, profile)
	await test_cloud_read_retry(game, profile)
	await test_unsynced_cosmetic_restart(game, profile)
	await test_menu(game, profile)
	game.queue_free()
	await process_frame
	for file in DirAccess.get_files_at(TEST_FOLDER):
		DirAccess.remove_absolute(TEST_FOLDER.path_join(file))
	print("Profile checks complete; %d checks, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_public_bounds() -> void:
	check(ProfileScript.level_from_xp(0) == 1 and ProfileScript.level_from_xp(99) == 1 and ProfileScript.level_from_xp(100) == 2 and ProfileScript.level_from_xp(900) == 4, "quadratic XP thresholds have consistent boundary levels")
	check(ProfileScript.level_from_xp(-100) == 1 and ProfileScript.level_from_xp(999999999) == ProfileScript.MAX_LEVEL, "negative and excessive XP keep level bounded")
	var safe: Dictionary = ProfileScript.sanitize_public_profile({"name": "  A\nB\tC\u202eD  ", "xp": 900, "level": 9999999, "developer": true, "account_id": "someone_else", "avatar": png()})
	check(safe.name == "ABCD" and safe.level == 4 and safe.xp == 900, "public names remove controls and levels derive from bounded XP")
	check(safe.size() == 4 and not safe.has("developer") and not safe.has("account_id"), "public profiles cannot carry account identity or developer claims")
	check(ProfileScript.validate_avatar(safe.avatar), "small valid PNG pictures survive public sanitization")
	check(ProfileScript.sanitize_public_profile({"xp": NAN, "name": 55, "avatar": "https://example.invalid/photo"}).xp == 0, "non-finite XP and wrong public value types are rejected")
	check(ProfileScript.sanitize_public_profile({"xp": INF}).xp == 0 and ProfileScript.sanitize_public_profile({"xp": -44}).xp == 0, "infinite and negative public XP cannot overflow progression")
	check(ProfileScript.sanitize_public_profile({"xp": 1000000000}).xp == ProfileScript.MAX_XP, "large integer public XP is capped")
	check(ProfileScript.clean_name("abcdefghijklmnopqrstuvw").length() == 20 and ProfileScript.clean_name("\n\t") == "Monke", "names are bounded with a nonempty fallback")
	check(not ProfileScript.validate_avatar(png(65)) and ProfileScript.sanitize_public_profile({"avatar": png(65)}).avatar.is_empty(), "oversized PNG dimensions are rejected before decode")
	var too_big := PackedByteArray()
	too_big.resize(ProfileScript.MAX_AVATAR_BYTES + 1)
	check(not ProfileScript.validate_avatar(too_big), "network picture payloads cannot exceed six thousand bytes")
	var forged := png()
	forged[16] = 127
	check(not ProfileScript.validate_avatar(forged), "forged huge PNG dimensions are rejected before allocation")

func test_rewards(profile: TestProfile) -> void:
	check(profile._quiet_json("{invalid provider payload") == null and profile._quiet_json("{\"version\":1}") is Dictionary, "quiet JSON decoding rejects malformed data without diagnostic logging")
	check(profile.award_xp(10, "round:1:tag:2") and profile.xp == 10, "accepted local gameplay rewards add cosmetic XP")
	check(not profile.award_xp(10, "round:1:tag:2") and profile.xp == 10, "repeated gameplay events cannot award XP twice")
	check(not profile.award_xp(-1, "bad") and not profile.award_xp(10, "") and not profile.award_xp(10, "a".repeat(121)), "invalid amounts and unbounded event keys are ignored")
	check(profile.award_xp(1000000000, "bounded") and profile.xp == 10010, "individual rewards cap at ten thousand XP")
	var summary := profile.progress_summary()
	check(summary.current >= 0 and summary.current <= summary.needed and summary.level == profile.level, "XP progress uses the current quadratic level interval")
	var saved_xp := profile.xp
	profile.xp = ProfileScript.MAX_XP
	var maximum := profile.progress_summary()
	check(maximum.level == ProfileScript.MAX_LEVEL and maximum.current == maximum.needed and maximum.max_level, "maximum XP fills the final level without exceeding its progress interval")
	profile.xp = saved_xp
	check(profile.set_display_name("  Test Monke  ") and profile.display_name == "Test Monke", "public name edits trim surrounding whitespace")
	check(not profile.set_display_name("AB") and profile.display_name == "Test Monke", "too-short names do not replace the saved profile")
	var saved := FileAccess.get_file_as_string(profile._storage_path(""))
	check(not saved.contains("SessionTicket") and not saved.contains("Password") and not saved.contains("CustomId"), "profile save contains no authentication credentials")
	var public := profile.public_profile()
	public.name = "Changed outside"
	check(profile.display_name == "Test Monke", "returned profile dictionaries do not let callers mutate state")

func test_pictures(profile: TestProfile) -> void:
	check(profile.import_avatar_bytes(png(128), "png") and ProfileScript.validate_avatar(profile.avatar), "local PNG imports become bounded shareable pictures")
	var dimensions := ProfileScript._png_dimensions(profile.avatar)
	check(dimensions == Vector2i(64, 64) and profile.avatar.size() <= ProfileScript.MAX_AVATAR_BYTES, "PNG imports are cropped and resized to a 64-pixel square")
	var image := Image.create(120, 80, false, Image.FORMAT_RGB8)
	image.fill(Color("ee8877"))
	check(profile.import_avatar_bytes(image.save_jpg_to_buffer(), "jpeg"), "local JPEG pictures pass the bounded header and decoder path")
	check(profile.import_avatar_bytes(png(), "") and profile.import_avatar_bytes(image.save_jpg_to_buffer(), ""), "extensionless native document pictures sniff bounded PNG and JPEG headers")
	check(not profile.import_avatar_bytes(PackedByteArray([255, 216, 255]), ""), "extensionless documents still require complete bounded image headers")
	check(ProfileScript.valid_picture_path("content://com.android.documents/document/42", true, true), "Android native-picker content documents are accepted as local picture paths")
	check(not ProfileScript.valid_picture_path("content://documents/42", true, false) and not ProfileScript.valid_picture_path("content://documents/42", false, true), "content documents require both Android and a native picker selection")
	check(not ProfileScript.valid_picture_path("https://example.invalid/picture", true, true) and not ProfileScript.valid_picture_path("file://picture.png", true, true), "HTTP and arbitrary URI schemes remain blocked even in a native picker flow")
	check(not ProfileScript.valid_picture_path("content://", true, true) and not ProfileScript.valid_picture_path("content://documents/\n42", true, true), "empty and control-character document URIs are rejected")
	# Godot's String.chr(0) replaces NUL with U+FFFD and emits a warning before
	# path validation. Use another numeric ASCII control to exercise this gate.
	check(not ProfileScript.valid_picture_path("content://documents/" + String.chr(1) + "42", true, true), "numeric ASCII control characters in picture paths are rejected without source literals")
	check(ProfileScript._png_dimensions(profile.avatar) == Vector2i(64, 64), "JPEG pictures publish as square PNG data")
	var before := profile.avatar.duplicate()
	check(not profile.import_avatar_bytes(PackedByteArray([0, 1, 2]), "png") and profile.avatar == before, "invalid picture files preserve the previous avatar")
	var forged := png()
	forged[16] = 127
	check(not profile.import_avatar_bytes(forged, "png"), "source images with malicious dimensions are rejected before decode")
	var oversized := PackedByteArray()
	oversized.resize(ProfileScript.MAX_FILE_BYTES + 1)
	check(not profile.import_avatar_bytes(oversized, "png"), "local files larger than four megabytes are rejected")
	check(not profile.import_avatar_file("https://example.invalid/picture.png") and not profile.import_avatar_bytes(png(), "svg"), "remote URLs and unsupported image formats are never imported")
	var path := TEST_FOLDER.path_join("local-picture.png")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(png())
	file.close()
	check(profile.import_avatar_file(path), "local file upload reads an allowed small PNG")
	profile.clear_avatar()
	check(profile.avatar.is_empty(), "resetting a picture restores the built-in Monke icon")

func test_account_storage(game: MockGame, profile: TestProfile) -> void:
	var guest_xp := profile.xp
	game.account.account_id = "PLAYER_A"
	game.account.replies = [record("Cloud A", 900, png())]
	await profile.account_changed()
	check(profile.display_name == "Cloud A" and profile.xp == 900 and profile.level == 4, "verified account loads its own cloud profile")
	check(profile._bound_id == "PLAYER_A" and not profile._storage_path("../another").contains("../"), "profile files are bound to a hashed verified account ID")
	check(profile.award_xp(20, "A:event") and profile.set_display_name("Saved A"), "account-local edits and gameplay update the bound profile")
	await profile.save_now()
	var call: Dictionary = game.account.calls.back()
	check(call.api == "UpdateUserData" and call.owner == "PLAYER_A" and call.payload.Permission == "Public", "authenticated saves target the current owner with public cosmetic data")
	var data: Dictionary = JSON.parse_string(call.payload.Data[ProfileScript.CLOUD_KEY])
	check(data.name == "Saved A" and data.xp == 920 and data.size() == 4 and str(call.payload).length() < 9000, "cloud save is bounded cosmetic JSON without tickets or roles")
	game.account.account_id = "PLAYER_B"
	game.account.replies = [{"ok": true, "data": {"Data": {}}}]
	await profile.account_changed()
	check(profile.display_name == "Monke" and profile.xp == 0 and profile.avatar.is_empty(), "a new account cannot inherit another player's profile")
	game.account.account_id = ""
	await profile.account_changed()
	check(profile.display_name == "Test Monke" and profile.xp == guest_xp, "logout restores separate guest data rather than the last signed-in account")
	game.account.account_id = "PLAYER_A"
	game.account.replies = [{"ok": false}]
	await profile.account_changed()
	check(profile.display_name == "Saved A" and profile.xp == 920, "offline cloud failure retains the current account's local profile")
	var before := game.account.calls.size()
	await profile.account_changed()
	check(game.account.calls.size() == before, "unrelated account status changes do not reload or overwrite profile data")
	game.account.account_id = "CORRUPT_ACCOUNT"
	game.account.username = "Quiet Monke"
	var corrupted := FileAccess.open(profile._storage_path("CORRUPT_ACCOUNT"), FileAccess.WRITE)
	corrupted.store_string("{malformed local payload")
	corrupted.close()
	game.account.replies = [{"ok": true, "data": {"Data": {ProfileScript.CLOUD_KEY: {"Value": "{malformed cloud payload"}}}}]
	await profile.account_changed()
	check(profile.display_name == "Quiet Monke" and profile.xp == 0 and profile.avatar.is_empty(), "malformed local and cloud JSON preserves the bound account's default profile quietly")
	game.account.username = ""

func test_cloud_races(game: MockGame, profile: TestProfile) -> void:
	game.account.account_id = "PLAYER_C"
	game.account.replies = [record("Late C", 7777)]
	game.account.block_api = "GetUserData"
	profile.account_changed()
	await frames(1)
	check(game.account.blocked, "cloud load can remain in flight for race testing")
	game.account.account_id = "PLAYER_D"
	game.account.replies = [record("Current D", 100)]
	await profile.account_changed()
	game.account.released.emit()
	await frames()
	check(profile.display_name == "Current D" and profile.xp == 100 and profile._bound_id == "PLAYER_D", "a stale account load cannot overwrite a newer account")
	profile.set_display_name("D saved")
	game.account.replies = [{"ok": true, "data": {}}]
	game.account.block_api = "UpdateUserData"
	profile.save_now()
	await frames(1)
	game.account.account_id = ""
	await profile.account_changed()
	game.account.released.emit()
	await frames()
	check(profile._bound_id.is_empty() and profile.display_name == "Test Monke" and not profile._saving, "a stale cloud save cannot change the guest profile after logout")
	game.account.account_id = "PLAYER_E"
	game.account.replies = [record("Cloud old", 9000, png())]
	game.account.block_api = "GetUserData"
	profile.account_changed()
	await frames(1)
	profile.set_display_name("Local new")
	profile.award_xp(10, "new-local-event")
	var calls_before_load := game.account.calls.size()
	profile.save_now()
	profile._process(0.0)
	await frames(1)
	check(game.account.calls.size() == calls_before_load and profile._cloud_loading and not profile._cloud_ready, "manual and automatic cloud saves cannot run before the initial read completes")
	game.account.released.emit()
	await frames()
	check(profile.display_name == "Local new" and profile.xp == 9010 and ProfileScript.validate_avatar(profile.avatar), "late cloud reads preserve edited names, load unedited pictures and retain cloud XP plus in-flight rewards")
	game.account.replies = [{"ok": true, "data": {}}]
	game.account.block_api = "UpdateUserData"
	profile.save_now()
	await frames(1)
	profile.award_xp(5, "during-save")
	game.account.released.emit()
	await frames()
	check(profile._dirty and profile.xp == 9015, "changes made during a cloud save remain dirty for a later sync")
	var before := game.account.calls.size()
	await profile.save_now()
	check(game.account.calls.size() == before and profile._dirty, "manual sync respects the ten-second cloud write throttle")
	profile.test_clock += ProfileScript.SAVE_INTERVAL_MS
	game.account.replies = [{"ok": false}]
	await profile.save_now()
	check(profile._dirty and profile.xp == 9015 and profile.status.contains("retry"), "failed cloud saves keep local progress and expose retry feedback")

func test_cloud_read_retry(game: MockGame, profile: TestProfile) -> void:
	game.account.account_id = "INITIAL_READ_FAILED"
	game.account.replies = [{"ok": false}]
	await profile.account_changed()
	var before := game.account.calls.size()
	await profile.save_now()
	check(not profile._dirty and not profile._cloud_ready and game.account.calls.size() == before and profile._cloud_retry_requested, "Retry sync queues a throttled failed initial read even without local edits")
	profile.award_xp(10, "reward-during-failed-read")
	profile.clear_avatar()
	profile.test_clock += ProfileScript.SAVE_INTERVAL_MS
	game.account.replies = [{"ok": false}]
	await profile.save_now()
	check(game.account.calls.back().api == "GetUserData" and profile.xp == 10 and not profile._cloud_ready, "repeated read failure cannot upload defaults over an unread cloud profile")
	profile.test_clock += ProfileScript.SAVE_INTERVAL_MS
	game.account.replies = [record("Recovered Monke", 900, png())]
	await profile.save_now()
	check(game.account.calls.back().api == "GetUserData" and profile._cloud_ready and profile.xp == 910 and profile.display_name == "Recovered Monke" and profile.avatar.is_empty(), "retry reads cloud data before writing and preserves unread rewards plus a locally reset picture")
	game.account.replies = [{"ok": true, "data": {}}]
	await profile.save_now()
	var saved: Dictionary = JSON.parse_string(game.account.calls.back().payload.Data[ProfileScript.CLOUD_KEY])
	check(game.account.calls.back().api == "UpdateUserData" and saved.xp == 910 and saved.avatar == "", "only a successful initial cloud read permits uploading the merged profile")
	game.account.account_id = "UNEDITED_FAILED_READ"
	game.account.replies = [{"ok": false}]
	await profile.account_changed()
	profile.test_clock += ProfileScript.SAVE_INTERVAL_MS
	game.account.replies = [record("Untouched Cloud", 900)]
	await profile.save_now()
	check(profile._cloud_ready and not profile._dirty and profile.xp == 900 and game.account.calls.back().api == "GetUserData", "Retry sync performs a real recovery read even when no profile edits are pending")
	var no_changes_calls := game.account.calls.size()
	await profile.save_now()
	check(game.account.calls.size() == no_changes_calls, "an unchanged recovered cloud profile never needs a default overwrite")
	game.account.account_id = "ONLY_REWARD_DURING_READ"
	game.account.replies = [record("Reward Cloud", 900, png())]
	game.account.block_api = "GetUserData"
	profile.account_changed()
	await frames(1)
	profile.award_xp(10, "only-xp")
	game.account.released.emit()
	await frames()
	check(profile.display_name == "Reward Cloud" and ProfileScript.validate_avatar(profile.avatar) and profile.xp == 910, "XP-only edits preserve cloud cosmetics and add rewards to existing cloud progression")
	game.account.account_id = "CACHED_HIGHER_PROGRESS"
	var cache := FileAccess.open(profile._storage_path("CACHED_HIGHER_PROGRESS"), FileAccess.WRITE)
	cache.store_string(JSON.stringify({"version": 1, "name": "Cached", "xp": 100, "avatar": ""}))
	cache.close()
	game.account.replies = [record("Cached Cloud", 80)]
	game.account.block_api = "GetUserData"
	profile.account_changed()
	await frames(1)
	profile.award_xp(10, "cached-reward")
	game.account.released.emit()
	await frames()
	check(profile.xp == 110 and profile._dirty, "higher cached XP is retained with rewards earned during the cloud read")

func test_unsynced_cosmetic_restart(game: MockGame, profile: TestProfile) -> void:
	game.account.account_id = "PENDING_RESTART"
	game.account.replies = [record("Old Cloud", 900, png())]
	await profile.account_changed()
	profile.set_display_name("Pending Local")
	profile.clear_avatar()
	game.account.replies = [{"ok": false}]
	await profile.save_now()
	var saved: Dictionary = profile._quiet_json(FileAccess.get_file_as_string(profile._storage_path("PENDING_RESTART")))
	check(saved._local_pending.name and saved._local_pending.avatar, "failed cloud saves persist local-only pending name and picture flags")
	var restored := TestProfile.new()
	restored.game = game
	game.add_child(restored)
	restored.set_process(false)
	game.account.replies = [record("Old Cloud", 900, png())]
	await restored.account_changed()
	check(restored.display_name == "Pending Local" and restored.avatar.is_empty() and restored._dirty, "a restarted client retains unsynced name and picture changes over older cloud cosmetics")
	game.account.replies = [{"ok": true, "data": {}}]
	await restored.save_now()
	var public_save: Dictionary = restored._quiet_json(game.account.calls.back().payload.Data[ProfileScript.CLOUD_KEY])
	check(public_save.size() == 4 and not public_save.has("_local_pending") and public_save.name == "Pending Local", "pending sync flags never enter public cloud data")
	var synced: Dictionary = restored._quiet_json(FileAccess.get_file_as_string(restored._storage_path("PENDING_RESTART")))
	check(not synced._local_pending.name and not synced._local_pending.avatar, "a successful matching cloud save clears only its persisted cosmetic pending flags")
	var latest := TestProfile.new()
	latest.game = game
	game.add_child(latest)
	latest.set_process(false)
	game.account.replies = [record("New Cloud", 900, png())]
	await latest.account_changed()
	check(latest.display_name == "New Cloud" and ProfileScript.validate_avatar(latest.avatar), "later cloud cosmetic changes load normally after prior local edits were synced")
	restored.queue_free()
	latest.queue_free()
	await frames()

func test_menu(game: MockGame, profile: TestProfile) -> void:
	var menu := ProfileMenuScript.new()
	menu.game = game
	game.add_child(menu)
	menu.set_open(true)
	check(menu.is_open and game.opened == 1 and menu.toggle_key == KEY_F5, "profile opens through the shared menu coordinator with its F5 shortcut")
	menu._set_name("Menu Monke")
	menu._dispatch("save")
	await frames()
	check(profile.display_name == "Menu Monke" and menu._world_name.text.contains("Menu Monke"), "desktop name edits share state with headset profile controls")
	check(menu._desktop_level.text.contains("LEVEL") and menu._desktop_progress.max_value > 0, "profile shows level and a bounded XP progress bar")
	check(menu._desktop_picture.texture != null and menu._world_picture.texture != null, "desktop and headset profile pictures have a built-in fallback")
	await test_desktop_widths(menu)
	var bounds := Rect2(-menu.panel_size * 0.5, menu.panel_size)
	var valid := true
	var overlap := false
	for index in range(menu._world_buttons.size()):
		var rectangle: Rect2 = menu._world_buttons[index].rect
		valid = valid and bounds.encloses(rectangle)
		for previous in range(index):
			overlap = overlap or rectangle.intersects(menu._world_buttons[previous].rect)
	check(valid and not overlap, "headset profile buttons stay inside the panel without overlapping ray targets")
	menu._dispatch("clear_name")
	menu._dispatch("key:M")
	menu._dispatch("key:O")
	menu._dispatch("key:N")
	menu._dispatch("save")
	check(profile.display_name == "MON", "VR keyboard can create and save a public name")
	await frames()
	menu._picker_generation = profile._generation
	game.account.account_id = "PLAYER_UI_NEXT"
	await profile.account_changed()
	menu.refresh_status()
	check(menu._name_edit.text == "Monke" and menu._name_buffer == "Monke", "changing account clears the previous owner's editable public name")
	menu._picture_selected(TEST_FOLDER.path_join("local-picture.png"))
	check(profile.avatar.is_empty() and menu._desktop_status.text.contains("account changed"), "picture selection from an old account cannot modify a newer profile")
	menu._dispatch("close")
	check(not menu.is_open and game.closed == 1, "closing profile restores the coordinated underlying menu")
	game.frontend_state = "loading"
	menu.set_open(true)
	check(not menu.is_open, "loading prevents profile from taking over navigation")
	menu.queue_free()

func test_desktop_widths(menu: Node) -> void:
	var original_size: Vector2i = root.size
	var original_scale: Vector2i = root.content_scale_size
	for size in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(520, 640), Vector2i(360, 480)]:
		root.size = size
		root.content_scale_size = size
		await frames(6)
		var width := root.get_visible_rect().size.x
		var frame: Dictionary = menu._desktop_frame
		check(frame.panel.size.x <= width - 47 and frame.scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and frame.scroll.follow_focus, "profile card fits width " + str(width) + " while tall content remains scrollable")
		check(menu._desktop_picture_actions.columns == (2 if width >= 600 else 1) and menu._desktop_actions.columns == (3 if width >= 600 else 1) and menu._desktop_hero.columns == (2 if width >= 480 else 1), "profile picture, action and progress groups adapt at width " + str(width))
		var inside := true
		for button in menu._desktop_buttons.values():
			var rectangle: Rect2 = button.get_global_rect()
			inside = inside and rectangle.position.x >= 0 and rectangle.end.x <= width
		check(inside, "every profile button stays within desktop width " + str(width))
	root.size = original_size
	root.content_scale_size = original_scale
	await frames(3)
