extends "res://scripts/lobby_menu.gd"

# Credentials remain transient input values. Only the public PlayFab ID and
# account state are shown outside masked input controls.
const LETTER_ROWS := ["1234567890", "qwertyuiop", "asdfghjkl@", "zxcvbnm._-", "!?/:+=,; '"]
const SYMBOL_ROWS := ["!@#$%^&*()", "[]{}<>+=\\|", ";:'\",./?`~", "_-01234567", "89!@#$%^&*"]
const INPUT_LIMITS := {"username": 20, "email": 254, "password": 100}
const AccountScript = preload("res://scripts/playfab_account.gd")
const MenuTheme = preload("res://scripts/menu_theme.gd")
const ErrorCodes = preload("res://scripts/error_codes.gd")

var first_time := false
var _username := ""
var _email := ""
var _password := ""
var _active_field := "username"
var _uppercase := false
var _symbols := false
var _submission_action := "register"
var _mode_selected := false
var _was_registered := false
var _local_validation_visible := false
var _username_edit: LineEdit
var _email_edit: LineEdit
var _password_edit: LineEdit
var _desktop_role: Label
var _desktop_help: Label
var _desktop_heading: Label
var _desktop_code: Label
var _desktop_fields: GridContainer
var _desktop_secondary: GridContainer
var _desktop_frame: Dictionary = {}
var _world_role: Label3D
var _world_heading: Label3D
var _world_help: Label3D
var _world_fields: Dictionary = {}

func _init() -> void:
	toggle_key = KEY_F3
	toggle_hand = 0
	toggle_button = "ax_button"
	panel_size = Vector2(2.1, 2.35)
	_status_text = "Signing in this device…"

func set_first_time(value: bool) -> void:
	first_time = value
	if value:
		_submission_action = "register"
		_mode_selected = false
	_state_snapshot = ""
	if is_node_ready():
		refresh_status()

func select_mode(action: String) -> void:
	if action in ["register", "login"]:
		_dispatch("mode:" + action)

func set_open(value: bool) -> void:
	if value and is_instance_valid(game) and game.has_method("can_open_account_menu") and not game.call("can_open_account_menu"): return
	var was_open := is_open
	if value and not is_open and is_instance_valid(game) and game.has_method("on_account_menu_open"):
		_mode_selected = false
		_submission_action = "login" if _account_bool("account_has_credentials") else "register"
		game.call("on_account_menu_open")
	super.set_open(value)
	if not value:
		_set_field("password", "")
		for control in [_username_edit, _email_edit, _password_edit]:
			if control != null:
				control.release_focus()
		if was_open and is_instance_valid(game) and game.has_method("on_account_menu_closed"):
			game.call("on_account_menu_closed")
		if was_open and first_time:
			first_time = false
			if is_instance_valid(game) and game.has_method("on_first_time_account_closed"):
				game.call("on_first_time_account_closed")
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
	# Automatic device sign-in must not change a mode the player selected.
	# A successful upgrade switches the default to the existing-account form.
	if has_credentials and not _was_registered:
		_mode_selected = false
	if not _mode_selected:
		_submission_action = "login" if has_credentials else "register"
	_was_registered = has_credentials
	var status := _game_text("account_status", "Signed out")
	if not configured:
		status = "Account sign-in has not been configured."
	var account_id := _game_text("account_id", "Not signed in")
	var snapshot := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [status, account_id, configured, signed_in, busy, developer, has_credentials, _submission_action, first_time, _game_text("account_error_code", ""), _action_enabled("developer")]
	if snapshot == _state_snapshot:
		return
	_state_snapshot = snapshot
	_local_validation_visible = false
	_status_text = status
	_update_labels()
	_refresh_controls()

func _login_identifier() -> String:
	return _email.strip_edges() if not _email.strip_edges().is_empty() else _username.strip_edges()

