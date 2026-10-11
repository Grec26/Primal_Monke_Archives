extends Node3D

# Maps are local, bounded documents. Editing never changes a connected lobby.
const Menu = preload("res://scripts/map_creator_menu.gd")
const KINDS := ["platform", "block", "wall", "tree", "rock"]
const DEFAULT_SIZES := [Vector3(3, 0.3, 3), Vector3(2, 2, 2), Vector3(4, 3, 0.5), Vector3(1, 5, 1), Vector3(2, 1.5, 2)]
var game: Node3D
var document: RefCounted
var renderer: Node3D
var menu: Node3D
var active := false
var playtesting := false
var is_open := false
var selected_id := -1
var selected_kind := "platform"
var placing := false
var grid_step := 0.5
var selected_slot := 1
var status := "Build a local map, save it, then try it in Playtest."
var pending_action := ""
var _camera: Camera3D
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _world_cursor: MeshInstance3D
var _world_ray: MeshInstance3D
var _preview_position := Vector3.ZERO
var _preview_valid := false
var _validated_preview_valid := false
var _preview_revision := -1
var _preview_kind := ""
var _validated_preview_position := Vector3.INF
var _look_held := false
var _vr_trigger_held := true
var _vr_toggle_held := true
var _test_canvas: CanvasLayer
var _test_world_hint: Label3D

func _ready() -> void:
	var data_script: Script = load("res://scripts/map_document.gd")
	var map_script: Script = load("res://scripts/custom_map.gd")
	if data_script == null or map_script == null:
		status = "The map creator could not load its map resources."
		return
	document = data_script.new()
	renderer = map_script.new() as Node3D
	renderer.name = "CreatedMap"
	renderer.call("set_active", false)
	renderer.set("document", document)
	add_child(renderer)
	document.connect("changed", _document_changed)
	_camera = Camera3D.new()
	_camera.name = "EditorCamera"
	_camera.fov = 62
	_camera.near = 0.05
	_camera.far = 100
	add_child(_camera)
	_reset_camera()
	_ghost = MeshInstance3D.new()
	_ghost.name = "PlacementPreview"
	_ghost.mesh = BoxMesh.new()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.albedo_color = Color(0.65, 0.88, 0.45, 0.38)
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost.material_override = _ghost_material
	add_child(_ghost)
	_ghost.visible = false
	_world_cursor = MeshInstance3D.new()
	_world_cursor.name = "EditorAimPoint"
	var cursor_mesh := SphereMesh.new()
	cursor_mesh.radius = 0.018
	cursor_mesh.height = 0.036
	_world_cursor.mesh = cursor_mesh
	var cursor_material := StandardMaterial3D.new()
	cursor_material.albedo_color = Color("d7b46e")
	cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_world_cursor.material_override = cursor_material
	_world_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_world_cursor)
	_world_cursor.visible = false
	_world_ray = MeshInstance3D.new()
	_world_ray.name = "EditorAimRay"
	_world_ray.material_override = cursor_material
	_world_ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_world_ray)
	_world_ray.visible = false
	menu = Menu.new()
	menu.name = "MapCreatorMenu"
	menu.set("game", game)
	menu.set("creator", self)
	add_child(menu)
	_create_test_notice()
	_document_changed()

func _player() -> Node3D:
	return game.get("player") as Node3D if is_instance_valid(game) else null

func _is_xr() -> bool:
	var player := _player()
	return player != null and bool(player.get("xr_running"))

func _editing_allowed() -> bool:
	return active and not playtesting and is_instance_valid(game) and str(game.get("network_mode")) == "offline" and str(game.get("frontend_state")) == "creating"

