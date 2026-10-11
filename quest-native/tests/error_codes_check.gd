extends SceneTree

const Codes = preload("res://scripts/error_codes.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	# These public numeric identifiers are documented by the official SDK enum.
	var official := {
		"InvalidParams": "PF-1000", "AccountNotFound": "PF-1001",
		"AccountBanned": "PF-1002", "InvalidUsernameOrPassword": "PF-1003",
		"InvalidTitleId": "PF-1004", "InvalidEmailAddress": "PF-1005",
		"EmailAddressNotAvailable": "PF-1006", "InvalidUsername": "PF-1007",
		"InvalidPassword": "PF-1008", "UsernameNotAvailable": "PF-1009",
		"AccountAlreadyLinked": "PF-1011", "DuplicateEmail": "PF-1046",
		"NameNotAvailable": "PF-1058", "DuplicateUsername": "PF-1065",
		"APINotEnabledForGameClientAccess": "PF-1082", "ServiceUnavailable": "PF-1123",
		"APIRequestLimitExceeded": "PF-1130", "InvalidEmailOrPassword": "PF-1142",
		"NotAuthorizedByTitle": "PF-1191", "APIConcurrentRequestLimitExceeded": "PF-1342",
		"PlayerCreationDisabled": "PF-22000", "AccountAlreadyExists": "PF-22001"
	}
	for identifier in official:
		check(Codes.code_for({"ok": false, "error": identifier, "provider_code": 5847}) == official[identifier], "documented provider code has precedence: " + identifier)
	var local := {"Connection": "PM-N01", "Timeout": "PM-N02", "TLS": "PM-N03", "InvalidResponse": "PM-N04", "RequestLimitExceeded": "PM-N05", "AccountChanged": "PM-A10"}
	for identifier in local:
		check(Codes.code_for({"ok": false, "error": identifier, "provider_code": 5847}) == local[identifier], "local transport or account-change code has precedence: " + identifier)
	check(Codes.VALIDATION_CODE == "PM-A01" and Codes.VERIFICATION_CODE == "PM-A02", "validation and verification failures have separate stable application codes")
	check(Codes.code_for({}) == "PM-A09", "missing error details receive generic local rejection code")
	check(Codes.code_for({"ok": false, "error": "ProviderRejected"}) == "PM-A09", "unknown provider rejection receives generic local code")
	check(Codes.code_for({"ok": true, "error": "Connection", "provider_code": 5847}) == "", "successful response never carries stale error code")
	for code in [1000, 5847, 5847.0, 999999]:
		check(Codes.code_for({"ok": false, "error": "ProviderRejected", "provider_code": code}) == "PF-%d" % int(code), "bounded unknown provider number is preserved safely: %s" % code)
	for code in [null, "5847", -5847, 0, 999, 1000000, 5847.25, true, {}, [5847], INF, -INF, NAN]:
		check(Codes.code_for({"ok": false, "error": "ProviderRejected", "provider_code": code}) == "PM-A09", "invalid diagnostic type, range or nonfinite value cannot produce a provider code")
	var private_detail := "private@example.invalid secret-password test-session-ticket"
	for identifier in [private_detail, "EmailAddressNotAvailable\n" + private_detail, "PF-5847", "Connection " + private_detail, 1006, {"error": private_detail}, [private_detail]]:
		var result: String = Codes.code_for({"ok": false, "error": identifier, "errorMessage": private_detail, "errorDetails": {"Password": private_detail}, "data": {"SessionTicket": private_detail}})
		check(result == "PM-A09" and not result.contains(private_detail), "raw provider strings and nested private fields never become user-facing codes")
	var result: String = Codes.code_for({"ok": false, "error": private_detail, "provider_code": 5847, "errorMessage": private_detail, "errorDetails": {"Password": private_detail}})
	check(result == "PF-5847" and not result.contains(private_detail), "unknown 5847 diagnostic survives without provider text or invented meaning")
	print("Error code checks complete; checks: %s; failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)
