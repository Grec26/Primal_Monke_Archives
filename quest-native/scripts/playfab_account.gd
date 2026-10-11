extends Node

# TitleData is writable by title administrators, never by the client API.
# A player-supplied PlayFab ID is never accepted as proof of identity.
signal state_changed
const DEVELOPER_KEY := "PrimalMonkeDeveloperIds"
const LEASE_MS := 300000
const REFRESH_MS := 240000
var title_id := ""
var account_id := ""
var has_credentials := false
var busy := false
var status := "Not signed in"
var _ticket := ""
var _developer := false
var _access_until_ms := 0
var _next_refresh_ms := 0
var _generation := 0

func _ready() -> void:
	title_id = str(ProjectSettings.get_setting("primal_monke/playfab/title_id", "")).strip_edges().to_upper()
	if not configured(): status = "Account sign-in is unavailable in this build"

func configured() -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9A-F]{1,16}$")
	return pattern.search(title_id) != null

func is_signed_in() -> bool:
	return not _ticket.is_empty() and not account_id.is_empty()

func is_developer() -> bool:
	return is_signed_in() and _developer and Time.get_ticks_msec() < _access_until_ms

func _identity_path() -> String:
	return "user://playfab_device_identity.txt"

func _device_identity() -> String:
	# This random device credential stays in local user storage, never in the repo,
	# UI or logs. It is unrelated to a public PlayFab ID or computer nickname.
	var path := _identity_path()
	if FileAccess.file_exists(path):
		var stored := FileAccess.get_file_as_string(path).strip_edges()
		var pattern := RegEx.new()
		pattern.compile("^PM-[0-9a-f]{64}$")
		if pattern.search(stored) != null: return stored
	var bytes := Crypto.new().generate_random_bytes(32)
	if bytes.size() != 32: return ""
	var identity := "PM-" + bytes.hex_encode()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return ""
	file.store_string(identity)
	file.close()
	return identity

func sign_out() -> void:
	_generation += 1
	_ticket = ""
	account_id = ""
	has_credentials = false
	_developer = false
	_access_until_ms = 0
	_next_refresh_ms = 0
	busy = false
	status = "Signed out — device identity retained for your next sign-in"
	state_changed.emit()

func login_device() -> void:
	if busy: return
	if not configured():
		_fail("Account sign-in is unavailable in this build")
		return
	var identity := _device_identity()
	if identity.is_empty():
		_fail("Could not save this device's account. Check available storage.")
		return
	await _login("LoginWithCustomID", {"TitleId": title_id, "CustomId": identity, "CreateAccount": true})

func _validation_error(message: String) -> void:
	status = message
	state_changed.emit()

func login_credentials(identifier: String, password: String) -> void:
	if busy: return
	identifier = identifier.strip_edges()
	if identifier.is_empty() or identifier.length() > 254 or password.length() < 6 or password.length() > 100:
		_validation_error("Enter your username/email and a password of 6–100 characters")
		return
	var email_login := identifier.contains("@")
	if not email_login and (identifier.length() < 3 or identifier.length() > 20):
		_validation_error("Usernames must be 3–20 characters")
		return
	var payload := {"TitleId": title_id, "Password": password}
	payload["Email" if email_login else "Username"] = identifier
	await _login("LoginWithEmailAddress" if email_login else "LoginWithPlayFab", payload)

func register(username: String, email: String, password: String) -> void:
	if busy: return
	username = username.strip_edges()
	email = email.strip_edges()
	var email_pattern := RegEx.new()
	email_pattern.compile("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")
	if username.length() < 3 or username.length() > 20 or username.contains("@"):
		_validation_error("Choose a username of 3–20 characters")
		return
	if email.length() > 254 or email_pattern.search(email) == null:
		_validation_error("Enter a valid email address")
		return
	if password.length() < 6 or password.length() > 100:
		_validation_error("Choose a password of 6–100 characters")
		return
	if has_credentials:
		_validation_error("This account is registered. Sign out to create another account.")
		return
	var payload := {"Username": username, "Email": email, "Password": password}
	if not is_signed_in():
		payload["TitleId"] = title_id
		payload["RequireBothUsernameAndEmail"] = true
		await _login("RegisterPlayFabUser", payload)
		return
	# Upgrade the signed-in anonymous account so its public ID and dev role survive.
	_generation += 1
	var generation := _generation
	busy = true
	status = "Registering this account…"
	state_changed.emit()
	var reply: Dictionary = await _request("AddUsernamePassword", payload, _ticket)
	if generation != _generation: return
	if not reply.get("ok", false):
		busy = false
		_validation_error("Registration failed. Check your details; username/email may already be in use.")
		return
	var verified: Dictionary = await _request("GetAccountInfo", {}, _ticket)
	if generation != _generation: return
	if not verified.get("ok", false) or _verified_id(verified) != account_id or not _has_credentials(verified):
		_fail("Could not verify registration. Sign in again with your new credentials.")
		return
	has_credentials = true
	await _load_permissions(generation)

