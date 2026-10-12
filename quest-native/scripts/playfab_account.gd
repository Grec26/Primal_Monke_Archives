extends Node

# TitleData is writable by title administrators, never by the client API.
# A player-supplied PlayFab ID is never accepted as proof of identity.
signal state_changed
const DEVELOPER_KEY := "PrimalMonkeDeveloperIds"
# Older titles used PMDID. The canonical key takes precedence whenever present,
# including an empty list: a revoked developer must not regain access via an
# outdated legacy list. Both values still come only from authenticated TitleData.
const LEGACY_DEVELOPER_KEY := "PMDID"
const LEASE_MS := 300000
const REFRESH_MS := 240000
const ErrorCodes = preload("res://scripts/error_codes.gd")
# Keep only identifiers we recognize. Provider error text/details may contain
# submitted credentials or addresses and must never reach UI, logs or storage.
const PROVIDER_ERRORS := [
	"EmailAddressNotAvailable", "UsernameNotAvailable", "InvalidUsernameOrPassword",
	"AccountNotFound", "PlayerCreationDisabled", "InvalidTitleId",
	"APINotEnabledForGameClientAccess", "InvalidParams", "InvalidEmailAddress",
	"AccountAlreadyLinked", "AccountAlreadyExists", "NameNotAvailable",
	"InvalidPassword", "InvalidUsername", "ServiceUnavailable", "RequestLimitExceeded",
	"DuplicateEmail", "DuplicateUsername", "InvalidEmailOrPassword",
	"APIRequestLimitExceeded", "APIConcurrentRequestLimitExceeded",
	"AccountBanned", "NotAuthorizedByTitle"
]
var title_id := ""
var account_id := ""
var username := ""
var has_credentials := false
var busy := false
var status := "Not signed in"
var error_code := ""
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
	username = ""
	has_credentials = false
	_developer = false
	_access_until_ms = 0
	_next_refresh_ms = 0
	busy = false
	status = "Signed out — device identity retained for your next sign-in"
	error_code = ""
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

func _validation_error(message: String, code := ErrorCodes.VALIDATION_CODE) -> void:
	error_code = code
	status = message if message.ends_with("[" + code + "]") else message + " [" + code + "]"
	state_changed.emit()

static func login_error(identifier: String, password: String) -> String:
	identifier = identifier.strip_edges()
	if identifier.is_empty() or identifier.length() > 254 or password.length() < 6 or password.length() > 100:
		return "Enter your username/email and a password of 6–100 characters"
	if not identifier.contains("@") and (identifier.length() < 3 or identifier.length() > 20):
		return "Usernames must be 3–20 characters"
	if identifier.contains("@") and not _valid_email(identifier):
		return "Enter a valid email address"
	return ""