func begin() -> bool:
	if document == null or not is_instance_valid(game) or not game.has_method("can_open_map_creator") or not bool(game.call("can_open_map_creator")):
		return false
	if active:
		if playtesting: stop_playtest()
		set_open(true)
		return true
	game.call("enter_map_creation")
	if str(game.get("frontend_state")) != "creating": return false
	active = true
	playtesting = false
	pending_action = ""
	renderer.call("set_active", true)
	_document_changed()
	_reset_camera()
	if not _is_xr(): _camera.make_current()
	set_open(true)
	status = "Local map creator · Maps stay on this device."
	_refresh_menu()
	return true

func set_open(value: bool) -> void:
	is_open = value and active and not playtesting
	if is_instance_valid(menu): menu.call("set_open", is_open)
	_look_held = false
	if active and not _is_xr() and not playtesting: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not is_open: _ghost.visible = false

func start_playtest() -> bool:
	if not _editing_allowed() or not pending_action.is_empty(): return false
	set_open(false)
	playtesting = true
	placing = false
	renderer.call("set_selected", -1)
	_ghost.visible = false
	_world_cursor.visible = false
	_world_ray.visible = false
	_camera.clear_current()
	var player := _player()
	if player != null:
		player.call("reset_player")
		var head := player.get("head") as Camera3D
		if head != null: head.make_current()
	game.call("begin_map_playtest")
	if str(game.get("frontend_state")) != "map_playtest":
		playtesting = false
		if not _is_xr(): _camera.make_current()
		set_open(true)
		return false
	_test_canvas.visible = not _is_xr()
	_test_world_hint.visible = _is_xr()
	status = "Playtest · No timer, bots, or XP. F8 / right B returns to the editor."
	return true

func stop_playtest() -> void:
	if not active or not playtesting: return
	playtesting = false
	_test_canvas.visible = false
	_test_world_hint.visible = false
	game.call("end_map_playtest")
	renderer.call("set_selected", selected_id)
	if not _is_xr(): _camera.make_current()
	set_open(true)
	status = "Back in the editor. Your map is unchanged."
	_refresh_menu()

func request_action(action: String) -> bool:
	if not _editing_allowed() or action not in ["exit", "new:blank", "new:parkour", "new:climb", "load"]: return false
	if is_instance_valid(menu) and not bool(menu.call("_commit_name")): return false
	if bool(document.get("dirty")):
		pending_action = action
		status = "Unsaved changes. Save first, discard changes, or cancel."
		set_open(true)
		_refresh_menu()
		return false
	return _perform_pending(action)

func request_exit() -> bool:
	return request_action("exit")

func resolve_pending(choice: String) -> bool:
	if not _editing_allowed() or pending_action.is_empty(): return false
	if choice == "cancel":
		pending_action = ""
		status = "Kept your current map."
		_refresh_menu()
		return true
	if choice == "save" and not save(): return false
	if choice not in ["save", "discard"]: return false
	var action := pending_action
	pending_action = ""
	if choice == "discard" and action == "exit": document.call("discard_changes")
	return _perform_pending(action)

func _perform_pending(action: String) -> bool:
	if action == "exit":
		_finish()
		return true
	if action.begins_with("new:"):
		document.call("new_map", action.trim_prefix("new:"))
		selected_id = -1
		_reset_camera()
		status = str(document.get("status"))
	elif action == "load":
		if not bool(document.call("load_slot", selected_slot)):
			status = str(document.get("status"))
			_refresh_menu()
			return false
		selected_id = -1
		status = "Loaded slot %d. %s" % [selected_slot, str(document.get("status"))]
	_refresh_menu()
	return true

func _finish() -> void:
	active = false
	playtesting = false
	is_open = false
	pending_action = ""
	placing = false
	set_open(false)
	# Collision must leave with the editor, even if its document stays in memory.
	renderer.call("set_active", false)
	_ghost.visible = false
	_world_cursor.visible = false
	_world_ray.visible = false
	_test_canvas.visible = false
	_test_world_hint.visible = false
	_camera.clear_current()
	var player := _player()
	if player != null:
		var head := player.get("head") as Camera3D
		if head != null: head.make_current()
	game.call("finish_map_creation")

