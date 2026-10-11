extends Node3D

signal retry_requested

const FOREST := Color("122b23")
const CARD := Color("1d3b30")
const CREAM := Color("f5f1dd")
const MUTED := Color("afc3a6")
const AMBER := Color("efbe69")
const TIPS := [
	"Use both hands to push against surfaces and climb.",
	"PC and Quest friends can join on the same Wi-Fi.",
	"Map creator lets you build, save and playtest locally.",
	"Voice is off until you choose to enable it."
]

var _shown := false
var _failed := false
var _progress := 0.0
var _message := "Preparing your forest"
var _canvas: CanvasLayer
var _desktop_message: Label
var _desktop_progress: ProgressBar
var _desktop_percentage: Label
var _retry: Button
var _world: Node3D
var _world_message: Label3D
var _world_percentage: Label3D
var _world_hint: Label3D
var _world_fill: MeshInstance3D
var _desktop_tip: Label
var _desktop_panel: PanelContainer
var _desktop_margin: MarginContainer
var _tip_elapsed := 0.0
var _tip_index := 0

func _ready() -> void:
	_create_desktop()
	_create_world()
	_update_content()
	_update_visibility()
	set_process(_shown)

func show_loading(message: String, progress: float = 0.0) -> void:
	_shown = true
	_failed = false
	_message = message
	_progress = clampf(progress, 0.0, 1.0)
	if is_node_ready():
		_update_content()
		_update_visibility()
		set_process(true)

func set_progress(progress: float, message: String = "") -> void:
	_progress = clampf(progress, 0.0, 1.0)
	if not message.is_empty(): _message = message
	if is_node_ready(): _update_content()

func show_error(message: String) -> void:
	_shown = true
	_failed = true
	_message = message
	if is_node_ready():
		_update_content()
		_update_visibility()
		set_process(true)

func hide_loading() -> void:
	_shown = false
	if is_node_ready():
		_update_visibility()
		set_process(false)

