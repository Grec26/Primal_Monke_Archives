extends RefCounted

# A local map is plain bounded data. Imported maps never contain scripts,
# resource paths, credentials, or nodes from another project.
signal changed

const FORMAT_VERSION := 1
const MAX_OBJECTS := 128
const MAX_JSON_BYTES := 256 * 1024
const MAX_HISTORY := 64
const MAX_ID := 1000000
const KINDS := ["platform", "block", "wall", "tree", "rock"]
const COLORS := [Color("4d8b65"), Color("a98254"), Color("89938b"), Color("66a8be"), Color("d7b46e"), Color("c97c6a")]
const DEFAULT_SIZES := {
	"platform": Vector3(3, 0.3, 3), "block": Vector3(2, 2, 2),
	"wall": Vector3(4, 3, 0.5), "tree": Vector3(1, 5, 1), "rock": Vector3(2, 1.5, 2),
}
const DEFAULT_COLORS := {"platform": 1, "block": 3, "wall": 2, "tree": 0, "rock": 2}

var storage_directory := "user://maps"
var status := "Create a local map, then save it to a map slot."
var revision := 0
var current_slot := 0
var data: Dictionary:
	get: return _data.duplicate(true)
var dirty: bool:
	get: return _fingerprint(_data) != _saved_fingerprint
var object_count: int:
	get: return _data.objects.size()
var can_undo: bool:
	get: return not _undo.is_empty()
var can_redo: bool:
	get: return not _redo.is_empty()

var _data := {"version": FORMAT_VERSION, "name": "Untitled map", "objects": []}
var _saved_fingerprint := ""
var _saved_data: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _validation_error := ""

func _init() -> void:
	_saved_fingerprint = _fingerprint(_data)
	_saved_data = data

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func vector(value: Variant) -> Variant:
	if value is Vector3:
		return value if value.is_finite() else null
	if value is Array and value.size() == 3 and number(value[0]) and number(value[1]) and number(value[2]):
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return null

static func array_vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func get_object(id: int) -> Dictionary:
	for object in _data.objects:
		if object.id == id: return object.duplicate(true)
	return {}

func has_object(id: int) -> bool:
	return not get_object(id).is_empty()

