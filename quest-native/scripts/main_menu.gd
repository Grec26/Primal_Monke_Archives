extends "res://scripts/lobby_menu.gd"

# The forest owns the frontend state. This menu only chooses a destination;
# opening or closing it never starts a round or creates a network session.
const INK := Color("112c25")
const CREAM := Color("f4f1df")
const MUTED := Color("b4c9af")
const ORANGE := Color("f0aa58")
const MenuTheme = preload("res://scripts/menu_theme.gd")

var _desktop_mode: Label
var _world_mode: Label3D
var _desktop_profile: Label
var _world_profile: Label3D
var _desktop_frame: Dictionary = {}
var _desktop_artwork: VBoxContainer
var _desktop_utilities: GridContainer
var _desktop_heading: Label

func _init() -> void:
	toggle_key = KEY_F1
	toggle_hand = 1
	toggle_button = "by_button"
	panel_size = Vector2(1.7, 2.34)
	_status_text = "Choose how you want to play."

func toggle() -> void:
	# The main screen stays open until the player chooses a destination. In a
	# round, its shortcut pauses locally through the forest's frontend handler.
	if is_open or _game_text("frontend_state", "main_menu") == "loading":
		return
	if is_instance_valid(game) and game.has_method("open_main_menu"):
		game.call("open_main_menu")
	else:
		set_open(true)

func _process(delta: float) -> void:
	# Right B belongs to the multiplayer lobby while that screen/session is
	# active. F1 still reaches toggle() directly on desktop in every state.
	if _game_text("network_mode", "offline") != "offline" or _game_text("frontend_state", "main_menu") == "lobby":
		_toggle_held = true
	super._process(delta)

func set_open(value: bool) -> void:
	super.set_open(value)
	if value and not _is_xr():
		var first_action := "resume" if _action_enabled("resume") else "solo"
		if _desktop_buttons.has(first_action):
			var button: Button = _desktop_buttons[first_action]
			button.grab_focus()

func _action_enabled(action: String) -> bool:
	if not is_instance_valid(game) or _game_text("frontend_state", "main_menu") == "loading":
		return false
	match action:
		"solo": return game.has_method("start_solo")
		"multiplayer": return game.has_method("open_multiplayer_lobby")
		"account": return game.has_method("open_account_menu")
		"developer": return game.has_method("can_open_developer_menu") and game.has_method("open_developer_menu") and bool(game.call("can_open_developer_menu"))
		"profile": return game.has_method("open_profile_menu")
		"tutorial": return game.has_method("open_tutorial_menu")
		"voice": return game.has_method("open_voice_menu")
		"resume": return game.has_method("can_resume_play") and game.has_method("resume_play") and bool(game.call("can_resume_play"))
		"quit": return OS.get_name() != "Android" and game.has_method("quit_game")
		"pcvr", "desktop": return super._action_enabled(action)
	return false

func _dispatch(action: String) -> void:
	if not _action_enabled(action):
		return
	match action:
		"solo": game.call("start_solo")
		"multiplayer": game.call("open_multiplayer_lobby")
		"account": game.call("open_account_menu")
		"developer": game.call("open_developer_menu")
		"profile": game.call("open_profile_menu")
		"tutorial": game.call("open_tutorial_menu")
		"voice": game.call("open_voice_menu")
		"resume": game.call("resume_play")
		"quit": game.call("quit_game")
		"pcvr", "desktop": game.call("switch_play_mode", action)
	refresh_status()

