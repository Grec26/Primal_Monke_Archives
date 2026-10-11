extends "res://scripts/lobby_menu.gd"

const MenuTheme = preload("res://scripts/menu_theme.gd")
var creator: Node3D
var _sidebar: PanelContainer
var _tabs: TabContainer
var _summary: Label
var _selected_summary: Label
var _name_edit: LineEdit
var _slot_picker: OptionButton
var _slot_label: Label
var _fields: Dictionary = {}
var _updating_fields := false
var _confirm: VBoxContainer
var _confirm_text: Label
var _world_title: Label3D
var _world_selected: Label3D
var _world_feedback: Label3D
var _world_pages: Dictionary = {}
var _page := 0

func _init() -> void:
	toggle_key = KEY_NONE
	toggle_hand = -1
	allow_during_creation = true
	panel_size = Vector2(2.0, 2.15)

func _input(_event: InputEvent) -> void:
	# The creator owns F8 and right B, including returning from a playtest.
	pass

func set_open(value: bool) -> void:
	if not is_instance_valid(creator): return
	value = value and bool(creator.get("active")) and not bool(creator.get("playtesting"))
	super.set_open(value)
	if value: refresh_status()

func toggle() -> void:
	if is_instance_valid(creator): creator.call("set_open", not is_open)

func pointer_over_ui() -> bool:
	if not is_open or _sidebar == null: return false
	if _sidebar.get_global_rect().has_point(get_viewport().get_mouse_position()): return true
	return _confirm.visible and _confirm.get_global_rect().has_point(get_viewport().get_mouse_position())

func _document() -> RefCounted:
	return creator.get("document") as RefCounted if is_instance_valid(creator) else null

func _action_enabled(action: String) -> bool:
	if _document() == null or not bool(creator.call("_editing_allowed")): return false
	if not str(creator.get("pending_action")).is_empty(): return action in ["confirm_save", "confirm_discard", "confirm_cancel"]
	if action in ["confirm_save", "confirm_discard", "confirm_cancel"]: return false
	if action == "undo": return bool(_document().get("can_undo"))
	if action == "redo": return bool(_document().get("can_redo"))
	if action in ["duplicate", "delete", "rotate", "color"] or action.begins_with("move:") or action.begins_with("size:"):
		return int(creator.get("selected_id")) >= 0
	if action == "next_object": return int(_document().get("object_count")) > 0
	if action == "close": return _is_xr()
	return true

func _dispatch(action: String) -> void:
	if not _action_enabled(action): return
	if is_instance_valid(game) and game.has_method("play_ui_sound") and not _is_xr(): game.call("play_ui_sound", "click")
	if action.begins_with("kind:"): creator.call("choose_kind", action.trim_prefix("kind:"))
	elif action.begins_with("move:") or action.begins_with("size:"):
		var parts := action.split(":")
		var amount := float(parts[2]) * float(creator.get("grid_step"))
		creator.call("nudge" if parts[0] == "move" else "resize_axis", int(parts[1]), amount)
	else:
		match action:
			"select": creator.call("set_select_mode")
			"next_object": creator.call("cycle_selection")
			"undo", "redo": creator.call("history_action", action)
			"duplicate": creator.call("duplicate_selected")
			"delete": creator.call("delete_selected")
			"rotate": creator.call("rotate_selected")
			"color": creator.call("color_selected")
			"grid": creator.call("cycle_grid")
			"save":
				if not _commit_name(): return
				creator.call("save")
			"load", "exit": creator.call("request_action", action)
			"new_blank": creator.call("request_action", "new:blank")
			"new_parkour": creator.call("request_action", "new:parkour")
			"new_climb": creator.call("request_action", "new:climb")
			"playtest":
				if not _commit_name(): return
				creator.call("start_playtest")
			"slot_previous": creator.call("select_slot", 6 if int(creator.get("selected_slot")) <= 1 else int(creator.get("selected_slot")) - 1)
			"slot_next": creator.call("select_slot", 1 if int(creator.get("selected_slot")) >= 6 else int(creator.get("selected_slot")) + 1)
			"page_previous": _page = (_page + 3) % 4
			"page_next": _page = (_page + 1) % 4
			"confirm_save":
				if not _commit_name(): return
				creator.call("resolve_pending", "save")
			"confirm_discard": creator.call("resolve_pending", "discard")
			"confirm_cancel": creator.call("resolve_pending", "cancel")
			"close": creator.call("set_open", false)
	refresh_status()