func _submission_error(action: String) -> String:
	if action == "register":
		if _account_bool("account_has_credentials"):
			return "This account is registered. Sign out to create another account."
		return AccountScript.registration_error(_username, _email, _password)
	return AccountScript.login_error(_login_identifier(), _password)

func _action_enabled(action: String) -> bool:
	var busy := _account_bool("account_busy")
	var signed_in := _account_bool("account_signed_in")
	var configured := _account_bool("account_configured")
	match action:
		"login", "register":
			return configured and not busy and _submission_error(action).is_empty()
		"submit":
			return _action_enabled(_submission_action)
		"mode:login", "mode:register":
			return not busy
		"device":
			return configured and not busy
		"refresh":
			return signed_in and not busy
		"logout":
			return signed_in or busy
		"developer":
			return is_instance_valid(game) and game.has_method("can_open_developer_menu") and bool(game.call("can_open_developer_menu"))
		"close":
			return true
	return not busy

func _dispatch(action: String) -> void:
	if action == "submit":
		action = _submission_action
	if action in ["login", "register"] and not _account_bool("account_busy") and _account_bool("account_configured"):
		var validation := _submission_error(action)
		if not validation.is_empty():
			_local_validation_visible = true
			_status_text = validation + " [" + ErrorCodes.VALIDATION_CODE + "]"
			_update_labels()
			return
	if not _action_enabled(action):
		return
	if action == "close":
		set_open(false)
		return
	if action.begins_with("mode:"):
		_submission_action = action.trim_prefix("mode:")
		_mode_selected = true
		_local_validation_visible = false
		_status_text = _game_text("account_status", "Signed out")
		_update_labels()
		_refresh_controls()
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
			if game.has_method("account_login_credentials"):
				_set_field("password", "")
				game.call("account_login_credentials", identifier, submitted_password)
		"register":
			var username := _username.strip_edges()
			var email := _email.strip_edges()
			var submitted_password := _password
			if game.has_method("account_register"):
				_set_field("password", "")
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
		"developer":
			if game.has_method("open_developer_menu"):
				game.call("open_developer_menu")
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
	if _local_validation_visible:
		var validation := _submission_error(_submission_action)
		_local_validation_visible = not validation.is_empty()
		_status_text = validation + " [" + ErrorCodes.VALIDATION_CODE + "]" if _local_validation_visible else _game_text("account_status", "Signed out")
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
		if action == "developer":
			button.visible = _account_bool("account_is_developer")
		if action.begins_with("mode:"):
			button.set_pressed_no_signal(action == "mode:" + _submission_action)
	_set_world_action_visible("developer", _account_bool("account_is_developer"))
	_update_button_colors()

func _role_text() -> String:
	if not _account_bool("account_signed_in"):
		return "Signed out"
	var role := "Developer access" if _account_bool("account_is_developer") else "Player account"
	return role + (" · Registered account" if _account_bool("account_has_credentials") else " · Device account")

