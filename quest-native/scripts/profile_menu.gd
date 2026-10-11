extends "res://scripts/lobby_menu.gd"

const ProfileScript = preload("res://scripts/profile_state.gd")
const MenuTheme = preload("res://scripts/menu_theme.gd")
const DEFAULT_PICTURE = preload("res://assets/app_icon.png")
const KEYS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_- ."
var _name_buffer := "Monke"
var _name_edit: LineEdit
var _desktop_picture: TextureRect
var _desktop_progress: ProgressBar
var _desktop_level: Label
var _world_picture: Sprite3D
var _world_name: Label3D
var _world_level: Label3D
var _picture_dialog: FileDialog
var _avatar_cache := PackedByteArray()
var _picker_generation := -1
var _menu_generation := -1
var _name_touched := false
var _desktop_frame: Dictionary
var _desktop_hero: GridContainer
var _desktop_picture_actions: GridContainer
var _desktop_actions: GridContainer

func _init() -> void:
	toggle_key = KEY_F5
	# Profile is opened from the main menu in VR, without stealing a controller
	# shortcut that is already assigned to Account or Developer tools.
	toggle_button = "profile_menu_unassigned"
	panel_size = Vector2(2.1, 2.35)

func _profile() -> Node:
	return game.get("profile") as Node if is_instance_valid(game) else null

func set_open(value: bool) -> void:
	if value and is_instance_valid(game) and game.get("frontend_state") == "loading":
		return
	var was_open := is_open
	if value and not was_open:
		var profile := _profile()
		if profile != null:
			_name_buffer = str(profile.get("display_name"))
			_menu_generation = int(profile.get("_generation"))
			_name_touched = false
		if is_instance_valid(game) and game.has_method("on_feature_menu_open"):
			game.call("on_feature_menu_open", self)
	super.set_open(value)
	if value and _name_edit != null:
		_name_edit.text = _name_buffer
		_update_labels()
		if not _is_xr():
			_name_edit.grab_focus()
	elif was_open:
		if _name_edit != null:
			_name_edit.release_focus()
		if is_instance_valid(game) and game.has_method("close_feature_menu"):
			game.call("close_feature_menu", self)

func refresh_status() -> void:
	var profile := _profile()
	if profile == null:
		return
	var summary: Dictionary = profile.call("progress_summary")
	var picture: PackedByteArray = profile.get("avatar")
	var generation := int(profile.get("_generation"))
	if generation != _menu_generation:
		_menu_generation = generation
		_name_touched = false
	if not _name_touched:
		_name_buffer = str(profile.get("display_name"))
		if _name_edit != null:
			_name_edit.text = _name_buffer
	var snapshot := "%s|%s|%s|%s|%s" % [profile.get("status"), summary.xp, profile.get("display_name"), hash(picture), generation]
	if snapshot == _state_snapshot:
		return
	_state_snapshot = snapshot
	_status_text = str(profile.get("status"))
	_update_labels()
	if _desktop_level != null:
		_desktop_level.text = "LEVEL %d  ·  %d XP" % [summary.level, summary.xp]
		_desktop_progress.max_value = summary.needed
		_desktop_progress.value = summary.current
	if _world_level != null:
		_world_level.text = "LEVEL %d · %d / %d XP" % [summary.level, summary.current, summary.needed]
	if picture != _avatar_cache:
		_avatar_cache = picture.duplicate()
		var texture: Texture2D = DEFAULT_PICTURE
		if ProfileScript.validate_avatar(picture):
			var image := Image.new()
			if image.load_png_from_buffer(picture) == OK:
				texture = ImageTexture.create_from_image(image)
		if _desktop_picture != null:
			_desktop_picture.texture = texture
		if _world_picture != null:
			_world_picture.texture = texture
			_world_picture.pixel_size = 0.3 / float(maxi(1, texture.get_width()))

func _update_labels() -> void:
	if _desktop_status != null:
		_desktop_status.text = _status_text
	if _world_status != null:
		_world_status.text = _status_text
	if _world_name != null:
		_world_name.text = "NAME: " + _name_buffer

func _action_enabled(action: String) -> bool:
	if action == "upload":
		return DisplayServer.get_name() != "headless"
	return _profile() != null or action == "close"