func _commit_name() -> bool:
	if _name_edit != null and _document() != null:
		var data: Dictionary = _document().get("data")
		if _name_edit.text != str(data.get("name", "")): return bool(creator.call("rename_map", _name_edit.text))
	return true

func refresh_status() -> void:
	if _document() == null: return
	var snapshot := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [_document().get("revision"), creator.get("status"), creator.get("selected_id"), creator.get("selected_kind"), creator.get("placing"), creator.get("grid_step"), creator.get("selected_slot"), creator.get("pending_action"), _page, _is_xr(), creator.get("active")]
	if snapshot == _state_snapshot: return
	_state_snapshot = snapshot
	var data: Dictionary = _document().get("data")
	var object: Dictionary = creator.call("selected_object")
	var dirty := bool(_document().get("dirty"))
	_status_text = str(creator.get("status"))
	var count := int(_document().get("object_count"))
	var map_name := str(data.get("name", "Untitled map"))
	var summary := "%s\n%d / 128 objects  ·  %s" % [map_name, count, "Unsaved changes" if dirty else "Saved / unchanged"]
	var selected := "Nothing selected · Use Select, then click an object."
	if not object.is_empty():
		selected = "%s #%d\nPosition %s\nSize %s · Yaw %.0f°" % [str(object.get("kind", "Object")).capitalize(), int(object.get("id", -1)), _format_vector(object.get("position", [])), _format_vector(object.get("size", [])), float(object.get("yaw", 0))]
	if _summary != null: _summary.text = summary
	if _selected_summary != null: _selected_summary.text = selected
	if _desktop_status != null: _desktop_status.text = _status_text
	var pending := not str(creator.get("pending_action")).is_empty()
	if _confirm != null:
		_confirm.visible = pending
		_confirm_text.text = "You have unsaved changes. Save to slot %d before continuing?" % int(creator.get("selected_slot"))
		_tabs.visible = not pending
	if _name_edit != null and not _name_edit.has_focus(): _name_edit.text = map_name
	if _slot_picker != null: _slot_picker.select(int(creator.get("selected_slot")) - 1)
	if _slot_label != null: _slot_label.text = _slot_description()
	_updating_fields = true
	for key in _fields:
		var field: SpinBox = _fields[key]
		field.editable = not object.is_empty() and not pending
		if object.is_empty(): continue
		if field.get_line_edit().has_focus(): continue
		var parts: PackedStringArray = str(key).split(":")
		if parts[0] == "yaw": field.value = float(object.get("yaw", 0))
		else:
			var value: Vector3 = creator.call("_vector", object.get(parts[0], [0, 0, 0]))
			field.value = value[int(parts[1])]
	_updating_fields = false
	for action in _desktop_buttons:
		var button: Button = _desktop_buttons[action]
		button.disabled = not _action_enabled(action)
		if action == "grid": button.text = "Grid · %.2f m" % float(creator.get("grid_step"))
		if action == "select": button.text = "Select ●" if not bool(creator.get("placing")) else "Select"
		if action.begins_with("kind:"):
			var kind: String = action.trim_prefix("kind:")
			button.text = kind.capitalize() + (" ●" if bool(creator.get("placing")) and str(creator.get("selected_kind")) == kind else "")
	_update_world(summary, selected, pending)
	_update_button_colors()

func _slot_description() -> String:
	var slot: int = int(creator.get("selected_slot"))
	var summary: Variant = _document().call("slot_summary", slot)
	if summary is Dictionary:
		if summary.get("exists", false): return "Slot %d · %s" % [slot, str(summary.get("name", "Saved map"))]
		return "Slot %d · Empty" % slot
	return str(summary)

func _format_vector(value: Variant) -> String:
	var vector: Vector3 = creator.call("_vector", value)
	return "%.2f, %.2f, %.2f" % [vector.x, vector.y, vector.z]

