extends Node3D

# Presentation consumes the forest's state; gameplay and networking remain
# authoritative in their existing controllers. Nothing here creates colliders.
const MenuTheme = preload("res://scripts/menu_theme.gd")

var game: Node3D
var _canvas: CanvasLayer
var _root: Control
var _card: PanelContainer
var _badge: Label
var _title: Label
var _timer: Label
var _objective: Label
var _profile: Label
var _status: Label
var _progress: ProgressBar
var _footer: Label
var _diagnostics: Label
var _snapshot := ""

func _ready() -> void:
	_configure_environment()
	_create_ground_details()
	_create_hud()

func _configure_environment() -> void:
	if not is_instance_valid(game): return
	for child in game.get_children():
		if child is WorldEnvironment and child.environment != null:
			var environment: Environment = child.environment
			var sky_material := ProceduralSkyMaterial.new()
			sky_material.sky_top_color = Color("527f8c")
			sky_material.sky_horizon_color = Color("c3d4b4")
			sky_material.ground_bottom_color = Color("244e3d")
			sky_material.ground_horizon_color = Color("c3d4b4")
			sky_material.sky_curve = 0.22
			sky_material.sun_angle_max = 5.0
			var sky := Sky.new()
			sky.sky_material = sky_material
			sky.radiance_size = Sky.RADIANCE_SIZE_128
			environment.background_mode = Environment.BG_SKY
			environment.sky = sky
			environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.ambient_light_color = Color("d4e3bf")
			environment.ambient_light_energy = 0.72
			environment.fog_enabled = true
			environment.fog_light_color = Color("b6ccb2")
			environment.fog_density = 0.008
		elif child is DirectionalLight3D:
			child.light_color = Color("fff1ca")
			child.light_energy = 1.0
			child.shadow_enabled = false

func _create_ground_details() -> void:
	if not is_instance_valid(game): return
	var map: Node3D = game.get("forest_map") as Node3D
	if map == null: return
	# One instanced draw for small plants along the boundary keeps the playable
	# lanes clear and the headset scene inexpensive. They vanish with the map.
	var plants := MultiMeshInstance3D.new()
	plants.name = "ForestGroundPlants"
	plants.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var leaf := PrismMesh.new()
	leaf.size = Vector3(0.13, 0.3, 0.08)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("628c4e")
	material.roughness = 1.0
	leaf.material = material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = leaf
	instances.instance_count = 48
	for index in range(48):
		var side := index / 12
		var step := index % 12
		var along := -13.4 + step * 2.25
		var edge := 14.8 + float(step % 3) * 0.12
		var location := Vector3(along, 0.13, edge) if side == 0 else Vector3(edge, 0.13, along)
		if side == 2: location = Vector3(along, 0.13, -edge)
		elif side == 3: location = Vector3(-edge, 0.13, along)
		var basis := Basis(Vector3.UP, float(index) * 1.73)
		basis = basis.scaled(Vector3(1.0 + 0.15 * (index % 3), 0.7 + 0.18 * (index % 4), 1.0))
		instances.set_instance_transform(index, Transform3D(basis, location))
	plants.multimesh = instances
	map.add_child(plants)

