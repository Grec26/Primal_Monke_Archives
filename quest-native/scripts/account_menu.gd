extends "res://scripts/lobby_menu.gd"

# Credentials remain transient input values. Only the public PlayFab ID and
# account state are shown outside masked input controls.
const LETTER_ROWS := ["1234567890", "qwertyuiop", "asdfghjkl@", "zxcvbnm._-", "!?/:+=,; '"]
const SYMBOL_ROWS := ["!@#$%^&*()", "[]{}<>+=\\|", ";:'\",./?`~", "_-01234567", "89!@#$%^&*"]
const INPUT_LIMITS := {"username": 20, "email": 254, "password": 100}

var _username := ""
var _email := ""
var _password := ""
var _active_field := "username"
var _uppercase := false
var _symbols := false
var _username_edit: LineEdit
var _email_edit: LineEdit
var _password_edit: LineEdit
var _desktop_role: Label
var _world_role: Label3D
var _world_fields: Dictionary = {}

func _init() -> void:
	toggle_key = KEY_F3
	toggle_hand = 0
	toggle_button = "ax_button"
	panel_size = Vector2(2.1, 2.35)
	_status_text = "Signing in this device…"

func set_open(value: bool) -> void:
	if value and not is_open and is_instance_valid(game) and game.has_method("on_account_menu_open"):
		game.call("on_account_menu_open")
	super.set_open(value)
	if not value:
		_set_field("password", "")
		for control in [_username_edit, _email_edit, _password_edit]:
			if control != null:
				control.release_focus()
	elif not _is_xr() and _username_edit != null:
		_username_edit.grab_focus()
		_username_edit.select_all()

func _exit_tree() -> void:
	_password = ""
	if is_instance_valid(_password_edit):
		_password_edit.text = ""
	super._exit_tree()

func _account_bool(property_name: String) -> bool:
	return is_instance_valid(game) and game.get(property_name) == true

func refresh_status() -> void:
	if not is_instance_valid(game):
		return
	var configured := _account_bool("account_configured")
	var signed_in := _account_bool("account_signed_in")
	var busy := _account_bool("account_busy")
	var developer := _account_bool("account_is_developer")
	var has_credentials := _account_bool("account_has_credentials")
	var status := _game_text("account_status", "Signed out")
	if not configured:
		status = "Account sign-in has not been configured."
	var account_id := _game_text("account_id", "Not signed in")
	var snapshot := "%s|%s|%s|%s|%s|%s|%s" % [status, account_id, configured, signed_in, busy, developer, has_credentials]
	if snapshot == _state_snapshot:
		return
	_state_snapshot = snapshot
	_status_text = status
	_update_labels()
	_refresh_controls()

func _login_identifier() -> String:
	return _email.strip_edges() if not _email.strip_edges().is_empty() else _username.strip_edges()

func _action_enabled(action: String) -> bool:
	var busy := _account_bool("account_busy")
	var signed_in := _account_bool("account_signed_in")
	var configured := _account_bool("account_configured")
	match action:
		"login":
			return configured and not busy and not _login_identifier().is_empty() and _password.length() >= 6
		"register":
			return configured and not busy and not _account_bool("account_has_credentials") and _username.strip_edges().length() >= 3 and _email.contains("@") and _password.length() >= 6
		"device":
			return configured and not busy
		"refresh":
			return signed_in and not busy
		"logout":
			return signed_in or busy
		"close":
			return true
	return not busy

func _dispatch(action: String) -> void:
	if not _action_enabled(action):
		return
	if action == "close":
		set_open(false)
		return
	if action.begins_with("field:"):
		_active_field = action.trim_prefix("field:")
		_update_button_colors()
		return
	if action.begins_with("key_index:"):
		var character := _keyboard_character(action.trim_prefix("key_index:").to_int())
		_set_field(_active_field, _field_value(_active_field) + character)
		return
	match action:
		"uppercase":
			_uppercase = not _uppercase
			_refresh_keyboard()
			return
		"symbols":
			_symbols = not _symbols
			_refresh_keyboard()
			return
		"backspace":
			var value := _field_value(_active_field)
			_set_field(_active_field, value.left(maxi(0, value.length() - 1)))
			return
		"clear":
			_set_field(_active_field, "")
			return
	if not is_instance_valid(game):
		return
	match action:
		"login":
			var identifier := _login_identifier()
			var submitted_password := _password
			_set_field("password", "")
			if game.has_method("account_login_credentials"):
				game.call("account_login_credentials", identifier, submitted_password)
		"register":
			var username := _username.strip_edges()
			var email := _email.strip_edges()
			var submitted_password := _password
			_set_field("password", "")
			if game.has_method("account_register"):
				game.call("account_register", username, email, submitted_password)
		"device":
			_set_field("password", "")
			if game.has_method("account_login_device"):
				game.call("account_login_device")
		"refresh":
			if game.has_method("account_refresh"):
				game.call("account_refresh")
		"logout":
			_set_field("password", "")
			if game.has_method("account_logout"):
				game.call("account_logout")
	refresh_status()