func _update_labels() -> void:
	var account_id := _game_text("account_id", "Not signed in")
	var role := _role_text()
	var code := ErrorCodes.VALIDATION_CODE if _local_validation_visible else _game_text("account_error_code", "")
	if _desktop_code != null:
		_desktop_code.text = "Support code: " + code
		_desktop_code.visible = not code.is_empty()
	var help := "Use Email + password, or clear Email to use Username.\nUse the same account on PC and Quest."
	if _submission_action == "register":
		if _account_bool("account_has_credentials"):
			help = "This account is already registered.\nSign out to create another account."
		elif _account_bool("account_signed_in"):
			help = "Choose a username, email and password.\nYour device's PlayFab ID stays the same."
		else:
			help = "Choose a username, email and password for your new account.\nAlready have an account? Choose Sign in."
	if first_time and _submission_action == "register" and not _account_bool("account_has_credentials"):
		help = "Make an account to use your player identity on PC and Quest.\nYou can continue as a guest and register later."
	if _desktop_heading != null:
		_desktop_heading.text = "Welcome, monke!" if first_time else "Your account"
	if _world_heading != null:
		_world_heading.text = "WELCOME, MONKE!" if first_time else "PRIMAL MONKE ACCOUNT"
	if _desktop_help != null:
		_desktop_help.text = help
	if _world_help != null:
		_world_help.text = help
	if _desktop_buttons.has("submit"):
		_desktop_buttons["submit"].text = "Register account" if _submission_action == "register" else "Sign in now"
	if _desktop_buttons.has("close"):
		_desktop_buttons["close"].text = "Continue as guest" if first_time else "Back"
	for button in _world_buttons:
		if button["action"] == "submit":
			button["label"].text = "REGISTER" if _submission_action == "register" else "SIGN IN"
		elif button["action"] == "close":
			button["label"].text = "GUEST" if first_time else "CLOSE"
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
		_world_role.text = role + ("  ·  " + code if not code.is_empty() else "")
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
		var selected := action == "field:" + _active_field or action == "mode:" + _submission_action or (action == "uppercase" and _uppercase) or (action == "symbols" and _symbols)
		if selected and _action_enabled(action):
			var material: StandardMaterial3D = button["material"]
			material.albedo_color = Color("527d4e")

func _desktop_field(parent: VBoxContainer, caption: String, field: String, secret := false) -> LineEdit:
	MenuTheme.label(parent, caption, 13, MenuTheme.MUTED)
	var control := LineEdit.new()
	control.max_length = INPUT_LIMITS[field]
	control.secret = secret
	MenuTheme.field(control)
	control.placeholder_text = "Create your monke name" if field == "username" else ("you@example.com" if field == "email" else "At least 6 characters")
	control.text_changed.connect(func(value: String): _set_field(field, value))
	control.focus_entered.connect(func(): _active_field = field)
	parent.add_child(control)
	return control

func _adapt_desktop_layout() -> void:
	if _desktop_fields != null:
		_desktop_fields.columns = 2 if get_viewport().get_visible_rect().size.x >= 700 else 1
	if _desktop_secondary != null:
		_desktop_secondary.columns = 3 if get_viewport().get_visible_rect().size.x >= 460 else 1