func set_name(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.is_empty() or clean.length() > 48 or _contains_control(clean):
		return _fail("Map names need 1–48 characters, without line breaks.")
	var next := data
	next.name = clean
	return _edit(next, "Map renamed.")

func add_object(kind: String, position: Vector3) -> int:
	if not KINDS.has(kind):
		_fail("Choose a supported object from the palette.")
		return -1
	if object_count >= MAX_OBJECTS:
		_fail("Map limit reached: 128 objects.")
		return -1
	var id := 1
	for object in _data.objects: id = maxi(id, int(object.id) + 1)
	if id > MAX_ID:
		_fail("No more object IDs are available in this map.")
		return -1
	var next := data
	next.objects.append({"id": id, "kind": kind, "position": array_vector(position), "size": array_vector(DEFAULT_SIZES[kind]), "yaw": 0.0, "color": DEFAULT_COLORS[kind]})
	return id if _edit(next, "Placed %s." % kind) else -1

func update_object(id: int, fields: Dictionary) -> bool:
	var next := data
	var index := _index(id)
	if index < 0: return _fail("Select an object first.")
	for key in fields:
		if key not in ["position", "size", "yaw", "color"]:
			return _fail("That object property cannot be edited.")
		var value: Variant = fields[key]
		if key == "position" or key == "size":
			value = vector(value)
			if value == null: return _fail("Object coordinates must be three finite numbers.")
			value = array_vector(value)
		next.objects[index][key] = value
	return _edit(next, "Object updated.")

func delete_object(id: int) -> bool:
	var index := _index(id)
	if index < 0: return _fail("Select an object first.")
	var next := data
	next.objects.remove_at(index)
	return _edit(next, "Object deleted.")

func duplicate_object(id: int) -> int:
	var object := get_object(id)
	if object.is_empty():
		_fail("Select an object first.")
		return -1
	if object_count >= MAX_OBJECTS:
		_fail("Map limit reached: 128 objects.")
		return -1
	var next_id := 1
	for entry in _data.objects: next_id = maxi(next_id, int(entry.id) + 1)
	if next_id > MAX_ID:
		_fail("No more object IDs are available in this map.")
		return -1
	# Keep a duplicate at the same safe transform; the creator selects it so
	# moving it is deliberate, rather than silently crossing a map boundary.
	object.id = next_id
	var next := data
	next.objects.append(object)
	return next_id if _edit(next, "Object duplicated. Move the selected copy.") else -1

func undo() -> bool:
	if _undo.is_empty(): return _fail("Nothing to undo.")
	_redo.append(data)
	_data = _undo.pop_back()
	_notify("Change undone.")
	return true

func redo() -> bool:
	if _redo.is_empty(): return _fail("Nothing to redo.")
	_undo.append(data)
	_data = _redo.pop_back()
	_notify("Change redone.")
	return true

func discard_changes() -> bool:
	_data = _saved_data.duplicate(true)
	_saved_fingerprint = _fingerprint(_data)
	_undo.clear()
	_redo.clear()
	_notify("Discarded unsaved changes.")
	return true

func new_map(preset: String = "blank") -> bool:
	var next := {"version": FORMAT_VERSION, "name": "Untitled map", "objects": []}
	if preset == "parkour":
		next.name = "Canopy circuit"
		for index in range(10):
			var height := 0.18 + float(index) * 0.3
			next.objects.append(_object(index + 1, "platform", Vector3(-6, height, -1.5 + index * 0.8), Vector3(2, 0.3, 1.2), 1))
		next.objects.append(_object(11, "platform", Vector3(-2.7, 2.9, 6.2), Vector3(5, 0.3, 2), 4))
		next.objects.append(_object(12, "block", Vector3(4, 0.6, 2), Vector3(2, 1.2, 2), 3))
		next.objects.append(_object(13, "rock", Vector3(6.5, 0.75, 5.5), Vector3(2.5, 1.5, 2.5), 2))
	elif preset == "climb":
		next.name = "Climbing garden"
		for index in range(5):
			next.objects.append(_object(index + 1, "wall", Vector3(-7 + index * 3.5, 2, 7), Vector3(2, 4, 0.5), index % 6))
			next.objects.append(_object(index + 6, "platform", Vector3(-7 + index * 3.5, 4.15, 7), Vector3(2.4, 0.3, 2), 1))
		for index in range(4):
			next.objects.append(_object(index + 11, "tree", Vector3(-9 + index * 6, 2.5, 1), Vector3(2, 5, 2), 0))
	elif preset != "blank": return _fail("Choose Blank, Parkour, or Climb.")
	var clean := validate_data(next)
	if clean.is_empty(): return _fail(_validation_error)
	_data = clean
	_undo.clear()
	_redo.clear()
	current_slot = 0
	_saved_data = {"version": FORMAT_VERSION, "name": "Untitled map", "objects": []}
	_saved_fingerprint = ""
	_notify("New %s map. Save it to keep your work." % preset)
	return true

func export_json() -> String:
	return JSON.stringify(_data, "\t")

func import_json(text: String) -> bool:
	if text.to_utf8_buffer().size() > MAX_JSON_BYTES: return _fail("Map files must be smaller than 256 KiB.")
	var parser := JSON.new()
	if parser.parse(text) != OK: return _fail("That map file is not valid JSON.")
	var clean := validate_data(parser.data)
	if clean.is_empty(): return _fail(_validation_error)
	return _edit(clean, "Map imported. Save it to keep your work.")

func save_slot(slot: int) -> bool:
	var path := _slot_path(slot)
	if path.is_empty(): return false
	var clean := validate_data(_data)
	if clean.is_empty(): return _fail(_validation_error)
	if DirAccess.make_dir_recursive_absolute(storage_directory) != OK:
		return _fail("The map folder could not be created.")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _fail("The map slot could not be written.")
	file.store_string(JSON.stringify(clean, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return _fail("The map slot could not be written completely.")
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return _fail("The map slot could not be replaced.")
	_saved_fingerprint = _fingerprint(_data)
	_saved_data = data
	current_slot = slot
	_notify("Saved %s to slot %s." % [_data.name, slot])
	return true

func load_slot(slot: int) -> bool:
	var clean := _read_slot(slot)
	if clean.is_empty(): return false
	_data = clean
	_undo.clear()
	_redo.clear()
	current_slot = slot
	_saved_fingerprint = _fingerprint(_data)
	_saved_data = data
	_notify("Loaded %s from slot %s." % [_data.name, slot])
	return true

func slot_summary(slot: int) -> String:
	var original_status := status
	var path := _slot_path(slot)
	if path.is_empty():
		status = original_status
		return "Unavailable slot"
	if not FileAccess.file_exists(path):
		status = original_status
		return "Slot %s · Empty" % slot
	var clean := _read_slot(slot)
	status = original_status
	return "Slot %s · %s · %s objects" % [slot, clean.name, clean.objects.size()] if not clean.is_empty() else "Slot %s · Unreadable map" % slot

func validate_data(value: Variant) -> Dictionary:
	_validation_error = "The map data has an unsupported format."
	if not value is Dictionary or not _exact_keys(value, ["version", "name", "objects"]): return {}
	if not number(value.version) or float(value.version) != FORMAT_VERSION: return {}
	if not value.name is String or value.name.strip_edges().is_empty() or value.name.length() > 48 or _contains_control(value.name):
		_validation_error = "Map names need 1–48 characters, without line breaks."
		return {}
	if not value.objects is Array or value.objects.size() > MAX_OBJECTS:
		_validation_error = "A map can contain at most 128 objects."
		return {}
	var result := {"version": FORMAT_VERSION, "name": value.name.strip_edges(), "objects": []}
	var ids := {}
	for entry in value.objects:
		if not entry is Dictionary or not _exact_keys(entry, ["id", "kind", "position", "size", "yaw", "color"]): return {}
		if not number(entry.id) or float(entry.id) != floor(float(entry.id)) or entry.id < 1 or entry.id > MAX_ID or ids.has(int(entry.id)):
			_validation_error = "Every object needs a unique whole-number ID."
			return {}
		if not entry.kind is String or not KINDS.has(entry.kind):
			_validation_error = "The map contains an unsupported object."
			return {}
		var position: Variant = vector(entry.position)
		var size: Variant = vector(entry.size)
		if position == null or size == null or not number(entry.yaw) or not number(entry.color) or float(entry.color) != floor(float(entry.color)) or entry.color < 0 or entry.color >= COLORS.size():
			_validation_error = "Object coordinates, rotation, and color must be valid finite numbers."
			return {}
		if absf(position.x) > 14 or absf(position.z) > 14 or position.y < 0 or position.y > 12 or size.x < 0.25 or size.y < 0.25 or size.z < 0.25 or size.x > 8 or size.y > 8 or size.z > 8:
			_validation_error = "Keep centers within ±14 m, height 0–12 m, and sizes 0.25–8 m."
			return {}
		var yaw := fposmod(float(entry.yaw), 360.0)
		var angle := deg_to_rad(yaw)
		var half_x: float = (absf(cos(angle)) * size.x + absf(sin(angle)) * size.z) * 0.5
		var half_z: float = (absf(sin(angle)) * size.x + absf(cos(angle)) * size.z) * 0.5
		if absf(position.x) + half_x > 15.0 or absf(position.z) + half_z > 15.0:
			_validation_error = "The entire object must stay inside the arena walls."
			return {}
		# Conservative rectangle-versus-circle test keeps the floor spawn and
		# headset headroom clear even when the object rotates.
		var nearest_x: float = maxf(absf(position.x) - half_x, 0.0)
		var nearest_z: float = maxf(absf(position.z + 5.0) - half_z, 0.0)
		if position.y - size.y * 0.5 < 3.0 and position.y + size.y * 0.5 > 0.0 and Vector2(nearest_x, nearest_z).length() < 1.4:
			_validation_error = "Keep the marked spawn area clear, including 3 m of headroom."
			return {}
		ids[int(entry.id)] = true
		result.objects.append({"id": int(entry.id), "kind": entry.kind, "position": array_vector(position), "size": array_vector(size), "yaw": yaw, "color": int(entry.color)})
	_validation_error = ""
	return result

func _edit(next: Dictionary, message: String) -> bool:
	var clean := validate_data(next)
	if clean.is_empty(): return _fail(_validation_error)
	if _fingerprint(clean) == _fingerprint(_data):
		status = "No change."
		return true
	_undo.append(data)
	if _undo.size() > MAX_HISTORY: _undo.pop_front()
	_redo.clear()
	_data = clean
	_notify(message)
	return true

func _index(id: int) -> int:
	for index in range(_data.objects.size()):
		if _data.objects[index].id == id: return index
	return -1

func _read_slot(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if path.is_empty(): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("That map slot is empty or unavailable.")
		return {}
	if file.get_length() > MAX_JSON_BYTES:
		file.close()
		_fail("Map files must be smaller than 256 KiB.")
		return {}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		_fail("That saved map is damaged. Choose another slot.")
		return {}
	var clean := validate_data(parser.data)
	if clean.is_empty(): _fail(_validation_error)
	return clean

func _slot_path(slot: int) -> String:
	if slot < 1 or slot > 6:
		_fail("Choose a map slot from 1 to 6.")
		return ""
	return storage_directory.path_join("slot-%s.json" % slot)

func _fingerprint(value: Dictionary) -> String:
	return JSON.stringify(value)

func _notify(message: String) -> void:
	status = message
	revision += 1
	changed.emit()

func _fail(message: String) -> bool:
	status = message
	return false

static func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

static func _contains_control(value: String) -> bool:
	for index in range(value.length()):
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127: return true
	return false

static func _object(id: int, kind: String, position: Vector3, size: Vector3, color: int) -> Dictionary:
	return {"id": id, "kind": kind, "position": array_vector(position), "size": array_vector(size), "yaw": 0.0, "color": color}