func save() -> bool:
	if not _editing_allowed(): return false
	var result := bool(document.call("save_slot", selected_slot))
	status = str(document.get("status"))
	_cue("success" if result else "error")
	_refresh_menu()
	return result

func select_slot(value: int) -> void:
	selected_slot = clampi(value, 1, 6)
	_refresh_menu()

func rename_map(value: String) -> bool:
	if not _editing_allowed() or not pending_action.is_empty(): return false
	var result := bool(document.call("set_name", value))
	status = str(document.get("status"))
	if not result: _cue("error")
	_refresh_menu()
	return result

func choose_kind(kind: String) -> bool:
	if not _editing_allowed() or kind not in KINDS or not pending_action.is_empty(): return false
	selected_kind = kind
	placing = true
	status = "Place %s · Click a surface, or aim + trigger with the VR panel hidden." % kind
	_refresh_menu()
	return true

func set_select_mode() -> void:
	if not _editing_allowed(): return
	placing = false
	_ghost.visible = false
	status = "Select · Click an object, or aim + trigger with the VR panel hidden."
	_refresh_menu()

func place_at_surface(point: Vector3, normal: Vector3 = Vector3.UP) -> int:
	if not _editing_allowed() or not pending_action.is_empty() or not placing or not point.is_finite() or not normal.is_finite(): return -1
	var position := placement_position(point, normal)
	var result := int(document.call("add_object", selected_kind, position))
	if result >= 0:
		select_object(result)
		status = "Placed %s. Keep placing, or switch to Select." % selected_kind
	else: status = str(document.get("status"))
	_cue("click" if result >= 0 else "error")
	_refresh_menu()
	return result

func placement_position(point: Vector3, normal: Vector3) -> Vector3:
	var size: Vector3 = DEFAULT_SIZES[KINDS.find(selected_kind)]
	var n := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var extent := absf(n.x) * size.x + absf(n.y) * size.y + absf(n.z) * size.z
	var position := point + n * (extent * 0.5 + 0.005)
	position.x = snappedf(position.x, grid_step)
	position.z = snappedf(position.z, grid_step)
	# Ground placement keeps short platforms flush with the floor rather than
	# snapping their centers below it. Side placement still snaps vertically.
	if n.y < 0.5: position.y = snappedf(position.y, grid_step)
	else: position.y = snappedf(point.y, grid_step) + size.y * 0.5
	return position

func select_object(id: int) -> bool:
	if not _editing_allowed(): return false
	selected_id = id if bool(document.call("has_object", id)) else -1
	renderer.call("set_selected", selected_id)
	_refresh_menu()
	return selected_id >= 0

func cycle_selection() -> void:
	if not _editing_allowed(): return
	var data: Dictionary = document.get("data")
	var objects: Array = data.get("objects", [])
	if objects.is_empty(): select_object(-1); return
	var next := 0
	for index in range(objects.size()):
		if int(objects[index].get("id", -1)) == selected_id:
			next = (index + 1) % objects.size()
			break
	select_object(int(objects[next].get("id", -1)))

func selected_object() -> Dictionary:
	return document.call("get_object", selected_id) if document != null else {}

func update_selected(fields: Dictionary) -> bool:
	if not _editing_allowed() or not pending_action.is_empty() or selected_id < 0: return false
	var result := bool(document.call("update_object", selected_id, fields))
	status = str(document.get("status"))
	_cue("click" if result else "error")
	_refresh_menu()
	return result

func nudge(axis: int, amount: float) -> bool:
	var object := selected_object()
	if object.is_empty() or axis < 0 or axis > 2 or not is_finite(amount): return false
	var position := _vector(object.get("position", [0, 0, 0]))
	position[axis] += amount
	return update_selected({"position": position})