static func _valid_email(email: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[^\\s@]+@[^\\s@.]+(?:\\.[^\\s@.]+)+$")
	return email.length() <= 254 and not email.contains("..") and pattern.search(email) != null

static func registration_error(username: String, email: String, password: String) -> String:
	username = username.strip_edges()
	email = email.strip_edges()
	if username.length() < 3 or username.length() > 20 or username.contains("@"):
		return "Choose a username of 3–20 characters without @"
	if not _valid_email(email):
		return "Enter a valid email address"
	if password.length() < 6 or password.length() > 100:
		return "Choose a password of 6–100 characters"
	return ""

func login_credentials(identifier: String, password: String) -> void:
	if busy: return
	var validation := login_error(identifier, password)
	if not validation.is_empty():
		_validation_error(validation)
		return
	identifier = identifier.strip_edges()
	var email_login := identifier.contains("@")
	var payload := {"TitleId": title_id, "Password": password}
	payload["Email" if email_login else "Username"] = identifier
	await _login("LoginWithEmailAddress" if email_login else "LoginWithPlayFab", payload)

func register(username: String, email: String, password: String) -> void:
	if busy: return
	var validation := registration_error(username, email, password)
	if not validation.is_empty():
		_validation_error(validation)
		return
	username = username.strip_edges()
	email = email.strip_edges()
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
		var message := _error_message(reply, "AddUsernamePassword")
		_validation_error(message, error_code)
		return
	var verified: Dictionary = await _request("GetAccountInfo", {}, _ticket)
	if generation != _generation: return
	if not verified.get("ok", false) or _verified_id(verified) != account_id or not _has_credentials(verified):
		_fail("Could not verify registration. Sign in again with your new credentials.")
		return
	has_credentials = true
	self.username = str(verified.data.AccountInfo.Username)
	await _load_permissions(generation, "Account registered. ")

func _login(api: String, payload: Dictionary) -> void:
	sign_out()
	if not configured():
		_validation_error("Account sign-in is unavailable in this build")
		return
	var generation := _generation
	busy = true
	status = "Creating your PlayFab account…" if api == "RegisterPlayFabUser" else "Signing in with PlayFab…"
	state_changed.emit()
	var reply: Dictionary = await _request(api, payload)
	if generation != _generation: return
	if not reply.get("ok", false):
		var message := _error_message(reply, api)
		_fail(message, error_code)
		return
	var data: Dictionary = reply.get("data", {})
	var id: Variant = data.get("PlayFabId")
	var ticket: Variant = data.get("SessionTicket")
	if not id is String or id.is_empty() or not ticket is String or ticket.is_empty():
		_fail("Registration may have completed. Choose Sign in with your new credentials." if api == "RegisterPlayFabUser" else "PlayFab returned an incomplete sign-in response")
		return
	# Keep the proposed identity private until the ticket's owner is verified.
	var verified: Dictionary = await _request("GetAccountInfo", {}, ticket)
	if generation != _generation: return
	if not verified.get("ok", false) or _verified_id(verified) != id or (api == "RegisterPlayFabUser" and not _has_credentials(verified)):
		_fail("Your account was created, but sign-in could not be verified. Choose Sign in with your new credentials." if api == "RegisterPlayFabUser" else "Could not verify your PlayFab account. Try signing in again.")
		return
	account_id = id
	_ticket = ticket
	has_credentials = _has_credentials(verified)
	username = str(verified.data.AccountInfo.get("Username", "")) if has_credentials else ""
	await _load_permissions(generation, "Account registered. " if api == "RegisterPlayFabUser" else "")

func client_request(api: String, payload: Dictionary) -> Dictionary:
	# Only ordinary, account-scoped profile operations are exposed to features.
	# No title data, developer list or server/admin endpoint can be written here.
	if api not in ["GetUserData", "UpdateUserData", "UpdateUserTitleDisplayName"]:
		return {"ok": false, "error": "NotAuthorizedByTitle"}
	if not is_signed_in(): return {"ok": false, "error": "AccountNotFound"}
	if payload.has("PlayFabId"):
		var requested_id: Variant = payload.PlayFabId
		if not requested_id is String or requested_id.to_upper() != account_id.to_upper():
			return {"ok": false, "error": "NotAuthorizedByTitle"}
	var generation := _generation
	var ticket := _ticket
	var reply: Dictionary = await _request(api, payload, ticket)
	if generation != _generation or ticket != _ticket or not is_signed_in():
		return {"ok": false, "error": "AccountChanged"}
	return reply

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
	username = str(verified.data.AccountInfo.get("Username", "")) if has_credentials else ""
	await _load_permissions(generation)

func _load_permissions(generation: int, success_prefix := "") -> void:
	var reply: Dictionary = await _request("GetTitleData", {"Keys": [DEVELOPER_KEY, LEGACY_DEVELOPER_KEY]}, _ticket)
	if generation != _generation: return
	_developer = false
	_access_until_ms = 0
	_next_refresh_ms = Time.get_ticks_msec() + REFRESH_MS
	busy = false
	error_code = ""
	if reply.get("ok", false):
		var envelope: Variant = reply.get("data", {})
		var data: Variant = envelope.get("Data", {}) if envelope is Dictionary else {}
		var key := DEVELOPER_KEY if data is Dictionary and data.has(DEVELOPER_KEY) else LEGACY_DEVELOPER_KEY
		var raw: Variant = data.get(key) if data is Dictionary else null
		# Use the quiet parser: an invalid title configuration must not echo its
		# contents into logs. PlayFab TitleData values are JSON encoded strings.
		var parser := JSON.new()
		var parsed: bool = raw is String and not raw.is_empty() and parser.parse(raw) == OK
		var ids: Variant = parser.data if parsed else null
		# Malformed/missing lists grant nobody access. All entries must be ID strings.
		var valid_list: bool = ids is Array and ids.all(func(value): return value is String and not value.strip_edges().is_empty())
		if valid_list:
			for id in ids:
				if id.strip_edges().to_upper() == account_id.to_upper():
					_developer = true
					_access_until_ms = Time.get_ticks_msec() + LEASE_MS
					break
		status = "Developer access verified" if _developer else "Signed in — player account (developer tools locked)"
		if _developer and key == LEGACY_DEVELOPER_KEY:
			status += " · PMDID"
		elif not data is Dictionary or not data.has(key):
			status = "Signed in — developer list missing (tools locked)"
		elif not valid_list:
			status = "Signed in — invalid developer list (tools locked)"
	else:
		error_code = ErrorCodes.code_for(reply)
		status = "Signed in — access check unavailable (tools locked) [" + error_code + "]"
	status = success_prefix + status
	state_changed.emit()

func _fail(message: String, code := ErrorCodes.VERIFICATION_CODE) -> void:
	_ticket = ""
	account_id = ""
	username = ""
	has_credentials = false
	_developer = false
	_access_until_ms = 0
	busy = false
	error_code = code
	status = message if message.ends_with("[" + code + "]") else message + " [" + code + "]"
	state_changed.emit()

func _error_message(reply: Dictionary, action: String) -> String:
	error_code = ErrorCodes.code_for(reply)
	var explanation := _error_explanation(reply, action)
	return explanation + (" [" + error_code + "]" if not error_code.is_empty() else "")

func _error_explanation(reply: Dictionary, action: String) -> String:
	var registering := action == "RegisterPlayFabUser" or action == "AddUsernamePassword"
	match reply.get("error", ""):
		"EmailAddressNotAvailable", "DuplicateEmail": return "That email is already in use. Choose Sign in, or use another email."
		"UsernameNotAvailable", "NameNotAvailable", "DuplicateUsername": return "That username is already in use. Choose another username."
		"InvalidUsernameOrPassword", "InvalidEmailOrPassword", "AccountNotFound": return "Sign-in failed. Check your username/email and password, or choose Create account."
		"PlayerCreationDisabled": return "Device accounts are disabled for this game. Choose Create account to register with email and password."
		"InvalidTitleId", "APINotEnabledForGameClientAccess": return "Account service is unavailable for this game. The owner must check the PlayFab title and account API policy."
		"InvalidEmailAddress": return "PlayFab rejected the email address. Enter a valid email."
		"InvalidPassword": return "PlayFab rejected the password. Choose a password of 6–100 characters."
		"InvalidUsername": return "PlayFab rejected the username. Choose another username of 3–20 characters."
		"InvalidParams": return "PlayFab rejected the details. Check your username, email and password."
		"AccountAlreadyLinked", "AccountAlreadyExists": return "This account is already registered. Choose Sign in with your existing credentials."
		"RequestLimitExceeded", "APIRequestLimitExceeded", "APIConcurrentRequestLimitExceeded": return "Too many account requests. Wait a moment, then try again."
		"AccountBanned": return "This PlayFab account is banned. Contact the game's owner."
		"NotAuthorizedByTitle": return "PlayFab has denied account access for this game. Contact the game's owner."
		"ServiceUnavailable": return "PlayFab is temporarily unavailable. Try again later."
		"Timeout": return "PlayFab timed out. Try Sign in with your new credentials before registering again." if registering else "PlayFab timed out. Try signing in again."
		"Connection": return "Could not reach PlayFab. Check your internet connection and try again."
		"TLS": return "Could not make a secure connection to PlayFab. Check your internet connection and device date/time."
		"InvalidResponse": return "PlayFab returned an unreadable response. Try Sign in before registering again." if registering else "PlayFab returned an unreadable response. Try again."
	var message := "Registration failed. Check your details or try Sign in if you already have an account." if registering else "Sign-in failed. Check your details and connection."
	var provider_code := _safe_error_code(reply.get("provider_code"))
	if provider_code > 0: message += " PlayFab error code %d." % provider_code
	return message

func _safe_error_code(value: Variant) -> int:
	if (value is int or value is float) and value >= 1000 and value <= 999999 and value == int(value):
		return int(value)
	return 0

func _decode_response(result: int, response_code: int, body: PackedByteArray) -> Dictionary:
	match result:
		HTTPRequest.RESULT_TIMEOUT: return {"ok": false, "error": "Timeout"}
		HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return {"ok": false, "error": "Connection"}
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return {"ok": false, "error": "TLS"}
	if result != HTTPRequest.RESULT_SUCCESS: return {"ok": false, "error": "InvalidResponse"}
	# JSON.parse_string logs tokens from malformed replies. Use the quiet parser
	# so an unexpected provider response cannot echo private values to logs.
	var parser := JSON.new()
	var parsed := parser.parse(body.get_string_from_utf8()) == OK
	var decoded: Variant = parser.data if parsed else null
	if response_code == 200:
		if decoded is Dictionary:
			var code: Variant = decoded.get("code")
			if (code is int or code is float) and code == 200 and decoded.get("data") is Dictionary:
				return {"ok": true, "data": decoded.data}
		return {"ok": false, "error": "InvalidResponse"}
	if response_code == 429: return {"ok": false, "error": "RequestLimitExceeded"}
	if response_code >= 500: return {"ok": false, "error": "ServiceUnavailable"}
	if decoded is Dictionary:
		var error: Variant = decoded.get("error", "")
		if error is String and error in PROVIDER_ERRORS:
			return {"ok": false, "error": error}
		var provider_code := _safe_error_code(decoded.get("errorCode"))
		if provider_code > 0:
			return {"ok": false, "error": "ProviderRejected", "provider_code": provider_code}
	return {"ok": false, "error": "ProviderRejected"}

func _request(api: String, payload: Dictionary, ticket := "") -> Dictionary:
	if not configured(): return {"ok": false, "error": "InvalidTitleId"}
	var http := HTTPRequest.new()
	http.timeout = 12
	http.body_size_limit = 524288
	http.max_redirects = 0
	http.use_threads = true
	# PlayFab can return raw DEFLATE that Godot cannot decompress. These small
	# account replies use plain JSON for compatibility, with TLS still verified.
	http.accept_gzip = false
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not ticket.is_empty(): headers.append("X-Authorization: " + ticket)
	var error := http.request("https://%s.playfabapi.com/Client/%s" % [title_id, api], headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		http.queue_free()
		return {"ok": false, "error": "Connection"}
	var response: Array = await http.request_completed
	http.queue_free()
	return _decode_response(response[0], response[1], response[3])

func _process(_delta: float) -> void:
	if _developer and Time.get_ticks_msec() >= _access_until_ms:
		_developer = false
		status = "Developer access expired — refresh access to continue"
		state_changed.emit()
	if is_signed_in() and not busy and _next_refresh_ms > 0 and Time.get_ticks_msec() >= _next_refresh_ms:
		refresh_permissions()