func _inspector_changed(value: float, key: String) -> void:
	if _updating_fields or not is_instance_valid(creator): return
	var object: Dictionary = creator.call("selected_object")
	if object.is_empty(): return
	var parts := key.split(":")
	if parts[0] == "yaw": creator.call("update_selected", {"yaw": value})
	else:
		var vector: Vector3 = creator.call("_vector", object.get(parts[0], [0, 0, 0]))
		vector[int(parts[1])] = value
		creator.call("update_selected", {parts[0]: vector})
	refresh_status()

func _create_desktop_menu() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "MapCreatorOverlay"
	_canvas.layer = 40
	add_child(_canvas)
	var root := Control.new()
	root.name = "TransparentEditorRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sidebar = PanelContainer.new()
	_sidebar.name = "EditorSidebar"
	_sidebar.add_theme_stylebox_override("panel", MenuTheme.style(MenuTheme.CARD, Color("456747"), 16))
	root.add_child(_sidebar)
	_sidebar.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_sidebar.offset_top = 12
	_sidebar.offset_bottom = -12
	_sidebar.offset_right = -12
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_sidebar.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	MenuTheme.label(content, "PRIMAL MONKE  /  STUDIO", 12, MenuTheme.ORANGE, true)
	MenuTheme.label(content, "Map creator", 28)
	_summary = MenuTheme.label(content, "", 14, MenuTheme.GREEN, true)
	MenuTheme.label(content, "Local maps · PC + VR playtest", 12, MenuTheme.MUTED, true)
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 14)
	content.add_child(_tabs)
	var build := _tab("Build")
	MenuTheme.label(build, "Choose a piece, then click a surface.", 13, MenuTheme.MUTED, true)
	var palette := GridContainer.new()
	palette.columns = 2
	palette.add_theme_constant_override("h_separation", 6)
	palette.add_theme_constant_override("v_separation", 6)
	build.add_child(palette)
	for kind in ["platform", "block", "wall", "tree", "rock"]: MenuTheme.button(self, palette, kind.capitalize(), "kind:" + kind, false, true)
	MenuTheme.button(self, palette, "Select", "select", false, true)
	MenuTheme.button(self, build, "", "grid", false, true)
	MenuTheme.label(build, "Green preview: valid · Red: outside bounds or inside the protected spawn area.", 12, MenuTheme.MUTED, true)
	var history := HBoxContainer.new()
	build.add_child(history)
	MenuTheme.button(self, history, "Undo", "undo", false, true)
	MenuTheme.button(self, history, "Redo", "redo", false, true)
	var inspector := _tab("Edit")
	_selected_summary = MenuTheme.label(inspector, "", 13, MenuTheme.GREEN, true)
	MenuTheme.button(self, inspector, "Select next object", "next_object", false, true)
	_inspector_fields(inspector, "Position", "position")
	_inspector_fields(inspector, "Size", "size")
	var yaw_row := HBoxContainer.new()
	inspector.add_child(yaw_row)
	MenuTheme.label(yaw_row, "Yaw", 14)
	_add_spin(yaw_row, "yaw", 0, 359.99, 15)
	var edit_actions := GridContainer.new()
	edit_actions.columns = 2
	edit_actions.add_theme_constant_override("h_separation", 6)
	edit_actions.add_theme_constant_override("v_separation", 6)
	inspector.add_child(edit_actions)
	MenuTheme.button(self, edit_actions, "Duplicate", "duplicate", false, true)
	MenuTheme.button(self, edit_actions, "Delete", "delete", false, true)
	MenuTheme.button(self, edit_actions, "Rotate +45°", "rotate", false, true)
	MenuTheme.button(self, edit_actions, "Change color", "color", false, true)
	var files := _tab("Maps")
	MenuTheme.label(files, "Map name", 14)
	_name_edit = LineEdit.new()
	_name_edit.name = "MapName"
	_name_edit.max_length = 48
	MenuTheme.field(_name_edit)
	_name_edit.text_submitted.connect(func(_value: String): _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	files.add_child(_name_edit)
	MenuTheme.label(files, "Saved on this device", 14)
	_slot_picker = OptionButton.new()
	_slot_picker.name = "MapSlot"
	_slot_picker.custom_minimum_size.y = 40
	for slot in range(1, 7): _slot_picker.add_item("Slot %d" % slot)
	_slot_picker.item_selected.connect(func(index: int): creator.call("select_slot", index + 1))
	files.add_child(_slot_picker)
	_slot_label = MenuTheme.label(files, "", 13, MenuTheme.MUTED, true)
	var saves := HBoxContainer.new()
	files.add_child(saves)
	MenuTheme.button(self, saves, "Save", "save", true, true)
	MenuTheme.button(self, saves, "Load", "load", false, true)
	MenuTheme.label(files, "Start a map", 14)
	MenuTheme.button(self, files, "Blank arena", "new_blank", false, true)
	MenuTheme.button(self, files, "Parkour starter", "new_parkour", false, true)
	MenuTheme.button(self, files, "Climbing garden", "new_climb", false, true)
	MenuTheme.label(files, "Up to 128 pieces. Your saved map is a local file; multiplayer uses the forest.", 12, MenuTheme.MUTED, true)
	_confirm = VBoxContainer.new()
	_confirm.name = "UnsavedConfirmation"
	_confirm.add_theme_constant_override("separation", 8)
	content.add_child(_confirm)
	_confirm_text = MenuTheme.label(_confirm, "", 17, MenuTheme.ORANGE, true)
	MenuTheme.button(self, _confirm, "Save and continue", "confirm_save", true)
	MenuTheme.button(self, _confirm, "Discard and continue", "confirm_discard")
	MenuTheme.button(self, _confirm, "Keep editing", "confirm_cancel")
	_confirm.visible = false
	_desktop_status = MenuTheme.label(content, "", 13, MenuTheme.ORANGE, true)
	MenuTheme.button(self, content, "Playtest map", "playtest", true)
	MenuTheme.button(self, content, "Back to main menu", "exit", false, true)
	MenuTheme.label(content, "WASD move · Q/E height\nRight mouse look · Wheel zoom\nR rotate · Delete remove · Ctrl+D duplicate\nCtrl+Z undo · Ctrl+S save · F8 hide tools", 12, MenuTheme.MUTED, true)
	var adapt := func():
		if not is_instance_valid(_sidebar): return
		_sidebar.offset_left = -clampf(get_viewport().get_visible_rect().size.x * 0.4, 245, 350) - 12
	var viewport := get_viewport()
	viewport.size_changed.connect(adapt)
	tree_exiting.connect(func():
		if viewport.size_changed.is_connected(adapt): viewport.size_changed.disconnect(adapt))
	adapt.call()

func _tab(title: String) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.name = title
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 8)
	_tabs.add_child(panel)
	return panel

