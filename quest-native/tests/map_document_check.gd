extends SceneTree

const Document = preload("res://scripts/map_document.gd")
const Renderer = preload("res://scripts/custom_map.gd")
const Player = preload("res://scripts/arm_player.gd")

var checks := 0
var failures := 0
var scratch := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	scratch = "/tmp/primal-monke-map-document-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	test_edits_and_history()
	test_validation()
	test_persistence()
	test_discarded_work()
	await test_renderer()
	await test_preset_playability()
	for slot in range(1, 7):
		DirAccess.remove_absolute(scratch.path_join("slot-%s.json" % slot))
		DirAccess.remove_absolute(scratch.path_join("slot-%s.json.tmp" % slot))
	DirAccess.remove_absolute(scratch)
	print("Map document checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_edits_and_history() -> void:
	var doc := Document.new()
	doc.storage_directory = scratch
	check(doc.object_count == 0 and not doc.dirty and not doc.can_undo, "initial map is a clean empty document")
	var id: int = doc.add_object("platform", Vector3(0, 0.15, 0))
	check(id == 1 and doc.object_count == 1 and doc.dirty and doc.can_undo, "placing a safe platform changes the document and enables undo")
	var snapshot: Dictionary = doc.data
	snapshot.objects[0].position[0] = 900
	check(doc.get_object(id).position[0] == 0, "returned data snapshots cannot mutate the model")
	var object: Dictionary = doc.get_object(id)
	object.kind = "script"
	check(doc.get_object(id).kind == "platform", "returned object snapshots cannot mutate the model")
	check(doc.update_object(id, {"position": Vector3(3, 0.15, 1), "size": [4, 0.3, 2], "yaw": -90, "color": 4}), "one edit can safely move resize rotate and recolor a selected object")
	check(doc.get_object(id).yaw == 270.0 and Document.vector(doc.get_object(id).position).is_equal_approx(Vector3(3, 0.15, 1)), "object rotation normalizes while transforms retain their values")
	check(doc.undo() and Document.vector(doc.get_object(id).position).is_equal_approx(Vector3(0, 0.15, 0)), "undo restores the full former transform")
	check(doc.redo() and Document.vector(doc.get_object(id).size).is_equal_approx(Vector3(4, 0.3, 2)), "redo restores the full new transform")
	check(doc.save_slot(1) and not doc.dirty and doc.current_slot == 1, "saving records the current clean revision")
	check(doc.update_object(id, {"color": 3}) and doc.dirty, "an edit after save marks the map dirty")
	check(doc.undo() and not doc.dirty, "undoing exactly to the saved contents clears dirty state")
	check(doc.redo() and doc.dirty, "redoing away from saved contents restores dirty state")
	check(doc.undo() and doc.update_object(id, {"color": 5}) and not doc.can_redo, "new work after undo discards only the redo branch")
	var copy_id: int = doc.duplicate_object(id)
	check(copy_id == 2 and doc.get_object(copy_id).position == doc.get_object(id).position, "duplication preserves a safe complete transform with a new ID")
	check(doc.delete_object(id) and not doc.has_object(id) and doc.has_object(copy_id), "deleting the selected object preserves other objects")
	check(doc.undo() and doc.has_object(id), "deleting an object is undoable")
	var previous := doc.export_json()
	check(not doc.delete_object(900) and not doc.update_object(900, {"color": 0}) and doc.duplicate_object(900) == -1 and doc.export_json() == previous, "unknown object IDs fail without corrupting map contents")
	check(not doc.update_object(id, {"script": "res://malicious.gd"}) and doc.export_json() == previous, "edits cannot introduce executable resource properties")
	check(doc.set_name("  My climbing map  ") and doc.data.name == "My climbing map", "map naming trims surrounding space")
	check(not doc.set_name("") and not doc.set_name("x".repeat(49)) and not doc.set_name("line\nbreak"), "map naming rejects empty long and control-character names")
	var bounded := Document.new()
	var bounded_id: int = bounded.add_object("block", Vector3(0, 1, 0))
	for index in range(75): bounded.update_object(bounded_id, {"color": index % 6})
	var undo_count := 0
	while bounded.undo(): undo_count += 1
	check(undo_count == Document.MAX_HISTORY and bounded.has_object(bounded_id), "undo history stays bounded to 64 recent edits")
	var redo_count := 0
	while bounded.redo(): redo_count += 1
	check(redo_count == Document.MAX_HISTORY, "redo preserves exactly the bounded undo history")
	for preset in ["blank", "parkour", "climb"]:
		check(doc.new_map(preset) and not doc.can_undo and not doc.can_redo and doc.dirty and doc.current_slot == 0, "new %s preset resets history and marks its unsaved contents" % preset)
		check(not doc.validate_data(doc.data).is_empty(), "%s preset satisfies every imported-map bound" % preset)
		for entry in doc.data.objects:
			check(Vector2(float(entry.position[0]), float(entry.position[2]) + 5.0).length() >= 1.4, "%s preset object %s preserves the spawn area" % [preset, entry.id])
	previous = doc.export_json()
	check(not doc.new_map("unknown") and previous == doc.export_json(), "unknown presets leave current work intact")

func test_validation() -> void:
	var doc := Document.new()
	var id: int = doc.add_object("block", Vector3(0, 1, 0))
	var valid: Dictionary = doc.data
	check(not doc.validate_data(valid).is_empty(), "a valid runtime map passes the shared import validator")
	var bad_maps: Array = [null, [], "map", 1, true, {}, {"version": 1, "name": "Map", "objects": {}}]
	for index in range(bad_maps.size()): check(doc.validate_data(bad_maps[index]).is_empty(), "invalid document type %s is rejected" % index)
	for version in [0, 2, "1", true, NAN, INF]:
		var bad := valid.duplicate(true)
		bad.version = version
		check(doc.validate_data(bad).is_empty(), "invalid format version %s is rejected" % str(version))
	for field in ["version", "name", "objects"]:
		var bad := valid.duplicate(true)
		bad.erase(field)
		check(doc.validate_data(bad).is_empty(), "missing document field %s is rejected" % field)
	var extra := valid.duplicate(true)
	extra.script = "res://scripts/forest.gd"
	check(doc.validate_data(extra).is_empty(), "imported maps cannot introduce executable root properties")
	for object_field in ["id", "kind", "position", "size", "yaw", "color"]:
		var bad := valid.duplicate(true)
		bad.objects[0].erase(object_field)
		check(doc.validate_data(bad).is_empty(), "missing object field %s is rejected" % object_field)
	for bad_id in [0, -1, 1.5, 1000001, "1", true, NAN, INF]:
		var bad := valid.duplicate(true)
		bad.objects[0].id = bad_id
		check(doc.validate_data(bad).is_empty(), "invalid object ID %s is rejected" % str(bad_id))
	var repeated := valid.duplicate(true)
	repeated.objects.append(repeated.objects[0].duplicate(true))
	check(doc.validate_data(repeated).is_empty(), "duplicate object IDs are rejected")
	for kind in ["script", "res://forest.tscn", "", 4, null]:
		var bad := valid.duplicate(true)
		bad.objects[0].kind = kind
		check(doc.validate_data(bad).is_empty(), "unsupported palette kind %s is rejected" % str(kind))
	for field in ["position", "size"]:
		for bad_vector in [null, "0,1,0", [0, 1], [0, 1, 0, 2], [false, 1, 0], ["0", 1, 0], [NAN, 1, 0], [0, INF, 0]]:
			var bad := valid.duplicate(true)
			bad.objects[0][field] = bad_vector
			check(doc.validate_data(bad).is_empty(), "invalid %s coordinates %s are rejected" % [field, str(bad_vector)])
	for position in [[14.1, 1, 0], [0, -0.1, 0], [0, 12.1, 0], [0, 1, -14.1]]:
		check(not doc.update_object(id, {"position": position}), "out-of-range object center %s is rejected" % str(position))
	for size in [[0.24, 1, 1], [1, 8.1, 1], [1, 1, -1]]:
		check(not doc.update_object(id, {"size": size}), "out-of-range object size %s is rejected" % str(size))
	for yaw in ["90", true, NAN, INF]: check(not doc.update_object(id, {"yaw": yaw}), "invalid yaw %s is rejected" % str(yaw))
	for color in [-1, 6, 1.5, "1", true, NAN, INF]: check(not doc.update_object(id, {"color": color}), "invalid color %s is rejected" % str(color))
	check(not doc.update_object(id, {"position": [14, 1, 0], "size": [4, 2, 2]}), "bounds use complete object extents rather than only its center")
	check(not doc.update_object(id, {"position": [14, 1, 0], "size": [2, 2, 2], "yaw": 45}), "rotated horizontal extents cannot cross arena walls")
	check(not doc.update_object(id, {"position": [0, 1, -5]}), "objects cannot block the player spawn")
	check(not doc.update_object(id, {"position": [0, 2.8, -5], "size": [2, 0.3, 2]}), "low ceilings cannot block spawn headroom")
	check(doc.update_object(id, {"position": [0, 3.2, -5], "size": [2, 0.3, 2]}), "safe structures above spawn headroom are allowed")
	check(not doc.update_object(id, {"position": [2.3, 1, -5], "size": [2, 2, 2]}), "spawn clearance includes a capsule margin around object edges")
	check(doc.update_object(id, {"position": [2.5, 1, -5], "size": [2, 2, 2]}), "objects outside the marked spawn margin are allowed")
	var full := Document.new()
	var unique := {}
	for index in range(Document.MAX_OBJECTS):
		var placed: int = full.add_object("block", Vector3(0, 1, 0))
		if placed > 0: unique[placed] = true
	check(unique.size() == 128 and full.object_count == 128, "a full 128-object map gives every object a unique positive ID")
	check(full.add_object("block", Vector3(0, 1, 0)) == -1 and full.duplicate_object(1) == -1 and full.object_count == 128, "object and duplicate creation respect the 128-object cap")
	var oversized := full.data
	oversized.objects.append(oversized.objects[0].duplicate(true))
	check(doc.validate_data(oversized).is_empty(), "imported data cannot bypass the object cap")
	var before := doc.export_json()
	check(not doc.import_json("x".repeat(Document.MAX_JSON_BYTES + 1)) and doc.export_json() == before, "oversized imported text fails without replacing current work")
	check(not doc.import_json("{bad json") and doc.export_json() == before, "malformed JSON fails without replacing current work")
	check(doc.import_json(JSON.stringify(valid)) and doc.get_object(id).position == [0.0, 1.0, 0.0], "valid JSON safely restores an imported map")
	check(not doc.import_json(JSON.stringify(extra)), "JSON cannot import an executable resource path")

func test_persistence() -> void:
	var doc := Document.new()
	doc.storage_directory = scratch
	check(doc.new_map("parkour") and doc.set_name("Saved parkour"), "a playable preset can be named before saving")
	var expected := doc.export_json()
	for slot in range(1, 7):
		check(doc.save_slot(slot) and FileAccess.file_exists(scratch.path_join("slot-%s.json" % slot)), "slot %s writes to a fixed local filename" % slot)
		check(not FileAccess.file_exists(scratch.path_join("slot-%s.json.tmp" % slot)), "slot %s does not leave an unfinished save file" % slot)
		check(doc.slot_summary(slot).contains("Saved parkour") and doc.slot_summary(slot).contains("13 objects"), "slot %s summarizes the actual saved map" % slot)
	check(doc.set_name("Updated parkour") and doc.save_slot(1), "atomic save can replace an existing slot")
	var restored := Document.new()
	restored.storage_directory = scratch
	check(restored.load_slot(1) and restored.data.name == "Updated parkour" and not restored.dirty and restored.current_slot == 1, "another document restores the replaced map as clean")
	check(restored.load_slot(2) and restored.export_json() == expected, "different save slots preserve independent map contents")
	var before := restored.export_json()
	for slot in [-100, 0, 7, 999]:
		check(not restored.save_slot(slot) and not restored.load_slot(slot) and restored.export_json() == before, "invalid slot %s cannot change files or current work" % slot)
	var invalid := FileAccess.open(scratch.path_join("slot-3.json"), FileAccess.WRITE)
	invalid.store_string("{damaged")
	invalid.close()
	check(not restored.load_slot(3) and restored.export_json() == before and restored.status.contains("damaged"), "damaged local JSON produces a useful error and preserves work")
	check(restored.slot_summary(3).contains("Unreadable") and restored.export_json() == before, "damaged slot summaries do not mutate the active map")
	invalid = FileAccess.open(scratch.path_join("slot-4.json"), FileAccess.WRITE)
	invalid.store_string(" ".repeat(Document.MAX_JSON_BYTES + 1))
	invalid.close()
	check(not restored.load_slot(4) and restored.export_json() == before and restored.status.contains("256"), "oversized disk maps are rejected before loading the file into the document")
	DirAccess.remove_absolute(scratch.path_join("slot-5.json"))
	check(not restored.load_slot(5) and restored.slot_summary(5).contains("Empty") and restored.export_json() == before, "missing map slots are clearly reported and preserve active work")
	var status_before: String = restored.status
	restored.slot_summary(2)
	check(restored.status == status_before, "reading a slot summary does not overwrite important save or load feedback")
	var on_disk := FileAccess.get_file_as_string(scratch.path_join("slot-2.json"))
	check(not on_disk.contains("password") and not on_disk.contains("ticket") and not on_disk.contains("PlayFab") and not on_disk.contains("res://"), "saved map files contain bounded geometry rather than account data or resources")

func test_renderer() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var doc := Document.new()
	var ids := []
	for index in range(Document.KINDS.size()):
		var kind: String = Document.KINDS[index]
		var size: Vector3 = Document.DEFAULT_SIZES[kind]
		ids.append(doc.add_object(kind, Vector3(-10 + index * 5, size.y * 0.5, 3)))
	var renderer := Renderer.new()
	renderer.document = doc
	world.add_child(renderer)
	for index in range(3): await physics_frame
	check(renderer.solids.size() == 10, "custom renderer builds four walls and the five palette objects with a separate solid tree crown")
	check(renderer.get_node_or_null("ForestFloor") == null, "custom renderer preserves the shared root floor instead of duplicating it")
	for index in range(Document.KINDS.size()):
		var origin := Vector3(-10 + index * 5, 10, 3)
		var query := PhysicsRayQueryParameters3D.create(origin, Vector3(origin.x, -1, origin.z), 1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider.get_meta("map_object_id", -1) == ids[index], "%s collider is pickable by its editable object ID" % Document.KINDS[index])
		if not hit.is_empty():
			check(hit.collider.collision_layer == 1 and hit.collider.collision_mask == 0, "%s surfaces share hand and desktop collision layer 1" % Document.KINDS[index])
			check(hit.collider.get_node("CollisionShape3D").get_meta("map_object_id", -1) == ids[index], "%s collision children carry the same picking ID" % Document.KINDS[index])
	for solid in renderer.solids:
		check(solid.get_child_count() == 2, "rendered collider %s contains one visible mesh and one shape" % solid.name)
		check(not solid.get_node("CollisionShape3D").shape is ConcavePolygonShape3D, "rendered collider %s uses safe convex collision" % solid.name)
	renderer.set_selected(ids[0])
	check(renderer._selection.visible and renderer._selection.mesh.get_surface_count() == 1 and renderer._selection.get_child_count() == 0, "selected objects have a visible outline without extra collision nodes")
	check(renderer._selection.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 24, "selection outline contains exactly the twelve bounding-box edges")
	renderer.set_selected(999)
	check(not renderer._selection.visible and renderer.selected_id == -1, "unknown object selections hide the outline safely")
	renderer.set_selected(ids[0])
	check(doc.update_object(ids[0], {"position": [-9, 0.15, 4], "yaw": 45}), "document can move and rotate a rendered platform")
	for index in range(3): await physics_frame
	check(renderer._selection.visible and renderer._selection.position.is_equal_approx(Vector3(-9, 0.15, 4)) and is_equal_approx(renderer._selection.rotation.y, PI / 4), "document signals update visible geometry and selected outline transform")
	check(renderer.solids.size() == 10, "repeated rendering replaces old colliders rather than accumulating them")
	var old_applied: Dictionary = renderer._applied.duplicate(true)
	check(not renderer.apply_data({"version": 99}) and renderer._applied == old_applied and renderer.solids.size() == 10, "renderer validates external data before replacing the active playable geometry")
	check(doc.delete_object(ids[0]), "selected rendered object can be deleted")
	for index in range(3): await physics_frame
	check(renderer.selected_id == -1 and not renderer._selection.visible and renderer.solids.size() == 9, "deletion removes both collision and stale selection")
	var boundary_query := PhysicsRayQueryParameters3D.create(Vector3(0, 2, 14), Vector3(0, 2, 18), 1)
	var boundary_hit := world.get_world_3d().direct_space_state.intersect_ray(boundary_query)
	check(not boundary_hit.is_empty() and not boundary_hit.collider.has_meta("map_object_id"), "fixed arena boundary walls stay solid and cannot be selected as editable objects")
	renderer.set_active(false)
	for index in range(3): await physics_frame
	check(not renderer.visible and world.get_world_3d().direct_space_state.intersect_ray(boundary_query).is_empty(), "inactive custom maps hide and disable their boundary physics")
	check(doc.update_object(ids[1], {"color": 5}), "inactive custom-map document can still be edited")
	for index in range(3): await physics_frame
	var disabled := true
	for solid in renderer.solids: disabled = disabled and solid.collision_layer == 0
	check(disabled and not renderer.visible and world.get_world_3d().direct_space_state.intersect_ray(boundary_query).is_empty(), "rebuilding an inactive map preserves disabled collisions and visibility")
	renderer.set_active(true)
	for index in range(3): await physics_frame
	check(renderer.visible and not world.get_world_3d().direct_space_state.intersect_ray(boundary_query).is_empty(), "activating the map restores its actual solid boundary")
	world.queue_free()
	await process_frame

func test_discarded_work() -> void:
	var doc := Document.new()
	doc.storage_directory = scratch
	var id: int = doc.add_object("platform", Vector3(0, 0.15, 0))
	doc.set_name("Saved draft")
	doc.save_slot(6)
	var saved := doc.export_json()
	var saved_file := FileAccess.get_file_as_string(scratch.path_join("slot-6.json"))
	doc.update_object(id, {"position": [4, 0.15, 2], "yaw": 45})
	doc.set_name("Changes to discard")
	check(doc.dirty and doc.can_undo and doc.export_json() != saved, "changed geometry and name are distinguishable from the saved baseline")
	check(doc.discard_changes() and doc.export_json() == saved and not doc.dirty and doc.current_slot == 6, "discard restores the saved geometry and name as a clean document")
	check(not doc.can_undo and not doc.can_redo, "discard removes history that could revive the discarded changes")
	check(FileAccess.get_file_as_string(scratch.path_join("slot-6.json")) == saved_file, "discarding edits never modifies the saved slot")
	var restored := Document.new()
	restored.storage_directory = scratch
	restored.load_slot(6)
	restored.update_object(id, {"color": 5})
	check(restored.discard_changes() and restored.export_json() == saved and not restored.dirty, "loaded documents discard to their loaded baseline too")
	doc.new_map("climb")
	doc.set_name("Unsaved garden")
	check(doc.dirty and doc.object_count > 0 and doc.current_slot == 0, "a new unsaved preset has a distinct draft with no saved slot")
	check(doc.discard_changes() and doc.object_count == 0 and doc.data.name == "Untitled map" and not doc.dirty and doc.current_slot == 0, "discarding a new unsaved draft restores a clean blank map")
	check(not doc.can_undo and not doc.can_redo and FileAccess.get_file_as_string(scratch.path_join("slot-6.json")) == saved_file, "discarded new maps cannot be recovered from history and preserve existing files")
	var initial := Document.new()
	initial.add_object("block", Vector3(0, 1, 0))
	check(initial.discard_changes() and initial.object_count == 0 and not initial.dirty, "a first unsaved edit discards to the initial clean document")

func capsule_clear(world: Node3D, feet: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 1.65
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = feet + Vector3(0, 0.845, 0)
	query.collision_mask = 1
	query.margin = 0.002
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func key_state(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func drive_player(player: CharacterBody3D, goal: Vector3, jump: bool) -> bool:
	var reached := false
	for frame in range(420):
		await physics_frame
		var offset := Vector2(goal.x - player.position.x, goal.z - player.position.z)
		key_state(KEY_A, offset.x < -0.12)
		key_state(KEY_D, offset.x > 0.12)
		key_state(KEY_W, offset.y < -0.12)
		key_state(KEY_S, offset.y > 0.12)
		key_state(KEY_SPACE, jump and offset.length() > 0.16)
		player._physics_process(1.0 / float(Engine.physics_ticks_per_second))
		if offset.length() < 0.18 and absf(player.position.y - goal.y) < 0.15 and player.is_on_floor():
			reached = true
			break
	for key in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE]: key_state(key, false)
	if not reached: print("Preset route stopped at %s; expected %s" % [player.position, goal])
	return reached

func test_preset_playability() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.collision_mask = 0
	floor.position.y = -0.5
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(32, 1, 32)
	floor_shape.shape = floor_box
	floor.add_child(floor_shape)
	world.add_child(floor)
	var doc := Document.new()
	doc.new_map("parkour")
	var renderer := Renderer.new()
	renderer.document = doc
	world.add_child(renderer)
	for frame in range(3): await physics_frame
	check(capsule_clear(world, Vector3(0, 0.1, -5)), "parkour preset keeps the actual desktop capsule spawn clear")
	var clear_steps := true
	var real_steps := true
	var previous_top := 0.0
	var reachable_risers := true
	for object in doc.data.objects:
		if object.id > 10: continue
		var position: Vector3 = Document.vector(object.position)
		var size: Vector3 = Document.vector(object.size)
		var top := position.y + size.y * 0.5
		var stand := Vector3(position.x, top + 0.03, position.z - 0.15)
		clear_steps = clear_steps and capsule_clear(world, stand)
		var ray := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.2, stand - Vector3.UP * 0.1, 1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
		real_steps = real_steps and not hit.is_empty() and hit.collider.get_meta("map_object_id", -1) == object.id
		reachable_risers = reachable_risers and top > previous_top and top - previous_top <= 0.4
		previous_top = top
	check(clear_steps and real_steps and reachable_risers, "all ten parkour treads provide real surfaces, clear capsule headroom, and jumpable rises")
	var player := Player.new()
	player.set_physics_process(false)
	player.collision_layer = 0
	player.collision_mask = 1
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 1.65
	collision.shape = capsule
	collision.position.y = 0.845
	player.capsule_node = collision
	player.add_child(collision)
	var head := XRCamera3D.new()
	head.position.y = 1.65
	player.head = head
	player.add_child(head)
	player.position = Vector3(-6, 0.1, -2.8)
	world.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	check(await drive_player(player, Vector3(-6, 3.03, 5.7), true), "shipping desktop movement can climb the entire parkour staircase using movement and jump input")
	check(await drive_player(player, Vector3(-2.7, 3.05, 5.7), false), "shipping desktop movement can walk from the top tread onto the connected rest deck")
	player.queue_free()
	await process_frame
	doc.new_map("climb")
	for frame in range(3): await physics_frame
	check(capsule_clear(world, Vector3(0, 0.1, -5)), "climbing preset keeps the actual desktop capsule spawn clear")
	var landings_clear := true
	var hand_contacts := true
	var hand_probe := Player.new()
	hand_probe.set_physics_process(false)
	world.add_child(hand_probe)
	hand_probe.set_physics_process(false)
	for object in doc.data.objects:
		var position: Vector3 = Document.vector(object.position)
		if object.kind == "platform":
			landings_clear = landings_clear and capsule_clear(world, position + Vector3.UP * 0.2)
		if object.kind == "wall":
			var contact: Dictionary = hand_probe.resolve_hand(position + Vector3(0, 0, -1), position + Vector3(0, 0, 1))
			hand_contacts = hand_contacts and contact.contact
	check(landings_clear and hand_contacts, "climbing preset walls support actual VR hand sweeps and clear standing space on all top landings")
	world.queue_free()
	await process_frame