func refresh_status() -> void:
	if not is_instance_valid(game):
		return
	var status := _game_text("frontend_status", "Choose how you want to play.")
	var mode_notice := _game_text("play_mode_notice", "")
	if not mode_notice.is_empty():
		status += "\n" + mode_notice
	var developer := bool(game.get("account_is_developer"))
	var snapshot := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [status, _is_xr(), _action_enabled("resume"), _action_enabled("pcvr"), _action_enabled("desktop"), _game_text("account_status", "Signed out"), _game_text("frontend_state", "main_menu"), _game_text("profile_summary", "Monke · Level 1"), developer, _action_enabled("developer")]
	if snapshot == _state_snapshot:
		return
	_state_snapshot = snapshot
	_status_text = status
	_update_labels()
	for action in _desktop_buttons:
		var button: Button = _desktop_buttons[action]
		button.disabled = not _action_enabled(action)
		if action == "resume":
			button.visible = _action_enabled("resume")
		elif action == "developer":
			button.visible = developer
	_set_world_action_visible("developer", developer)
	_update_button_colors()

func _mode_text() -> String:
	if OS.get_name() == "Android":
		return "QUEST VR" if _is_xr() else "QUEST · tracking unavailable"
	return "PC VR · arm movement" if _is_xr() else "DESKTOP · keyboard + mouse"

func _update_labels() -> void:
	var summary := _game_text("profile_summary", "Monke · Level 1")
	if _desktop_profile != null: _desktop_profile.text = summary
	if _world_profile != null: _world_profile.text = summary.replace("\n", " ").left(72)
	if _desktop_status != null:
		_desktop_status.text = _status_text
	if _desktop_mode != null:
		_desktop_mode.text = _mode_text()
	if _world_status != null:
		_world_status.text = _status_text
	if _world_mode != null:
		_world_mode.text = _mode_text()