func _login(api: String, payload: Dictionary) -> void:
	sign_out()
	if not configured():
		_validation_error("Account sign-in is unavailable in this build")
		return
	var generation := _generation
	busy = true
	status = "Signing in with PlayFab…"
	state_changed.emit()
	var reply: Dictionary = await _request(api, payload)
	if generation != _generation: return
	if not reply.get("ok", false):
		_fail("Sign-in or registration failed. Check your details and connection.")
		return
	var data: Dictionary = reply.get("data", {})
	var id: Variant = data.get("PlayFabId")
	var ticket: Variant = data.get("SessionTicket")
	if not id is String or id.is_empty() or not ticket is String or ticket.is_empty():
		_fail("PlayFab returned an incomplete sign-in response")
		return
	# Keep the proposed identity private until the ticket's owner is verified.
	var verified: Dictionary = await _request("GetAccountInfo", {}, ticket)
	if generation != _generation: return
	if not verified.get("ok", false) or _verified_id(verified) != id:
		_fail("Could not verify this device's PlayFab account")
		return
	account_id = id
	_ticket = ticket
	has_credentials = _has_credentials(verified)
	await _load_permissions(generation)

func _has_credentials(reply: Dictionary) -> bool:
	var data: Variant = reply.get("data", {})
	var info: Variant = data.get("AccountInfo", {}) if data is Dictionary else {}
	if not info is Dictionary: return false
	var username: Variant = info.get("Username", "")
	return username is String and not username.is_empty()

func _verified_id(reply: Dictionary) -> String:
	var data: Variant = reply.get("data", {})
	if not data is Dictionary: return ""
	var info: Variant = data.get("AccountInfo", {})
	if not info is Dictionary: return ""
	var id: Variant = info.get("PlayFabId", "")
	return id if id is String else ""

func refresh_permissions() -> void:
	if busy or not is_signed_in(): return
	var generation := _generation
	busy = true
	status = "Checking developer access…"
	state_changed.emit()
	var verified: Dictionary = await _request("GetAccountInfo", {}, _ticket)
	if generation != _generation: return
	if not verified.get("ok", false) or _verified_id(verified) != account_id:
		_fail("Account verification expired. Sign in again.")
		return
	has_credentials = _has_credentials(verified)
	await _load_permissions(generation)

func _load_permissions(generation: int) -> void:
	var reply: Dictionary = await _request("GetTitleData", {"Keys": [DEVELOPER_KEY]}, _ticket)
	if generation != _generation: return
	_developer = false
	_access_until_ms = 0
	_next_refresh_ms = Time.get_ticks_msec() + REFRESH_MS
	busy = false
	if reply.get("ok", false):
		var envelope: Variant = reply.get("data", {})
		var data: Variant = envelope.get("Data", {}) if envelope is Dictionary else {}
		var raw: Variant = data.get(DEVELOPER_KEY, "") if data is Dictionary else ""
		var ids: Variant = JSON.parse_string(raw) if raw is String and not raw.is_empty() else null
		# Malformed/missing lists grant nobody access. All entries must be ID strings.
		if ids is Array and ids.all(func(value): return value is String and not value.strip_edges().is_empty()):
			for id in ids:
				if id.strip_edges().to_upper() == account_id.to_upper():
					_developer = true
					_access_until_ms = Time.get_ticks_msec() + LEASE_MS
					break
		status = "Developer access verified" if _developer else "Signed in — player account (developer tools locked)"
	else:
		status = "Signed in — access check unavailable (developer tools locked)"
	state_changed.emit()

func _fail(message: String) -> void:
	_ticket = ""
	account_id = ""
	has_credentials = false
	_developer = false
	_access_until_ms = 0
	busy = false
	status = message
	state_changed.emit()

func _request(api: String, payload: Dictionary, ticket := "") -> Dictionary:
	if not configured(): return {"ok": false}
	var http := HTTPRequest.new()
	http.timeout = 12
	http.body_size_limit = 524288
	http.max_redirects = 0
	http.use_threads = true
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not ticket.is_empty(): headers.append("X-Authorization: " + ticket)
	var error := http.request("https://%s.playfabapi.com/Client/%s" % [title_id, api], headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		http.queue_free()
		return {"ok": false}
	var response: Array = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200: return {"ok": false}
	var decoded: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if not decoded is Dictionary or decoded.get("code", 0) != 200 or not decoded.get("data") is Dictionary:
		return {"ok": false}
	return {"ok": true, "data": decoded.data}

func _process(_delta: float) -> void:
	if _developer and Time.get_ticks_msec() >= _access_until_ms:
		_developer = false
		status = "Developer access expired — refresh access to continue"
		state_changed.emit()
	if is_signed_in() and not busy and _next_refresh_ms > 0 and Time.get_ticks_msec() >= _next_refresh_ms:
		refresh_permissions()