func _style(color: Color, radius: int = 18, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.border_color = border
	return style

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _icon_texture() -> Texture2D:
	return load(str(ProjectSettings.get_setting("application/config/icon", "res://icon.svg"))) as Texture2D

func _create_desktop() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 80
	add_child(_canvas)
	var background := ColorRect.new()
	background.color = FOREST
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(center)
	var panel := PanelContainer.new()
	_desktop_panel = panel
	panel.custom_minimum_size = Vector2(580, 420)
	panel.add_theme_stylebox_override("panel", _style(CARD, 28, Color("43624a")))
	center.add_child(panel)
	var margin := MarginContainer.new()
	_desktop_margin = margin
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var icon := TextureRect.new()
	icon.texture = _icon_texture()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(88, 88)
	column.add_child(icon)
	column.add_child(_label("PRIMAL MONKE", 34, CREAM))
	column.add_child(_label("FOREST  /  TAG  /  TOGETHER", 12, AMBER))
	var space := Control.new()
	space.custom_minimum_size.y = 7
	column.add_child(space)
	_desktop_message = _label(_message, 19, CREAM)
	_desktop_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_message.custom_minimum_size.y = 44
	column.add_child(_desktop_message)
	_desktop_progress = ProgressBar.new()
	_desktop_progress.custom_minimum_size.y = 7
	_desktop_progress.show_percentage = false
	_desktop_progress.add_theme_stylebox_override("background", _style(Color("345344"), 4))
	_desktop_progress.add_theme_stylebox_override("fill", _style(AMBER, 4))
	column.add_child(_desktop_progress)
	_desktop_percentage = _label("0%", 14, MUTED)
	column.add_child(_desktop_percentage)
	_retry = Button.new()
	_retry.text = "Try again"
	_retry.custom_minimum_size.y = 44
	_retry.add_theme_stylebox_override("normal", _style(AMBER, 12))
	_retry.add_theme_stylebox_override("hover", _style(Color("ffd286"), 12))
	_retry.add_theme_color_override("font_color", FOREST)
	_retry.add_theme_font_size_override("font_size", 18)
	_retry.pressed.connect(func(): retry_requested.emit())
	column.add_child(_retry)
	_desktop_tip = _label(TIPS[0], 13, MUTED)
	_desktop_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_tip.custom_minimum_size.y = 36
	column.add_child(_desktop_tip)
	get_viewport().size_changed.connect(_adapt_desktop)
	_adapt_desktop()

func _adapt_desktop() -> void:
	if _desktop_panel == null: return
	var viewport_size := get_viewport().get_visible_rect().size
	_desktop_panel.custom_minimum_size.x = clampf(viewport_size.x - 40.0, 260.0, 580.0)
	var spacing := 20 if viewport_size.x < 640 else 36
	for side in ["left", "right", "top", "bottom"]:
		_desktop_margin.add_theme_constant_override("margin_" + side, spacing)

func _world_quad(size: Vector2, location: Vector3, color: Color, priority: int = 0) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = location
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = priority
	material.no_depth_test = true
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(visual)
	return visual

func _world_label(text: String, location: Vector3, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = location
	label.font_size = size
	label.pixel_size = 0.0015
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = true
	label.render_priority = 4
	_world.add_child(label)
	return label

func _create_world() -> void:
	_world = Node3D.new()
	_world.name = "HeadsetLoadingPanel"
	_world.position = Vector3(0, 0, -1.6)
	add_child(_world)
	_world_quad(Vector2(1.52, 1.02), Vector3.ZERO, FOREST, 0)
	_world_quad(Vector2(1.46, 0.96), Vector3(0, 0, 0.002), CARD, 1)
	var icon := Sprite3D.new()
	icon.texture = _icon_texture()
	icon.pixel_size = 0.192 / maxf(1.0, maxf(icon.texture.get_width(), icon.texture.get_height())) if icon.texture != null else 0.003
	icon.position = Vector3(0, 0.30, 0.008)
	icon.no_depth_test = true
	icon.transparent = true
	icon.render_priority = 3
	_world.add_child(icon)
	_world_label("PRIMAL MONKE", Vector3(0, 0.11, 0.008), 48, CREAM)
	_world_label("FOREST  /  TAG  /  TOGETHER", Vector3(0, 0.018, 0.008), 18, AMBER)
	_world_message = _world_label(_message, Vector3(0, -0.11, 0.008), 25, CREAM)
	_world_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_message.width = 760
	_world_quad(Vector2(1.13, 0.013), Vector3(0, -0.225, 0.006), Color("345344"), 2)
	_world_fill = _world_quad(Vector2(1.13, 0.013), Vector3(-0.565, -0.225, 0.009), AMBER, 3)
	_world_percentage = _world_label("0%", Vector3(0, -0.29, 0.008), 22, MUTED)
	_world_hint = _world_label("Swing in. Play together.", Vector3(0, -0.41, 0.008), 18, MUTED)

func _update_content() -> void:
	_desktop_message.text = _message
	_world_message.text = _message
	_desktop_progress.value = _progress * 100.0
	var percentage := "%d%%" % roundi(_progress * 100.0)
	_desktop_percentage.text = percentage
	_world_percentage.text = percentage
	_world_fill.scale.x = maxf(_progress, 0.001)
	_world_fill.position.x = -0.565 + 0.565 * _progress
	_world_fill.visible = not _failed and _progress > 0.0
	_desktop_progress.visible = not _failed
	_desktop_percentage.visible = not _failed
	_world_percentage.visible = not _failed
	_retry.visible = _failed
	_world_hint.text = "Press your trigger to try again" if _failed else "Aim + trigger selects headset menus."
	_desktop_tip.text = "Check your connection, then try again." if _failed else TIPS[_tip_index]

func _update_visibility() -> void:
	var in_headset := get_viewport().use_xr
	_canvas.visible = _shown and not in_headset
	_world.visible = _shown and in_headset

func _process(delta: float) -> void:
	_update_visibility()
	_tip_elapsed += delta
	if not _failed and _tip_elapsed >= 5.0:
		_tip_elapsed = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
		_desktop_tip.text = TIPS[_tip_index]