func _field_value(field: String) -> String:
	match field:
		"username": return _username
		"email": return _email
		"password": return _password
	return ""

func _set_field(field: String, value: String) -> void:
	if not INPUT_LIMITS.has(field):
		return
	value = value.left(INPUT_LIMITS[field])
	var control: LineEdit
	match field:
		"username":
			_username = value
			control = _username_edit
		"email":
			_email = value
			control = _email_edit
		"password":
			_password = value
			control = _password_edit
	if control != null and control.text != value:
		control.text = value
		control.caret_column = value.length()
	_update_labels()
	_refresh_controls()

func _refresh_controls() -> void:
	var editable := not _account_bool("account_busy")
	for control in [_username_edit, _email_edit, _password_edit]:
		if control != null:
			control.editable = editable
	for action in _desktop_buttons:
		var button: Button = _desktop_buttons[action]
		button.disabled = not _action_enabled(action)
	_update_button_colors()

func _role_text() -> String:
	if not _account_bool("account_signed_in"):
		return "Signed out"
	var role := "Developer access" if _account_bool("account_is_developer") else "Player account"
	return role + (" · Registered account" if _account_bool("account_has_credentials") else " · Device account")

func _update_labels() -> void:
	var account_id := _game_text("account_id", "Not signed in")
	var role := _role_text()
	if _desktop_status != null:
		_desktop_status.text = _status_text
	if _desktop_address != null:
		_desktop_address.text = "PlayFab ID: " + account_id
	if _desktop_role != null:
		_desktop_role.text = role
	if _world_status != null:
		_world_status.text = _status_text
	if _world_address != null:
		_world_address.text = "PlayFab ID: " + account_id
	if _world_role != null:
		_world_role.text = role
	for field in _world_fields:
		var label: Label3D = _world_fields[field]
		if field == "password":
			# Never copy the password into any world-space label.
			label.text = "PASSWORD: " + ("•".repeat(mini(_password.length(), 32)) if not _password.is_empty() else "Select to enter")
		else:
			var value := _field_value(field)
			var preview := value if value.length() <= 42 else "…" + value.right(42)
			label.text = field.to_upper() + ": " + (preview if not preview.is_empty() else "Select to enter")

func _keyboard_character(index: int) -> String:
	if index < 0 or index >= 50:
		return ""
	var row := index / 10
	var column := index % 10
	var rows: Array = SYMBOL_ROWS if _symbols else LETTER_ROWS
	if row < 0 or row >= rows.size() or column >= rows[row].length():
		return ""
	var character: String = rows[row][column]
	return character.to_upper() if _uppercase else character

func _refresh_keyboard() -> void:
	for button in _world_buttons:
		var action: String = button["action"]
		var label: Label3D = button["label"]
		if action.begins_with("key_index:"):
			var character := _keyboard_character(action.trim_prefix("key_index:").to_int())
			label.text = "SPACE" if character == " " else character
		elif action == "uppercase":
			label.text = "UPPERCASE" if _uppercase else "LOWERCASE"
		elif action == "symbols":
			label.text = "LETTERS" if _symbols else "SYMBOLS"
	_update_button_colors()

func _update_button_colors() -> void:
	super._update_button_colors()
	for button in _world_buttons:
		var action: String = button["action"]
		var selected := action == "field:" + _active_field or (action == "uppercase" and _uppercase) or (action == "symbols" and _symbols)
		if selected and _action_enabled(action):
			var material: StandardMaterial3D = button["material"]
			material.albedo_color = Color("527d4e")

func _desktop_field(parent: VBoxContainer, caption: String, field: String, secret := false) -> LineEdit:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	var control := LineEdit.new()
	control.max_length = INPUT_LIMITS[field]
	control.secret = secret
	control.custom_minimum_size.y = 40
	control.text_changed.connect(func(value: String): _set_field(field, value))
	control.focus_entered.connect(func(): _active_field = field)
	parent.add_child(control)
	return control