func _create_desktop_menu() -> void:
	_desktop_frame = MenuTheme.desktop_frame(self, "AccountOverlay", 40, 650)
	_canvas = _desktop_frame.canvas
	var content: VBoxContainer = _desktop_frame.content
	MenuTheme.label(content, "PRIMAL MONKE  /  PLAYER IDENTITY", 12, MenuTheme.ORANGE)
	_desktop_heading = MenuTheme.label(content, "Your account", 32)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	content.add_child(tabs)
	MenuTheme.button(self, tabs, "Create account", "mode:register")
	MenuTheme.button(self, tabs, "Sign in", "mode:login")
	_desktop_buttons["mode:register"].toggle_mode = true
	_desktop_buttons["mode:login"].toggle_mode = true
	_desktop_help = MenuTheme.label(content, "", 14, MenuTheme.MUTED, true)
	_desktop_fields = GridContainer.new()
	_desktop_fields.columns = 2
	_desktop_fields.add_theme_constant_override("h_separation", 14)
	_desktop_fields.add_theme_constant_override("v_separation", 8)
	content.add_child(_desktop_fields)
	var username_column := VBoxContainer.new()
	username_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desktop_fields.add_child(username_column)
	var email_column := VBoxContainer.new()
	email_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desktop_fields.add_child(email_column)
	_username_edit = _desktop_field(username_column, "Username · 3–20 characters", "username")
	_email_edit = _desktop_field(email_column, "Email", "email")
	_password_edit = _desktop_field(content, "Password (6–100 characters)", "password", true)
	_password_edit.text_submitted.connect(func(_value: String): _dispatch("submit"))
	var primary := HBoxContainer.new()
	content.add_child(primary)
	MenuTheme.button(self, primary, "Register account", "submit", true)
	var feedback := PanelContainer.new()
	feedback.add_theme_stylebox_override("panel", MenuTheme.style(Color("102c21"), Color("36553d"), 12))
	content.add_child(feedback)
	var feedback_padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		feedback_padding.add_theme_constant_override("margin_" + side, 10)
	feedback.add_child(feedback_padding)
	var feedback_content := VBoxContainer.new()
	feedback_content.add_theme_constant_override("separation", 4)
	feedback_padding.add_child(feedback_content)
	_desktop_role = MenuTheme.label(feedback_content, "", 13, MenuTheme.GREEN)
	_desktop_status = MenuTheme.label(feedback_content, "", 14, MenuTheme.CREAM, true)
	_desktop_status.custom_minimum_size.y = 32
	_desktop_code = MenuTheme.label(feedback_content, "", 12, MenuTheme.ORANGE)
	_desktop_address = MenuTheme.label(feedback_content, "", 11, MenuTheme.MUTED, true)
	var second_row := GridContainer.new()
	_desktop_secondary = second_row
	second_row.columns = 3
	second_row.add_theme_constant_override("h_separation", 8)
	second_row.add_theme_constant_override("v_separation", 6)
	content.add_child(second_row)
	MenuTheme.button(self, second_row, "Device account", "device", false, true)
	MenuTheme.button(self, second_row, "Refresh access", "refresh", false, true)
	MenuTheme.button(self, second_row, "Sign out", "logout", false, true)
	MenuTheme.button(self, content, "Dev tools", "developer")
	var close_row := HBoxContainer.new()
	content.add_child(close_row)
	MenuTheme.button(self, close_row, "Back", "close", false, true)
	MenuTheme.label(content, "Enter submits the selected form · F3 / left X: close", 12, MenuTheme.MUTED, true)
	get_viewport().size_changed.connect(_adapt_desktop_layout)
	_adapt_desktop_layout()

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldAccount"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, panel_size, -0.035, Color("102a22"))
	_world_box(Vector2(0, 1.135), Vector2(1.93, 0.014), -0.012, MenuTheme.ORANGE)
	_world_heading = _world_label("PRIMAL MONKE ACCOUNT", Vector2(0, 1.07), 41)
	_world_help = _world_label("", Vector2(0, 0.965), 22)
	_world_address = _world_label("", Vector2(0, 0.855), 28)
	_world_role = _world_label("", Vector2(0, 0.76), 27)
	_world_status = _world_label("", Vector2(0, 0.66), 24)
	_world_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_status.width = 1300.0
	var fields := ["username", "email", "password"]
	for index in range(fields.size()):
		var field: String = fields[index]
		_world_button("", "field:" + field, Vector2(0, 0.54 - index * 0.16), Vector2(1.95, 0.11))
		var label: Label3D = _world_buttons.back()["label"]
		label.font_size = 27
		_world_fields[field] = label
	_world_button("CREATE ACCOUNT", "mode:register", Vector2(-0.65, 0.055), Vector2(0.60, 0.11))
	_world_buttons.back()["label"].font_size = 25
	_world_button("SIGN IN", "mode:login", Vector2(0, 0.055), Vector2(0.60, 0.11))
	_world_button("REGISTER", "submit", Vector2(0.65, 0.055), Vector2(0.60, 0.11), Color("386d4b"))
	var secondary := [["DEVICE", "device"], ["REFRESH", "refresh"], ["SIGN OUT", "logout"], ["DEV TOOLS", "developer"], ["CLOSE", "close"]]
	for index in range(secondary.size()):
		_world_button(secondary[index][0], secondary[index][1], Vector2(-0.8 + index * 0.4, -0.105), Vector2(0.36, 0.11))
		_world_buttons.back()["label"].font_size = 23
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