func _dispatch(action: String) -> void:
	if not _action_enabled(action):
		return
	var profile := _profile()
	if action.begins_with("key:"):
		_set_name((_name_buffer + action.trim_prefix("key:")).left(20))
	elif action == "backspace":
		_set_name(_name_buffer.left(maxi(0, _name_buffer.length() - 1)))
	elif action == "clear_name":
		_set_name("")
	elif action == "save":
		if profile.call("set_display_name", _name_buffer):
			profile.call("save_now")
	elif action == "sync":
		profile.call("save_now")
	elif action == "reset_picture":
		profile.call("clear_avatar")
	elif action == "upload":
		_open_picker()
	elif action == "close":
		set_open(false)
	refresh_status()

func _set_name(value: String) -> void:
	_name_touched = true
	_name_buffer = value.left(20)
	if _name_edit != null and _name_edit.text != _name_buffer:
		_name_edit.text = _name_buffer
	_update_labels()

func _open_picker() -> void:
	var profile := _profile()
	if profile == null:
		return
	_picker_generation = int(profile.get("_generation"))
	if _picture_dialog == null:
		_picture_dialog = FileDialog.new()
		_picture_dialog.title = "Choose your profile picture"
		_picture_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_picture_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_picture_dialog.filters = PackedStringArray(["*.png ; PNG pictures", "*.jpg,*.jpeg ; JPEG pictures"])
		_picture_dialog.use_native_dialog = true
		_picture_dialog.file_selected.connect(_picture_selected)
		add_child(_picture_dialog)
	if _is_xr() and OS.get_name() != "Android":
		_status_text = "The picture picker opened on your PC monitor. Choose a local PNG or JPEG."
	elif OS.get_name() == "Android":
		_status_text = "Choose a local PNG or JPEG in the headset's system picker. You can also upload on PC and sync your account."
	else:
		_status_text = "Choose a PNG or JPEG up to 4 MB. Pictures are shared with room players."
	_update_labels()
	_picture_dialog.popup_centered_ratio(0.7)

func _picture_selected(path: String) -> void:
	var profile := _profile()
	if profile != null:
		if _picker_generation != int(profile.get("_generation")):
			_status_text = "The account changed while the picker was open. Choose your picture again."
			_update_labels()
			return
		profile.call("import_avatar_file", path, true)
		refresh_status()

func _adapt_desktop_layout() -> void:
	var width := get_viewport().get_visible_rect().size.x
	if _desktop_hero != null:
		_desktop_hero.columns = 2 if width >= 480 else 1
	if _desktop_picture_actions != null:
		_desktop_picture_actions.columns = 2 if width >= 600 else 1
	if _desktop_actions != null:
		_desktop_actions.columns = 3 if width >= 600 else 1