func _style(color: Color, border_color: Color = Color.TRANSPARENT, radius: int = 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border_color
	box.set_border_width_all(1 if border_color.a > 0.0 else 0)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 12.0
	box.content_margin_bottom = 12.0
	return box

func _label(parent: Node, text: String, size: int, color: Color = CREAM) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _menu_button(parent: Container, caption: String, action: String, primary := false) -> Button:
	return MenuTheme.button(self, parent, caption, action, primary)

func _adapt_desktop_layout() -> void:
	var width := get_viewport().get_visible_rect().size.x
	if _desktop_artwork != null: _desktop_artwork.visible = width >= 840
	if _desktop_utilities != null: _desktop_utilities.columns = 2 if width >= 600 else 1
	if _desktop_heading != null: _desktop_heading.add_theme_font_size_override("font_size", 44 if width >= 840 else 36)

func _create_desktop_menu() -> void:
	_desktop_frame = MenuTheme.desktop_frame(self, "MainMenuOverlay", 20, 900)
	_canvas = _desktop_frame.canvas
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	_desktop_frame.content.add_child(columns)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	columns.add_child(content)
	_label(content, "WELCOME TO THE FOREST", 13, ORANGE)
	_desktop_heading = _label(content, "PRIMAL\nMONKE", 44)
	_label(content, "Swing. Climb. Tag. Repeat.", 17, MUTED)
	_desktop_profile = _label(content, "", 14, MenuTheme.GREEN)
	_desktop_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	content.add_child(gap)
	_menu_button(content, "Resume game", "resume", true)
	_menu_button(content, "Play solo", "solo", true)
	_menu_button(content, "Multiplayer lobby", "multiplayer")
	_desktop_utilities = GridContainer.new()
	_desktop_utilities.columns = 2
	_desktop_utilities.add_theme_constant_override("h_separation", 8)
	_desktop_utilities.add_theme_constant_override("v_separation", 8)
	content.add_child(_desktop_utilities)
	_menu_button(_desktop_utilities, "Profile & levels", "profile")
	_menu_button(_desktop_utilities, "Account", "account")
	_menu_button(_desktop_utilities, "Tutorial", "tutorial")
	_menu_button(_desktop_utilities, "Voice controls", "voice")
	_menu_button(content, "Dev tools", "developer")
	if OS.get_name() != "Android":
		var mode_row := HBoxContainer.new()
		mode_row.add_theme_constant_override("separation", 8)
		content.add_child(mode_row)
		_menu_button(mode_row, "PC VR", "pcvr")
		_menu_button(mode_row, "Desktop", "desktop")
		_menu_button(content, "Quit", "quit")
	var artwork := VBoxContainer.new()
	_desktop_artwork = artwork
	artwork.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	artwork.custom_minimum_size.x = 310
	artwork.add_theme_constant_override("separation", 12)
	columns.add_child(artwork)
	var logo_center := CenterContainer.new()
	logo_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	artwork.add_child(logo_center)
	var logo := TextureRect.new()
	logo.texture = load(str(ProjectSettings.get_setting("application/config/icon", "res://icon.svg"))) as Texture2D
	logo.custom_minimum_size = Vector2(236, 236)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_center.add_child(logo)
	_label(artwork, "FIND YOUR TRIBE.", 27)
	var intro := _label(artwork, "Explore solo or meet friends in a local lobby.\nPC and Quest can play on the same Wi-Fi.", 16, MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_mode = _label(artwork, "", 14, ORANGE)
	_desktop_status = _label(artwork, "", 15, MUTED)
	_desktop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_status.custom_minimum_size.y = 46
	var hint := _label(artwork, "F1 / Tab: menu · F3: account\nHeadset: right B menu · aim + trigger", 13, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	get_viewport().size_changed.connect(_adapt_desktop_layout)
	_adapt_desktop_layout()

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldMainMenu"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, panel_size, -0.035, INK)
	_world_box(Vector2(0, 1.00), Vector2(1.56, 0.014), -0.012, ORANGE)
	_world_label("PRIMAL MONKE", Vector2(0, 0.88), 55)
	_world_label("Swing. Climb. Tag. Repeat.", Vector2(0, 0.78), 27)
	_world_mode = _world_label("", Vector2(0, 0.68), 23)
	_world_profile = _world_label("", Vector2(0, 0.58), 24)
	_world_profile.modulate = MenuTheme.GREEN
	_world_status = _world_label("", Vector2(0, 0.46), 24)
	_world_status.width = 1000.0
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_button("PLAY SOLO", "solo", Vector2(0, 0.29), Vector2(1.46, 0.13), Color("946632"))
	_world_button("MULTIPLAYER LOBBY", "multiplayer", Vector2(0, 0.115), Vector2(1.46, 0.13), Color("386d4b"))
	_world_button("PROFILE + LEVELS", "profile", Vector2(-0.385, -0.055), Vector2(0.69, 0.12))
	_world_buttons.back()["label"].font_size = 24
	_world_button("ACCOUNT", "account", Vector2(0.385, -0.055), Vector2(0.69, 0.12))
	_world_button("TUTORIAL", "tutorial", Vector2(-0.385, -0.225), Vector2(0.69, 0.12))
	_world_button("VOICE", "voice", Vector2(0.385, -0.225), Vector2(0.69, 0.12))
	_world_button("RESUME GAME", "resume", Vector2(0, -0.395), Vector2(1.46, 0.12))
	if OS.get_name() != "Android":
		_world_button("PC VR", "pcvr", Vector2(-0.385, -0.56), Vector2(0.69, 0.12))
		_world_button("DESKTOP", "desktop", Vector2(0.385, -0.56), Vector2(0.69, 0.12))
		_world_button("QUIT", "quit", Vector2(0, -0.715), Vector2(1.46, 0.1))
	else:
		_world_label("PC + Quest · same Wi-Fi", Vector2(0, -0.62), 27)
	_world_button("DEV TOOLS", "developer", Vector2(0, -0.855), Vector2(1.46, 0.10), Color("946632"))
	_world_label("Right aim + trigger to select\nRight B opens this menu during play", Vector2(0, -1.015), 23)
	MenuTheme.world_text(_world_panel)
	_pointer = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.009
	dot.height = 0.018
	_pointer.mesh = dot
	_pointer.material_override = _material(ORANGE)
	_pointer.material_override.render_priority = 3
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pointer)