func resize_axis(axis: int, amount: float) -> bool:
	var object := selected_object()
	if object.is_empty() or axis < 0 or axis > 2 or not is_finite(amount): return false
	var size := _vector(object.get("size", [1, 1, 1]))
	size[axis] += amount
	return update_selected({"size": size})

func rotate_selected(amount: float = 45) -> bool:
	var object := selected_object()
	if object.is_empty() or not is_finite(amount): return false
	return update_selected({"yaw": fposmod(float(object.get("yaw", 0)) + amount, 360.0)})

func color_selected() -> bool:
	var object := selected_object()
	if object.is_empty(): return false
	return update_selected({"color": (int(object.get("color", 0)) + 1) % 6})

func duplicate_selected() -> int:
	if not _editing_allowed() or selected_id < 0 or not pending_action.is_empty(): return -1
	var id := int(document.call("duplicate_object", selected_id))
	if id >= 0: select_object(id)
	status = str(document.get("status"))
	_refresh_menu()
	return id

func delete_selected() -> bool:
	if not _editing_allowed() or selected_id < 0 or not pending_action.is_empty(): return false
	var result := bool(document.call("delete_object", selected_id))
	if result: selected_id = -1
	status = str(document.get("status"))
	_refresh_menu()
	return result

func history_action(action: String) -> bool:
	if not _editing_allowed() or not pending_action.is_empty() or action not in ["undo", "redo"]: return false
	var result := bool(document.call(action))
	status = str(document.get("status"))
	_refresh_menu()
	return result

func cycle_grid() -> void:
	if not _editing_allowed() or not pending_action.is_empty(): return
	var values := [0.25, 0.5, 1.0]
	grid_step = values[(values.find(grid_step) + 1) % values.size()]
	_refresh_menu()

func _vector(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and value.size() == 3: return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

func _document_changed() -> void:
	if not is_instance_valid(renderer) or document == null: return
	if active:
		if not bool(document.call("has_object", selected_id)): selected_id = -1
		renderer.call("set_selected", selected_id)
	_refresh_menu()

func _cue(cue: String) -> void:
	if is_instance_valid(game) and game.has_method("play_ui_sound"): game.call("play_ui_sound", cue)

func _refresh_menu() -> void:
	if is_instance_valid(menu): menu.call("refresh_status")

func _reset_camera() -> void:
	_camera.position = Vector3(18, 22, 25)
	_camera.look_at(Vector3.ZERO, Vector3.UP)

func _input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		if playtesting: stop_playtest()
		else: set_open(not is_open)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _editing_allowed() or _is_xr() or not pending_action.is_empty(): return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_look_held = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _look_held else Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().gui_release_focus()
			_apply_world_ray(_desktop_ray())
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_camera.position += -_camera.global_basis.z * (2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -2)
			_clamp_camera()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _look_held:
		_camera.rotation.y -= event.relative.x * 0.004
		_camera.rotation.x = clampf(_camera.rotation.x - event.relative.y * 0.004, -1.5, 1.5)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and not _typing():
		match event.physical_keycode:
			KEY_DELETE: delete_selected()
			KEY_R: rotate_selected()
			KEY_ESCAPE: set_select_mode(); set_open(true)
			KEY_D:
				if event.ctrl_pressed: duplicate_selected()
			KEY_Z:
				if event.ctrl_pressed: history_action("redo" if event.shift_pressed else "undo")
			KEY_Y:
				if event.ctrl_pressed: history_action("redo")
			KEY_S:
				if event.ctrl_pressed: save()

func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit

func _desktop_ray() -> Dictionary:
	var mouse := get_viewport().get_mouse_position()
	return {"origin": _camera.project_ray_origin(mouse), "direction": _camera.project_ray_normal(mouse)}

func ray_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.01: return {}
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 80, 1)
	return get_world_3d().direct_space_state.intersect_ray(query)

