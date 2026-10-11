extends Node

# This is cosmetic progression, managed by the client. It grants no gameplay
# authority or developer permissions. The verified account owns its own save.
signal public_profile_changed
signal state_changed

const CLOUD_KEY := "PMProfileV1"
const MAX_XP := 10000000
const MAX_LEVEL := 316
const MAX_AVATAR_BYTES := 6000
const MAX_FILE_BYTES := 4 * 1024 * 1024
const MAX_SOURCE_EDGE := 4096
const SAVE_INTERVAL_MS := 10000
const DEFAULT_NAME := "Monke"

var game: Node
var display_name := DEFAULT_NAME
var xp := 0
var level: int:
	get: return level_from_xp(xp)
var avatar := PackedByteArray()
var status := "Guest profile · progress is saved on this device."
var _bound_id := ""
var _generation := 0
var _revision := 0
var _dirty := false
var _saving := false
var _next_save_ms := 0
var _events: Dictionary = {}
var _loaded := false
var _cloud_ready := false
var _cloud_loading := false
var _cloud_retry_requested := false
var _next_read_ms := 0
var _load_baseline_xp := 0
var _name_revision := 0
var _avatar_revision := 0

static func level_from_xp(value: int) -> int:
	return clampi(int(floor(sqrt(float(clampi(value, 0, MAX_XP)) / 100.0))) + 1, 1, MAX_LEVEL)

static func clean_name(value: Variant) -> String:
	if not value is String:
		return DEFAULT_NAME
	var cleaned := ""
	for character in value.left(128).strip_edges():
		var code: int = character.unicode_at(0)
		if code >= 32 and code != 127 and not (code >= 0x202a and code <= 0x202e) and not (code >= 0x2066 and code <= 0x2069):
			cleaned += character
		if cleaned.length() >= 20:
			break
	return cleaned.strip_edges() if not cleaned.strip_edges().is_empty() else DEFAULT_NAME

static func _be32(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])