func _inspector_fields(parent: VBoxContainer, caption: String, key: String) -> void:
	MenuTheme.label(parent, caption, 14)
	for index in range(3):
		var row := HBoxContainer.new()
		parent.add_child(row)
		var label := MenuTheme.label(row, ["X", "Y", "Z"][index], 13, MenuTheme.MUTED)
		label.size_flags_horizontal = Control.SIZE_FILL
		label.custom_minimum_size.x = 20
		_add_spin(row, "%s:%d" % [key, index], 0.25 if key == "size" else (-14 if index != 1 else 0), 8 if key == "size" else (12 if index == 1 else 14), 0.05)

func _add_spin(parent: HBoxContainer, key: String, minimum: float, maximum: float, step: float) -> void:
	var field := SpinBox.new()
	field.name = key.replace(":", "_")
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(100, 36)
	field.value_changed.connect(func(value: float): _inspector_changed(value, key))
	parent.add_child(field)
	_fields[key] = field

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldMapCreator"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, panel_size, -0.035, MenuTheme.FOREST)
	_world_title = _world_label("MAP CREATOR", Vector2(0, 0.93), 43)
	_world_status = _world_label("", Vector2(0, 0.75), 25)
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_status.width = 1240
	_world_selected = _world_label("", Vector2(0, 0.57), 25)
	_world_selected.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_selected.width = 1240
	var pages := [
		[["PLATFORM", "kind:platform"], ["BLOCK", "kind:block"], ["WALL", "kind:wall"], ["TREE", "kind:tree"], ["ROCK", "kind:rock"], ["SELECT", "select"], ["NEXT OBJECT", "next_object"], ["GRID", "grid"]],
		[["X −", "move:0:-1"], ["X +", "move:0:1"], ["Y −", "move:1:-1"], ["Y +", "move:1:1"], ["Z −", "move:2:-1"], ["Z +", "move:2:1"], ["DUPLICATE", "duplicate"], ["DELETE", "delete"]],
		[["WIDTH −", "size:0:-1"], ["WIDTH +", "size:0:1"], ["HEIGHT −", "size:1:-1"], ["HEIGHT +", "size:1:1"], ["DEPTH −", "size:2:-1"], ["DEPTH +", "size:2:1"], ["ROTATE +45°", "rotate"], ["COLOR", "color"]],
		[["SLOT −", "slot_previous"], ["SLOT +", "slot_next"], ["SAVE", "save"], ["LOAD", "load"], ["BLANK MAP", "new_blank"], ["PARKOUR MAP", "new_parkour"], ["PLAYTEST", "playtest"], ["EXIT CREATOR", "exit"]]
	]
	for page in range(pages.size()):
		for index in range(pages[page].size()):
			var entry: Array = pages[page][index]
			_world_button(entry[0], entry[1], Vector2(-0.46 if index % 2 == 0 else 0.46, 0.34 - float(index / 2) * 0.22), Vector2(0.85, 0.16))
			_world_pages[entry[1]] = page
	_world_button("UNDO", "undo", Vector2(-0.46, -0.58), Vector2(0.85, 0.13))
	_world_button("REDO", "redo", Vector2(0.46, -0.58), Vector2(0.85, 0.13))
	_world_button("CLIMBING GARDEN", "new_climb", Vector2(0, -0.58), Vector2(1.7, 0.13))
	_world_pages["new_climb"] = 3
	_world_button("PREV", "page_previous", Vector2(-0.67, -0.79), Vector2(0.34, 0.13))
	_world_button("BUILD IN WORLD", "close", Vector2(0, -0.79), Vector2(0.93, 0.13), MenuTheme.GREEN.darkened(0.35))
	_world_button("NEXT", "page_next", Vector2(0.67, -0.79), Vector2(0.34, 0.13))
	_world_button("SAVE + CONTINUE", "confirm_save", Vector2(0, 0.21), Vector2(1.7, 0.17))
	_world_button("DISCARD + CONTINUE", "confirm_discard", Vector2(0, -0.06), Vector2(1.7, 0.17))
	_world_button("KEEP EDITING", "confirm_cancel", Vector2(0, -0.33), Vector2(1.7, 0.17))
	_world_feedback = _world_label("", Vector2(0, -0.965), 19)
	_world_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_feedback.width = 1240
	MenuTheme.world_text(_world_panel)
	_pointer = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.009
	dot.height = 0.018
	_pointer.mesh = dot
	_pointer.material_override = _material(MenuTheme.GREEN)
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pointer)