func _create_hud() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "GameHUD"
	_canvas.layer = 4
	_canvas.visible = false
	add_child(_canvas)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = PanelContainer.new()
	_card.position = Vector2(20, 20)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_style := MenuTheme.style(Color(0.045, 0.12, 0.085, 0.91), Color("567448"), 16)
	card_style.content_margin_left = 18
	card_style.content_margin_right = 18
	card_style.content_margin_top = 14
	card_style.content_margin_bottom = 14
	_card.add_theme_stylebox_override("panel", card_style)
	_root.add_child(_card)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	_card.add_child(column)
	_badge = MenuTheme.label(column, "SOLO · FOREST", 11, MenuTheme.ORANGE)
	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation", 14)
	column.add_child(heading)
	_title = MenuTheme.label(heading, "FOREST CHASE", 20)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_timer = MenuTheme.label(heading, "1:30", 23, MenuTheme.GREEN)
	_timer.size_flags_horizontal = Control.SIZE_SHRINK_END
	_objective = MenuTheme.label(column, "Tag the five forest monkeys", 14, MenuTheme.CREAM, true)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 5
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.add_theme_stylebox_override("background", MenuTheme.style(Color("314d38"), Color.TRANSPARENT, 3))
	_progress.add_theme_stylebox_override("fill", MenuTheme.style(MenuTheme.GREEN, Color.TRANSPARENT, 3))
	column.add_child(_progress)
	_profile = MenuTheme.label(column, "Monke · Level 1", 12, MenuTheme.MUTED, true)
	_status = MenuTheme.label(column, "", 12, MenuTheme.ORANGE, true)
	_diagnostics = MenuTheme.label(column, "", 12, MenuTheme.MUTED, true)
	_footer = Label.new()
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.add_theme_color_override("font_color", MenuTheme.CREAM)
	_footer.add_theme_color_override("font_outline_color", Color("10291f"))
	_footer.add_theme_constant_override("outline_size", 5)
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_footer)
	get_viewport().size_changed.connect(_adapt_hud)
	_adapt_hud()

func _adapt_hud() -> void:
	if _card == null: return
	var size := get_viewport().get_visible_rect().size
	_card.custom_minimum_size.x = clampf(size.x - 40.0, 240.0, 360.0)
	_footer.position = Vector2(24, maxf(24.0, size.y - 46.0))
	_footer.size.x = maxf(220.0, size.x - 48.0)

func update_hud(data: Dictionary) -> void:
	if _canvas == null: return
	_canvas.visible = data.get("visible", false) == true
	if not _canvas.visible: return
	var mode := str(data.get("mode", "co_op"))
	var map_playtest := mode == "map_playtest"
	var network := str(data.get("network", "offline"))
	var title := str(data.get("title", "FOREST CHASE"))
	var seconds := maxi(0, ceili(float(data.get("remaining", 90.0))))
	var score := clampi(int(data.get("score", 0)), 0, 5)
	# The forest updates every physics tick; relayout only when a displayed
	# value changes, rather than rebuilding text for fractional timer changes.
	var signature := JSON.stringify([mode, network, title, seconds, score, data.get("map_name", ""), data.get("profile", ""), data.get("status", ""), data.get("tag_summary", ""), data.get("diagnostics", "")])
	if signature == _snapshot: return
	_snapshot = signature
	_badge.text = "MAP PLAYTEST · LOCAL" if map_playtest else ("SOLO · FOREST" if network == "offline" else "MULTIPLAYER · " + network.to_upper())
	_title.text = "MAP PLAYTEST" if map_playtest else title
	_timer.text = "" if map_playtest else "%d:%02d" % [seconds / 60, seconds % 60]
	_timer.add_theme_color_override("font_color", MenuTheme.ORANGE if seconds <= 15 and not map_playtest else MenuTheme.GREEN)
	if map_playtest:
		_objective.text = str(data.get("map_name", "Your custom map")) + "\nExplore freely. No timer or XP."
	elif mode == "tag":
		_objective.text = str(data.get("tag_summary", "Chase the orange monke"))
	else:
		_objective.text = "%d / 5 tagged · %s" % [score, "All monkeys found!" if score == 5 else "Find the forest monkeys"]
	_progress.visible = not map_playtest
	_progress.value = clampf(float(seconds) / 90.0, 0.0, 1.0) * 100.0 if mode == "tag" else score * 20.0
	_profile.text = str(data.get("profile", "Monke · Level 1"))
	_status.text = str(data.get("status", ""))
	_status.visible = not _status.text.is_empty()
	_diagnostics.text = str(data.get("diagnostics", ""))
	_diagnostics.visible = not _diagnostics.text.is_empty()
	_footer.text = "F8 / Right B: return to editor · WASD: move · Space: jump" if map_playtest else "WASD: move · Right mouse: look · Space: jump · E: tag · F1: menu"
	# The creator owns its bottom playtest notice and Return to editor button.
	_footer.visible = not map_playtest
	for control in [_badge, _title, _timer, _objective, _profile, _status, _diagnostics]:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
