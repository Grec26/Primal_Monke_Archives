extends RefCounted

# Numeric PlayFab names come from the official PlayFabErrorCode enum. Unknown
# responses get local codes or a bounded numeric diagnostic, never response text.
const VALIDATION_CODE := "PM-A01"
const VERIFICATION_CODE := "PM-A02"
const PROVIDER_REJECTED_CODE := "PM-A09"
const ACCOUNT_CHANGED_CODE := "PM-A10"
const PROVIDER_CODES := {
	"InvalidParams": 1000,
	"AccountNotFound": 1001,
	"AccountBanned": 1002,
	"InvalidUsernameOrPassword": 1003,
	"InvalidTitleId": 1004,
	"InvalidEmailAddress": 1005,
	"EmailAddressNotAvailable": 1006,
	"InvalidUsername": 1007,
	"InvalidPassword": 1008,
	"UsernameNotAvailable": 1009,
	"AccountAlreadyLinked": 1011,
	"DuplicateEmail": 1046,
	"NameNotAvailable": 1058,
	"DuplicateUsername": 1065,
	"APINotEnabledForGameClientAccess": 1082,
	"ServiceUnavailable": 1123,
	"APIRequestLimitExceeded": 1130,
	"InvalidEmailOrPassword": 1142,
	"NotAuthorizedByTitle": 1191,
	"APIConcurrentRequestLimitExceeded": 1342,
	"PlayerCreationDisabled": 22000,
	"AccountAlreadyExists": 22001
}
const LOCAL_CODES := {
	"Connection": "PM-N01",
	"Timeout": "PM-N02",
	"TLS": "PM-N03",
	"InvalidResponse": "PM-N04",
	"RequestLimitExceeded": "PM-N05",
	"AccountChanged": ACCOUNT_CHANGED_CODE
}

static func code_for(reply: Dictionary) -> String:
	var ok: Variant = reply.get("ok", false)
	if ok is bool and ok: return ""
	var identifier: Variant = reply.get("error", "")
	if identifier is String:
		if PROVIDER_CODES.has(identifier): return "PF-%d" % PROVIDER_CODES[identifier]
		if LOCAL_CODES.has(identifier): return LOCAL_CODES[identifier]
	var code: Variant = reply.get("provider_code")
	if (code is int or code is float) and code >= 1000 and code <= 999999 and code == int(code):
		return "PF-%d" % int(code)
	return PROVIDER_REJECTED_CODE