func _apply_world_ray(ray: Dictionary) -> void:
	if ray.is_empty() or not _editing_allowed() or not pending_action.is_empty(): return
	var hit := ray_hit(ray.origin, ray.direction)
	if hit.is_empty(): return
	if placing: place_at_surface(hit.position, hit.normal)
	else:
		var body: Object = hit.collider
		select_object(int(body.get_meta("map_object_id", -1)))

func _process(delta: float) -> void:
	if not active: return
	if _is_xr(): _process_vr(delta)
	elif _editing_allowed():
		if not _typing() and not Input.is_physical_key_pressed(KEY_CTRL):
			var motion := Vector3.ZERO
			if Input.is_physical_key_pressed(KEY_W): motion -= _camera.global_basis.z
			if Input.is_physical_key_pressed(KEY_S): motion += _camera.global_basis.z
			if Input.is_physical_key_pressed(KEY_A): motion -= _camera.global_basis.x
			if Input.is_physical_key_pressed(KEY_D): motion += _camera.global_basis.x
			if Input.is_physical_key_pressed(KEY_Q): motion.y -= 1
			if Input.is_physical_key_pressed(KEY_E): motion.y += 1
			_camera.position += motion.normalized() * delta * (18 if Input.is_physical_key_pressed(KEY_SHIFT) else 9)
			_clamp_camera()
		var over_ui := is_open and bool(menu.call("pointer_over_ui"))
		_update_preview(_desktop_ray() if not over_ui and not _look_held else {})
	if playtesting and _is_xr():
		var player := _player()
		var head := player.get("head") as Node3D if player != null else null
		if head != null:
			_test_world_hint.global_transform = head.global_transform
			_test_world_hint.translate_object_local(Vector3(0, -0.23, -1.2))

func _clamp_camera() -> void:
	_camera.position.x = clampf(_camera.position.x, -35, 35)
	_camera.position.y = clampf(_camera.position.y, 0.4, 40)
	_camera.position.z = clampf(_camera.position.z, -35, 35)

func _update_preview(ray: Dictionary) -> void:
	_ghost.visible = false
	_preview_valid = false
	if not placing or not _editing_allowed() or not pending_action.is_empty() or ray.is_empty(): return
	var hit := ray_hit(ray.origin, ray.direction)
	if hit.is_empty(): return
	_preview_position = placement_position(hit.position, hit.normal)
	var size: Vector3 = DEFAULT_SIZES[KINDS.find(selected_kind)]
	var box := _ghost.mesh as BoxMesh
	box.size = size
	_ghost.global_position = _preview_position
	if _preview_revision != int(document.get("revision")) or _preview_kind != selected_kind or not _validated_preview_position.is_equal_approx(_preview_position):
		var candidate: Dictionary = document.get("data")
		var id := 1
		for object in candidate.objects: id = maxi(id, int(object.id) + 1)
		candidate.objects.append({"id": id, "kind": selected_kind, "position": [_preview_position.x, _preview_position.y, _preview_position.z], "size": [size.x, size.y, size.z], "yaw": 0, "color": [1, 3, 2, 0, 2][KINDS.find(selected_kind)]})
		_validated_preview_valid = not (document.call("validate_data", candidate) as Dictionary).is_empty()
		_preview_revision = int(document.get("revision"))
		_preview_kind = selected_kind
		_validated_preview_position = _preview_position
	_preview_valid = _validated_preview_valid
	_ghost_material.albedo_color = Color(0.65, 0.88, 0.45, 0.4) if _preview_valid else Color(0.95, 0.3, 0.22, 0.45)
	_ghost.visible = true