static func _png_dimensions(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 33 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return Vector2i.ZERO
	if _be32(bytes, 8) != 13 or bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
		return Vector2i.ZERO
	return Vector2i(_be32(bytes, 16), _be32(bytes, 20))

static func _jpeg_dimensions(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 4 or bytes[0] != 255 or bytes[1] != 216:
		return Vector2i.ZERO
	var offset := 2
	while offset + 4 <= bytes.size():
		if bytes[offset] != 255:
			return Vector2i.ZERO
		while offset < bytes.size() and bytes[offset] == 255:
			offset += 1
		if offset >= bytes.size():
			return Vector2i.ZERO
		var marker := bytes[offset]
		offset += 1
		if marker in [0xd9, 0xda, 0x00]:
			return Vector2i.ZERO
		if marker == 0x01 or (marker >= 0xd0 and marker <= 0xd8):
			continue
		if offset + 2 > bytes.size():
			return Vector2i.ZERO
		var length := (int(bytes[offset]) << 8) | int(bytes[offset + 1])
		if length < 2 or offset + length > bytes.size():
			return Vector2i.ZERO
		if marker in [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]:
			if length < 8:
				return Vector2i.ZERO
			return Vector2i((int(bytes[offset + 5]) << 8) | int(bytes[offset + 6]), (int(bytes[offset + 3]) << 8) | int(bytes[offset + 4]))
		offset += length
	return Vector2i.ZERO

static func validate_avatar(bytes: PackedByteArray) -> bool:
	if bytes.is_empty() or bytes.size() > MAX_AVATAR_BYTES:
		return false
	var dimensions := _png_dimensions(bytes)
	if dimensions.x < 1 or dimensions.y < 1 or dimensions.x > 64 or dimensions.y > 64:
		return false
	var image := Image.new()
	return image.load_png_from_buffer(bytes) == OK and image.get_width() == dimensions.x and image.get_height() == dimensions.y

static func sanitize_public_profile(incoming: Variant) -> Dictionary:
	var source: Dictionary = incoming if incoming is Dictionary else {}
	var raw_xp: Variant = source.get("xp", 0)
	var safe_xp := 0
	if raw_xp is int:
		safe_xp = clampi(raw_xp, 0, MAX_XP)
	elif raw_xp is float and is_finite(raw_xp):
		safe_xp = int(clampf(raw_xp, 0.0, float(MAX_XP)))
	var safe_avatar := PackedByteArray()
	var raw_avatar: Variant = source.get("avatar", PackedByteArray())
	if raw_avatar is PackedByteArray and validate_avatar(raw_avatar):
		safe_avatar = raw_avatar.duplicate()
	return {"name": clean_name(source.get("name", DEFAULT_NAME)), "xp": safe_xp, "level": level_from_xp(safe_xp), "avatar": safe_avatar}

func public_profile() -> Dictionary:
	return {"name": display_name, "xp": xp, "level": level_from_xp(xp), "avatar": avatar.duplicate()}

func progress_summary() -> Dictionary:
	var level := level_from_xp(xp)
	var start := (level - 1) * (level - 1) * 100
	var target := MAX_XP if level >= MAX_LEVEL else mini(level * level * 100, MAX_XP)
	return {"level": level, "xp": xp, "current": maxi(0, xp - start), "needed": maxi(1, target - start), "next": target, "max_level": xp >= MAX_XP}

func summary() -> String:
	return "%s · Level %d · %d XP" % [display_name, level, xp]

func _account() -> Node:
	return game.get("account") as Node if is_instance_valid(game) else null

func _current_id() -> String:
	var account := _account()
	return str(account.get("account_id")) if account != null and account.has_method("is_signed_in") and account.call("is_signed_in") else ""

func _now_ms() -> int:
	return Time.get_ticks_msec()

func _storage_path(identity: String) -> String:
	# Public IDs never form a path, and credentials are never serialized here.
	return "user://profile_guest.json" if identity.is_empty() else "user://profile_" + identity.sha256_text().left(32) + ".json"

func _encoded() -> Dictionary:
	return {"version": 1, "name": display_name, "xp": xp, "avatar": "" if avatar.is_empty() else Marshalls.raw_to_base64(avatar)}

func _quiet_json(text: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK else null

func _decode_saved(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return sanitize_public_profile({})
	var bytes := PackedByteArray()
	var encoded: Variant = value.get("avatar", "")
	if encoded is String and not encoded.is_empty() and encoded.length() <= 8000 and encoded.length() % 4 == 0:
		var base64 := RegEx.new()
		base64.compile("^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$")
		if base64.search(encoded) != null:
			bytes = Marshalls.base64_to_raw(encoded)
	return sanitize_public_profile({"name": value.get("name", DEFAULT_NAME), "xp": value.get("xp", 0), "avatar": bytes})

func _load_local() -> void:
	var path := _storage_path(_bound_id)
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 9000:
		return
	var parsed: Variant = _quiet_json(file.get_as_text())
	if not parsed is Dictionary or parsed.get("version", 0) != 1:
		return
	var decoded := _decode_saved(parsed)
	display_name = decoded.name
	xp = decoded.xp
	avatar = decoded.avatar
	if not _bound_id.is_empty():
		var pending: Variant = parsed.get("_local_pending", {})
		if pending is Dictionary:
			_name_revision = 1 if pending.get("name", false) == true else 0
			_avatar_revision = 1 if pending.get("avatar", false) == true else 0
			_dirty = _name_revision > 0 or _avatar_revision > 0

func _persist_local() -> void:
	var file := FileAccess.open(_storage_path(_bound_id), FileAccess.WRITE)
	if file != null:
		var saved := _encoded()
		# Only local storage records unsynced field ownership. Public UserData
		# keeps the four-field cosmetic schema, without private sync metadata.
		saved["_local_pending"] = {"name": not _bound_id.is_empty() and _name_revision > 0, "avatar": not _bound_id.is_empty() and _avatar_revision > 0}
		file.store_string(JSON.stringify(saved))

func account_changed() -> void:
	var identity := _current_id()
	var account := _account()
	if _loaded and identity == _bound_id:
		return
	_loaded = true
	_generation += 1
	_bound_id = identity
	_revision += 1
	_dirty = false
	_saving = false
	_next_save_ms = 0
	_next_read_ms = 0
	_cloud_ready = false
	_cloud_loading = false
	_cloud_retry_requested = false
	_name_revision = 0
	_avatar_revision = 0
	_events.clear()
	display_name = clean_name(account.get("username")) if account != null and not identity.is_empty() else DEFAULT_NAME
	xp = 0
	avatar = PackedByteArray()
	_load_local()
	_load_baseline_xp = xp
	status = "Guest profile · progress is saved on this device." if identity.is_empty() else "Loading your account profile…"
	public_profile_changed.emit()
	state_changed.emit()
	if identity.is_empty():
		return
	await _read_cloud_profile()

func _read_failed(message: String) -> void:
	_cloud_loading = false
	_cloud_ready = false
	status = message
	state_changed.emit()

func _read_cloud_profile() -> void:
	if _cloud_loading or _bound_id.is_empty() or _bound_id != _current_id():
		return
	if _now_ms() < _next_read_ms:
		_cloud_retry_requested = true
		status = "Local profile retained · cloud read retry is queued."
		state_changed.emit()
		return
	var account := _account()
	if not account.has_method("client_request"):
		_read_failed("Profile saved on this device. Cloud sync unavailable.")
		return
	if account.get("busy") == true:
		_cloud_retry_requested = true
		return
	var generation := _generation
	var identity := _bound_id
	_cloud_loading = true
	_cloud_retry_requested = false
	_next_read_ms = _now_ms() + SAVE_INTERVAL_MS
	status = "Reading your cloud profile before syncing local changes…"
	state_changed.emit()
	var reply: Dictionary = await account.call("client_request", "GetUserData", {"Keys": [CLOUD_KEY]})
	if generation != _generation or identity != _current_id():
		return
	if not reply.get("ok", false):
		_read_failed("Profile retained locally. Cloud read failed; use Retry sync before uploading changes.")
		return
	var data: Variant = reply.get("data", {})
	var records: Variant = data.get("Data", {}) if data is Dictionary else null
	if not records is Dictionary:
		_read_failed("Cloud profile could not be read safely. Local changes retained; use Retry sync.")
		return
	var record: Variant = records.get(CLOUD_KEY, {}) if records is Dictionary else {}
	var value: Variant = record.get("Value", "") if record is Dictionary else ""
	var parsed: Variant = _quiet_json(value) if value is String and not value.is_empty() and value.length() <= 9000 else null
	if records.has(CLOUD_KEY) and (not parsed is Dictionary or parsed.get("version", 0) != 1):
		_read_failed("Cloud profile could not be decoded safely. Local changes retained; use Retry sync.")
		return
	if parsed is Dictionary:
		var decoded := _decode_saved(parsed)
		# The initial cached XP baseline is stable across failed read retries.
		# Rewards earned while the cloud is unread are added to the greater of
		# cached and cloud progress, so a late read cannot erase either source.
		var earned := maxi(0, xp - _load_baseline_xp)
		xp = mini(MAX_XP, maxi(_load_baseline_xp, int(decoded.xp)) + earned)
		_dirty = _dirty or xp > int(decoded.xp)
		if _name_revision == 0:
			display_name = decoded.name
		if _avatar_revision == 0:
			avatar = decoded.avatar
		_revision += 1
		_persist_local()
		public_profile_changed.emit()
	_cloud_loading = false
	_cloud_ready = true
	_cloud_retry_requested = false
	status = "Account profile ready · local changes are queued to sync." if _dirty else "Account profile ready · cosmetic XP is saved locally and synced to PlayFab."
	state_changed.emit()

func _changed() -> void:
	_revision += 1
	_dirty = not _bound_id.is_empty()
	_persist_local()
	status = "Guest profile saved on this device. Sign in to sync." if _bound_id.is_empty() else "Profile saved locally · cloud sync pending."
	public_profile_changed.emit()
	state_changed.emit()

func set_display_name(value: String) -> bool:
	var cleaned := clean_name(value)
	if cleaned.length() < 3:
		status = "Choose a public name with 3–20 characters."
		state_changed.emit()
		return false
	_name_revision += 1
	if cleaned != display_name or _cloud_loading or (not _bound_id.is_empty() and not _cloud_ready):
		display_name = cleaned
		_changed()
	return true

func award_xp(amount: int, unique_event: String) -> bool:
	if amount <= 0 or unique_event.is_empty() or unique_event.length() > 120 or _events.has(unique_event):
		return false
	_events[unique_event] = true
	# Bound session memory. Root uses a unique round key for each reward.
	if _events.size() > 2048:
		_events.erase(_events.keys()[0])
	var next := mini(MAX_XP, xp + mini(amount, 10000))
	if next == xp:
		return false
	xp = next
	_changed()
	return true

func clear_avatar() -> void:
	_avatar_revision += 1
	avatar = PackedByteArray()
	_changed()

static func _picture_kind(bytes: PackedByteArray) -> String:
	if bytes.size() >= 8 and bytes.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return "png"
	if bytes.size() >= 3 and bytes[0] == 255 and bytes[1] == 216 and bytes[2] == 255:
		return "jpeg"
	return ""

func import_avatar_bytes(bytes: PackedByteArray, extension := "") -> bool:
	if bytes.is_empty() or bytes.size() > MAX_FILE_BYTES:
		return _image_error("Picture must be a PNG or JPEG smaller than 4 MB.")
	var kind := extension.to_lower().trim_prefix(".") if not extension.is_empty() else _picture_kind(bytes)
	var dimensions := _png_dimensions(bytes) if kind == "png" else (_jpeg_dimensions(bytes) if kind in ["jpg", "jpeg"] else Vector2i.ZERO)
	if dimensions.x < 1 or dimensions.y < 1 or dimensions.x > MAX_SOURCE_EDGE or dimensions.y > MAX_SOURCE_EDGE:
		return _image_error("Use a valid PNG or JPEG no larger than 4096 × 4096.")
	var image := Image.new()
	var result := image.load_png_from_buffer(bytes) if kind == "png" else image.load_jpg_from_buffer(bytes)
	if result != OK or image.get_width() != dimensions.x or image.get_height() != dimensions.y:
		return _image_error("That picture could not be decoded. Try another PNG or JPEG.")
	image.convert(Image.FORMAT_RGBA8)
	var edge := mini(image.get_width(), image.get_height())
	image = image.get_region(Rect2i((image.get_width() - edge) / 2, (image.get_height() - edge) / 2, edge, edge))
	image.resize(64, 64, Image.INTERPOLATE_LANCZOS)
	var encoded := image.save_png_to_buffer()
	if encoded.size() > MAX_AVATAR_BYTES:
		image.resize(32, 32, Image.INTERPOLATE_LANCZOS)
		encoded = image.save_png_to_buffer()
	if not validate_avatar(encoded):
		return _image_error("This picture is too detailed to share. Try a simpler image.")
	avatar = encoded
	_avatar_revision += 1
	_changed()
	return true

static func valid_picture_path(path: String, native_picker := false, android := false) -> bool:
	if path.is_empty() or path.length() > 4096:
		return false
	for index in range(path.length()):
		if path.unicode_at(index) < 32:
			return false
	if path.contains("://"):
		return android and native_picker and path.begins_with("content://") and path.length() > 10
	return true

func import_avatar_file(path: String, native_picker := false) -> bool:
	var document := path.begins_with("content://")
	if not valid_picture_path(path, native_picker, OS.get_name() == "Android") or (not document and not FileAccess.file_exists(path)):
		return _image_error("Choose a picture stored on this device.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > MAX_FILE_BYTES:
		return _image_error("Picture must be readable and smaller than 4 MB.")
	# Android's native document picker returns an opaque content URI rather
	# than a filename. FileAccess uses its locally granted document handler;
	# decode the bounded PNG/JPEG signature without trusting a URI extension.
	return import_avatar_bytes(file.get_buffer(file.get_length()), "" if document else path.get_extension())

func _image_error(message: String) -> bool:
	status = message
	state_changed.emit()
	return false

func save_now() -> void:
	if _bound_id.is_empty() or _bound_id != _current_id():
		return
	if not _cloud_ready:
		_cloud_retry_requested = true
		await _read_cloud_profile()
		return
	if _saving or not _dirty:
		return
	if _now_ms() < _next_save_ms:
		status = "Profile saved locally · cloud sync is queued."
		state_changed.emit()
		return
	var account := _account()
	if account == null or not account.has_method("client_request") or account.get("busy") == true:
		return
	_saving = true
	var generation := _generation
	var identity := _bound_id
	var revision := _revision
	var name_revision := _name_revision
	var avatar_revision := _avatar_revision
	_next_save_ms = _now_ms() + SAVE_INTERVAL_MS
	var payload := {"Data": {CLOUD_KEY: JSON.stringify(_encoded())}, "Permission": "Public"}
	var reply: Dictionary = await account.call("client_request", "UpdateUserData", payload)
	if generation != _generation or identity != _current_id():
		return
	_saving = false
	if reply.get("ok", false):
		_dirty = revision != _revision
		if _name_revision == name_revision:
			_name_revision = 0
		if _avatar_revision == avatar_revision:
			_avatar_revision = 0
		_persist_local()
		status = "Profile synced to your account." if not _dirty else "Profile saved locally · newer changes are waiting to sync."
	else:
		status = "Profile saved on this device. Cloud sync failed; retry from Profile."
	state_changed.emit()

func _process(_delta: float) -> void:
	if not _cloud_ready and not _cloud_loading and (_dirty or _cloud_retry_requested) and _now_ms() >= _next_read_ms:
		_read_cloud_profile()
	elif _cloud_ready and _dirty and not _saving and _now_ms() >= _next_save_ms:
		save_now()
