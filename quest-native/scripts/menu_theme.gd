extends RefCounted

# Original forest palette shared by the native desktop overlays.
const FOREST := Color("10291f")
const CARD := Color("183b2d")
const CREAM := Color("f4f2df")
const MUTED := Color("b0c5ad")
const GREEN := Color("b4d778")
const ORANGE := Color("efb66d")

static func style(color: Color, border := Color.TRANSPARENT, radius := 14) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	box.set_corner_radius_all(radius)
	return box

static func label(parent: Node, text: String, size: int, color := CREAM, wrap := false) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wrap: result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(result)
	return result

static func button(owner: Node, parent: Container, caption: String, action: String, primary := false, compact := false) -> Button:
	var result := Button.new()
	result.text = caption
	result.custom_minimum_size.y = 36 if compact else (48 if primary else 42)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_font_size_override("font_size", 14 if compact else 17)
	var fill := GREEN if primary else Color("284d3b")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var color: Color = fill
		if state == "hover": color = fill.lightened(0.12)
		elif state == "pressed": color = ORANGE if action.begins_with("mode:") else fill.darkened(0.12)
		elif state == "disabled": color = Color("203c2c")
		elif state == "focus": color = Color.TRANSPARENT
		var box := style(color, GREEN if state == "focus" else Color.TRANSPARENT, 10)
		if state == "normal" and not primary:
			box.border_color = Color("47614d")
			box.set_border_width_all(1)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		result.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		result.add_theme_color_override(state, FOREST if primary else CREAM)
	result.add_theme_color_override("font_pressed_color", FOREST if primary or action.begins_with("mode:") else CREAM)
	result.add_theme_color_override("font_disabled_color", Color("7f9984"))
	result.pressed.connect(func(): owner.call("_dispatch", action))
	parent.add_child(result)
	owner.get("_desktop_buttons")[action] = result
	return result

static func field(control: LineEdit) -> void:
	control.custom_minimum_size.y = 42
	control.add_theme_font_size_override("font_size", 16)
	control.add_theme_color_override("font_color", CREAM)
	control.add_theme_color_override("font_placeholder_color", MUTED.darkened(0.2))
	control.add_theme_color_override("caret_color", GREEN)
	for state in ["normal", "focus", "read_only"]:
		var box := style(Color("102c20"), GREEN if state == "focus" else Color("3a5944"), 10)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 7
		box.content_margin_bottom = 7
		control.add_theme_stylebox_override(state, box)

static func world_text(panel: Node3D) -> void:
	# World labels need a larger angular size than desktop text in a headset.
	for child in panel.get_children():
		if child is Label3D:
			child.pixel_size = 0.0015
			child.outline_size = 3

static func desktop_frame(owner: Node, name: String, layer: int, width: float) -> Dictionary:
	var canvas := CanvasLayer.new()
	canvas.name = name
	canvas.layer = layer
	owner.add_child(canvas)
	var root := Control.new()
	canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.055, 0.04, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	root.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 24
	scroll.offset_top = 24
	scroll.offset_right = -24
	scroll.offset_bottom = -24
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(center)
	var panel := PanelContainer.new()
	var panel_style := style(CARD, Color("557557"), 22)
	panel_style.shadow_color = Color(0.005, 0.02, 0.012, 0.32)
	panel_style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var viewport := owner.get_viewport()
	var adapt := func():
		if is_instance_valid(owner) and is_instance_valid(panel):
			# Reserve space for the vertical scrollbar so narrow cards keep both
			# rounded edges and controls inside the scroll viewport.
			panel.custom_minimum_size.x = maxf(240, minf(width, viewport.get_visible_rect().size.x - 64))
	viewport.size_changed.connect(adapt)
	owner.tree_exiting.connect(func():
		if viewport.size_changed.is_connected(adapt): viewport.size_changed.disconnect(adapt))
	adapt.call()
	return {"canvas": canvas, "root": root, "panel": panel, "content": content, "scroll": scroll}