func _process_vr(delta: float) -> void:
	_world_cursor.visible = false
	_world_ray.visible = false
	var player := _player()
	if player == null: return
	var hands: Variant = player.get("hands")
	if not (hands is Array) or hands.size() < 2: return
	var right := hands[1] as XRController3D
	var left := hands[0] as XRController3D
	if game.get("xr_focused") == false or right == null or not right.get_has_tracking_data():
		_vr_trigger_held = true
		_vr_toggle_held = true
		_ghost.visible = false
		return
	var pressed := right.is_button_pressed("by_button")
	if pressed and not _vr_toggle_held:
		if playtesting: stop_playtest()
		else: set_open(not is_open)
	_vr_toggle_held = pressed
	var trigger := right.is_button_pressed("trigger_click") or right.get_float("trigger") > 0.65
	if _editing_allowed() and not is_open:
		var aim := menu.get("_aim") as XRController3D
		var ray := aim if aim != null and aim.get_has_tracking_data() else right
		var world_ray := {"origin": ray.global_position, "direction": -ray.global_basis.z}
		_update_preview(world_ray)
		var surface := ray_hit(world_ray.origin, world_ray.direction)
		if not surface.is_empty():
			_world_cursor.global_position = surface.position + surface.normal * 0.02
			_world_cursor.visible = true
			var ray_mesh := ImmediateMesh.new()
			ray_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			ray_mesh.surface_add_vertex(to_local(world_ray.origin))
			ray_mesh.surface_add_vertex(to_local(_world_cursor.global_position))
			ray_mesh.surface_end()
			_world_ray.mesh = ray_mesh
			_world_ray.visible = true
		var hand_visuals: Variant = player.get("hand_visuals")
		if hand_visuals is Array:
			for index in range(mini(hand_visuals.size(), hands.size())):
				var hand := hands[index] as XRController3D
				var visual := hand_visuals[index] as MeshInstance3D
				if hand != null and visual != null:
					visual.visible = hand.get_has_tracking_data()
					if visual.visible: visual.global_position = hand.global_position
		if trigger and not _vr_trigger_held: _apply_world_ray(world_ray)
		if left != null and left.get_has_tracking_data() and not _typing():
			var stick := left.get_vector2("primary")
			if stick.length() > 0.18:
				var head := player.get("head") as Node3D
				if head != null:
					var forward := -head.global_basis.z
					forward.y = 0
					forward = forward.normalized()
					var rightward := forward.cross(Vector3.UP)
					player.global_position += (rightward * stick.x + forward * -stick.y) * delta * 3.0
					player.global_position.x = clampf(player.global_position.x, -14 - head.position.x, 14 - head.position.x)
					player.global_position.z = clampf(player.global_position.z, -14 - head.position.z, 14 - head.position.z)
					player.call("reset_tracking_history")
		var height_stick := right.get_vector2("primary")
		if absf(height_stick.y) > 0.25:
			player.global_position.y = clampf(player.global_position.y - height_stick.y * delta * 2.0, 0.1, 12)
			player.call("reset_tracking_history")
	else: _ghost.visible = false
	_vr_trigger_held = trigger

func _create_test_notice() -> void:
	_test_canvas = CanvasLayer.new()
	_test_canvas.name = "MapPlaytestNotice"
	_test_canvas.layer = 45
	add_child(_test_canvas)
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	root.offset_left = 16
	root.offset_top = -54
	root.offset_right = -16
	root.offset_bottom = -12
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_test_canvas.add_child(root)
	var label := Label.new()
	label.text = "LOCAL MAP PLAYTEST · No timer or XP"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color("f4f2df"))
	label.add_theme_color_override("font_shadow_color", Color("10291f"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(label)
	var back := Button.new()
	back.text = "Return to editor · F8"
	back.pressed.connect(stop_playtest)
	root.add_child(back)
	_test_canvas.visible = false
	_test_world_hint = Label3D.new()
	_test_world_hint.text = "MAP PLAYTEST · Right B returns to editor"
	_test_world_hint.font_size = 22
	_test_world_hint.pixel_size = 0.001
	_test_world_hint.no_depth_test = true
	_test_world_hint.outline_size = 4
	add_child(_test_world_hint)
	_test_world_hint.visible = false