func _update_world(summary: String, selected: String, pending: bool) -> void:
	if _world_title == null: return
	var page_names := ["BUILD", "MOVE", "SIZE & COLOR", "SAVE & PLAY"]
	_world_title.text = "UNSAVED CHANGES" if pending else "MAP CREATOR · %s %d/4" % [page_names[_page], _page + 1]
	_world_status.text = "Save to slot %d before continuing?" % int(creator.get("selected_slot")) if pending else summary.replace("\n", " · ")
	if pending: _world_selected.text = "Choose how to continue."
	elif _page == 3: _world_selected.text = _slot_description()
	else:
		var lines := selected.split("\n")
		_world_selected.text = lines[0]
		if lines.size() > 2 and _page in [1, 2]: _world_selected.text += "\n" + lines[1 if _page == 1 else 2]
	_world_feedback.text = _status_text + "\nRight B: tools · Hidden panel: aim + trigger\nLeft stick: move · Right stick: height"
	for button in _world_buttons:
		var action: String = button.action
		var confirmation := action.begins_with("confirm_")
		var visible_action := confirmation if pending else (not confirmation and (not _world_pages.has(action) or int(_world_pages[action]) == _page))
		if not pending and action in ["undo", "redo"] and _page == 3: visible_action = false
		_set_world_action_visible(action, visible_action)
		if action == "grid": button.label.text = "GRID %.2f m" % float(creator.get("grid_step"))
		if action == "select": button.label.text = "SELECT ●" if not bool(creator.get("placing")) else "SELECT"
		if action.begins_with("kind:"):
			var kind: String = action.trim_prefix("kind:")
			button.label.text = kind.to_upper() + (" ●" if bool(creator.get("placing")) and str(creator.get("selected_kind")) == kind else "")