func _create_desktop_menu() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "AccountOverlay"
	_canvas.layer = 40
	add_child(_canvas)
	var root := Control.new()
	_canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.06, 0.045, 0.86)
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 610)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	var heading := Label.new()
	heading.text = "PRIMAL MONKE · ACCOUNT"
	heading.add_theme_font_size_override("font_size", 25)
	content.add_child(heading)
	var help := Label.new()
	help.text = "Add credentials to this device account, or sign out to create a new account.\nSign in uses Email; clear Email to use Username."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(help)
	_desktop_address = Label.new()
	content.add_child(_desktop_address)
	_desktop_role = Label.new()
	content.add_child(_desktop_role)
	_desktop_status = Label.new()
	_desktop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desktop_status.custom_minimum_size.y = 42
	content.add_child(_desktop_status)
	_username_edit = _desktop_field(content, "Username (3–20 characters)", "username")
	_email_edit = _desktop_field(content, "Email", "email")
	_password_edit = _desktop_field(content, "Password (6–100 characters)", "password", true)
	_password_edit.text_submitted.connect(func(_value: String): _dispatch("login"))
	var first_row := HBoxContainer.new()
	first_row.add_theme_constant_override("separation", 8)
	content.add_child(first_row)
	_desktop_button(first_row, "Sign in", "login")
	_desktop_button(first_row, "Register", "register")
	_desktop_button(first_row, "Device account", "device")
	var second_row := HBoxContainer.new()
	second_row.add_theme_constant_override("separation", 8)
	content.add_child(second_row)
	_desktop_button(second_row, "Refresh access", "refresh")
	_desktop_button(second_row, "Sign out", "logout")
	_desktop_button(second_row, "Close", "close")
	var hint := Label.new()
	hint.text = "F3: open / close · Headset: left X, right aim + trigger"
	content.add_child(hint)

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldAccount"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, panel_size, -0.035, Color("102a22"))
	_world_label("PRIMAL MONKE ACCOUNT", Vector2(0, 1.07), 41)
	_world_label("Add credentials here; sign out to create a new account\nSign in uses Email; clear Email to use Username", Vector2(0, 0.965), 22)
	_world_address = _world_label("", Vector2(0, 0.855), 28)
	_world_role = _world_label("", Vector2(0, 0.76), 27)
	_world_status = _world_label("", Vector2(0, 0.66), 26)
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_status.width = 1900.0
	var fields := ["username", "email", "password"]
	for index in range(fields.size()):
		var field: String = fields[index]
		_world_button("", "field:" + field, Vector2(0, 0.54 - index * 0.16), Vector2(1.95, 0.11))
		var label: Label3D = _world_buttons.back()["label"]
		label.font_size = 27
		_world_fields[field] = label
	_world_button("SIGN IN", "login", Vector2(-0.65, 0.055), Vector2(0.60, 0.11), Color("386d4b"))
	_world_button("REGISTER", "register", Vector2(0, 0.055), Vector2(0.60, 0.11), Color("71632f"))
	_world_button("DEVICE", "device", Vector2(0.65, 0.055), Vector2(0.60, 0.11))
	_world_button("REFRESH", "refresh", Vector2(-0.65, -0.105), Vector2(0.60, 0.11))
	_world_button("SIGN OUT", "logout", Vector2(0, -0.105), Vector2(0.60, 0.11))
	_world_button("CLOSE", "close", Vector2(0.65, -0.105), Vector2(0.60, 0.11))
	for index in range(50):
		var row := index / 10
		var column := index % 10
		var character := _keyboard_character(index)
		_world_button("SPACE" if character == " " else character, "key_index:%d" % index, Vector2(-0.9225 + column * 0.205, -0.27 - row * 0.14), Vector2(0.165, 0.11))
		var label: Label3D = _world_buttons.back()["label"]
		label.font_size = 23 if character == " " else 32
	_world_button("LOWERCASE", "uppercase", Vector2(-0.765, -0.99), Vector2(0.46, 0.11))
	_world_button("SYMBOLS", "symbols", Vector2(-0.255, -0.99), Vector2(0.46, 0.11))
	_world_button("BACKSPACE", "backspace", Vector2(0.255, -0.99), Vector2(0.46, 0.11))
	_world_button("CLEAR FIELD", "clear", Vector2(0.765, -0.99), Vector2(0.46, 0.11))
	_world_label("Left X closes · Select a field, then aim + trigger", Vector2(0, -1.13), 23)
	_pointer = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.009
	dot.height = 0.018
	_pointer.mesh = dot
	_pointer.material_override = _material(Color("d9ff99"))
	_pointer.material_override.render_priority = 3
	_pointer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pointer)