func _create_desktop_menu() -> void:
	_desktop_frame = MenuTheme.desktop_frame(self, "ProfileOverlay", 42, 610)
	_canvas = _desktop_frame.canvas
	var content: VBoxContainer = _desktop_frame.content
	MenuTheme.label(content, "YOUR MONKE", 30)
	_desktop_hero = GridContainer.new()
	_desktop_hero.columns = 2
	_desktop_hero.add_theme_constant_override("h_separation", 24)
	_desktop_hero.add_theme_constant_override("v_separation", 12)
	content.add_child(_desktop_hero)
	_desktop_picture = TextureRect.new()
	_desktop_picture.custom_minimum_size = Vector2(100, 100)
	_desktop_picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_desktop_picture.texture = DEFAULT_PICTURE
	_desktop_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_desktop_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_desktop_hero.add_child(_desktop_picture)
	var progress := VBoxContainer.new()
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.add_theme_constant_override("separation", 10)
	_desktop_hero.add_child(progress)
	_desktop_level = MenuTheme.label(progress, "", 23, MenuTheme.GREEN, true)
	_desktop_progress = ProgressBar.new()
	_desktop_progress.custom_minimum_size.y = 20
	_desktop_progress.show_percentage = false
	_desktop_progress.add_theme_stylebox_override("background", MenuTheme.style(MenuTheme.FOREST, Color.TRANSPARENT, 10))
	_desktop_progress.add_theme_stylebox_override("fill", MenuTheme.style(MenuTheme.GREEN, Color.TRANSPARENT, 10))
	progress.add_child(_desktop_progress)
	MenuTheme.label(progress, "Earn cosmetic XP by playing rounds and tagging.", 15, MenuTheme.MUTED, true)
	MenuTheme.label(content, "Public name · shown to room players", 15, MenuTheme.CREAM, true)
	_name_edit = LineEdit.new()
	_name_edit.text = _name_buffer
	_name_edit.max_length = 20
	MenuTheme.field(_name_edit)
	_name_edit.text_changed.connect(_set_name)
	_name_edit.text_submitted.connect(func(_value: String): _dispatch("save"))
	content.add_child(_name_edit)
	_desktop_picture_actions = GridContainer.new()
	_desktop_picture_actions.add_theme_constant_override("h_separation", 8)
	_desktop_picture_actions.add_theme_constant_override("v_separation", 8)
	content.add_child(_desktop_picture_actions)
	MenuTheme.button(self, _desktop_picture_actions, "Upload picture", "upload")
	MenuTheme.button(self, _desktop_picture_actions, "Use Monke icon", "reset_picture")
	MenuTheme.label(content, "PNG / JPEG · up to 4 MB · cropped to a small square\nYour public picture, name, and cosmetic level are visible to other players.", 14, MenuTheme.MUTED, true)
	_desktop_status = MenuTheme.label(content, "", 15, MenuTheme.ORANGE, true)
	_desktop_status.custom_minimum_size.y = 48
	_desktop_actions = GridContainer.new()
	_desktop_actions.add_theme_constant_override("h_separation", 8)
	_desktop_actions.add_theme_constant_override("v_separation", 8)
	content.add_child(_desktop_actions)
	MenuTheme.button(self, _desktop_actions, "Save profile", "save", true)
	MenuTheme.button(self, _desktop_actions, "Retry sync", "sync")
	MenuTheme.button(self, _desktop_actions, "Close · F5", "close")
	var viewport := get_viewport()
	viewport.size_changed.connect(_adapt_desktop_layout)
	tree_exiting.connect(func():
		if viewport.size_changed.is_connected(_adapt_desktop_layout): viewport.size_changed.disconnect(_adapt_desktop_layout))
	_adapt_desktop_layout()

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldProfile"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, panel_size, -0.035, Color("142d32"))
	_world_label("YOUR MONKE", Vector2(0, 1.0), 49)
	_world_picture = Sprite3D.new()
	_world_picture.texture = DEFAULT_PICTURE
	_world_picture.pixel_size = 0.3 / float(maxi(1, DEFAULT_PICTURE.get_width()))
	_world_picture.position = Vector3(-0.6, 0.72, 0.04)
	_world_picture.no_depth_test = true
	_world_picture.render_priority = 2
	_world_panel.add_child(_world_picture)
	_world_level = _world_label("", Vector2(0.23, 0.73), 30)
	_world_label("Play rounds + tag to earn cosmetic XP", Vector2(0, 0.5), 26)
	_world_status = _world_label("", Vector2(0, 0.35), 24)
	_world_status.width = 1200
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_button("", "name", Vector2(0, 0.18), Vector2(1.95, 0.11))
	_world_name = _world_buttons.back()["label"]
	_world_name.font_size = 30
	_world_button("UPLOAD", "upload", Vector2(-0.65, 0.02), Vector2(0.60, 0.11))
	_world_button("MONKE ICON", "reset_picture", Vector2(0, 0.02), Vector2(0.60, 0.11))
	_world_button("SAVE", "save", Vector2(0.65, 0.02), Vector2(0.60, 0.11), Color("386d4b"))
	for index in range(KEYS.length()):
		var character := KEYS.substr(index, 1)
		_world_button("SPACE" if character == " " else character, "key:" + character, Vector2(-0.9225 + (index % 10) * 0.205, -0.16 - (index / 10) * 0.14), Vector2(0.165, 0.11))
		_world_buttons.back()["label"].font_size = 23 if character == " " else 32
	_world_button("BACKSPACE", "backspace", Vector2(-0.65, -0.77), Vector2(0.60, 0.11))
	_world_button("CLEAR NAME", "clear_name", Vector2(0, -0.77), Vector2(0.60, 0.11))
	_world_button("RETRY SYNC", "sync", Vector2(0.65, -0.77), Vector2(0.60, 0.11))
	_world_button("CLOSE", "close", Vector2(0, -0.94), Vector2(1.95, 0.11))
	_world_label("Aim + trigger · Public picture and name", Vector2(0, -1.09), 24)
	MenuTheme.world_text(_world_panel)
	_pointer = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.009
	dot.height = 0.018
	_pointer.mesh = dot
	_pointer.material_override = _material(Color("d9ff99"))
	_pointer.material_override.render_priority = 3
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pointer)
