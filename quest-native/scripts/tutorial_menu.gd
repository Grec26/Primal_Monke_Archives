extends "res://scripts/lobby_menu.gd"

const ThemeScript = preload("res://scripts/menu_theme.gd")
const PREFERENCE_PATH := "user://primal_monke_onboarding.cfg"
const LESSON_COUNT := 6
var lesson := 0
var completed := false
var practice_active := false
var _exercise_done := false
var _practice_started := false
var _last_position := Vector3.ZERO
var _start_height := 0.0
var _distance := 0.0
var _start_score := 0
var _desktop_title: Label
var _desktop_body: Label
var _desktop_progress: Label
var _world_title: Label3D
var _world_body: Label3D
var _world_progress: Label3D
var _practice_canvas: CanvasLayer
var _practice_label: Label
var _practice_world: Label3D

func _init() -> void:
	toggle_key = KEY_F4
	# Tutorial is reachable from the main menu in a headset. Do not reserve a
	# controller button already used by the main/account/developer screens.
	toggle_hand = -1
	panel_size = Vector2(1.85, 1.5)

func _ready() -> void:
	super._ready()
	_create_practice_hud()
	var preferences := ConfigFile.new()
	if preferences.load(PREFERENCE_PATH) == OK:
		completed = bool(preferences.get_value("tutorial", "completed", false))
	refresh_status()

func _exit_tree() -> void:
	if is_instance_valid(_practice_world): _practice_world.queue_free()
	super._exit_tree()

func begin() -> void:
	lesson = 0
	practice_active = false
	_exercise_done = false
	_practice_started = false
	set_open(true)
	refresh_status()

func toggle() -> void:
	if _game_text("frontend_state", "main_menu") == "loading": return
	if not is_open and not practice_active and lesson == 0:
		begin()
	else:
		set_open(not is_open)

func set_open(value: bool) -> void:
	if value and _game_text("frontend_state", "main_menu") == "loading": return
	if value == is_open: return
	if value and is_instance_valid(game) and game.has_method("on_feature_menu_open"):
		game.call("on_feature_menu_open", self)
	super.set_open(value)
	if not value and is_instance_valid(game) and game.has_method("close_feature_menu"):
		game.call("close_feature_menu", self)
	if value and _desktop_buttons.has("next") and not _is_xr():
		_desktop_buttons["next"].grab_focus()
	_update_practice_hud()

func _action_enabled(action: String) -> bool:
	match action:
		"back": return lesson > 0
		"next": return lesson in [0, 4, 5] or _exercise_done
		"try": return lesson in [1, 2, 3] and (not is_instance_valid(game) or _game_text("network_mode", "offline") == "offline" or _game_text("frontend_state", "main_menu") == "playing")
		"skip", "close": return true
	return false

func _dispatch(action: String) -> void:
	if not _action_enabled(action): return
	if is_instance_valid(game) and game.has_method("play_ui_sound"):
		game.call("play_ui_sound", "click")
	match action:
		"back":
			lesson = maxi(0, lesson - 1)
			practice_active = false
			_exercise_done = false
		"next":
			if lesson == LESSON_COUNT - 1:
				_finish(false)
			else:
				lesson += 1
				practice_active = false
				_exercise_done = false
		"try": _start_exercise()
		"skip": _finish(true)
		"close": set_open(false)
	refresh_status()

func _start_exercise() -> void:
	practice_active = true
	_exercise_done = false
	_practice_started = false
	_distance = 0.0
	set_open(false)
	if is_instance_valid(game):
		if lesson == 3 and _game_text("network_mode", "offline") == "offline" and bool(game.get("finished")) and game.has_method("start_solo"):
			# A won or expired solo round has no taggable monkeys. Restart only
			# this offline exercise; never restart or leave a shared online round.
			game.call("start_solo")
		elif game.has_method("can_resume_play") and bool(game.call("can_resume_play")):
			game.call("resume_play")
		elif _game_text("network_mode", "offline") == "offline" and game.has_method("start_solo"):
			game.call("start_solo")

func _finish(skipped: bool) -> void:
	practice_active = false
	completed = completed or not skipped
	var preferences := ConfigFile.new()
	preferences.load(PREFERENCE_PATH)
	preferences.set_value("tutorial", "completed", completed)
	preferences.set_value("tutorial", "skipped", skipped)
	preferences.save(PREFERENCE_PATH)
	set_open(false)

func _lesson_title() -> String:
	return ["Welcome to the forest", "Move through the forest", "Jump and climb", "Tag a monkey", "Play with your friends", "You're ready to play!"][lesson]

func _lesson_body() -> String:
	var xr := _is_xr()
	match lesson:
		0: return "Learn movement, tagging and multiplayer in six short steps. Practice at your own pace. You can skip and replay this tutorial from the main menu."
		1: return "Press Try exercise. Put your hands on the ground or a wall and push your body forward. Move two metres to finish." if xr else "Press Try exercise. Use WASD to move. Hold right mouse and move the mouse to look around. Walk two metres to finish."
		2: return "Press Try exercise. Put a hand against a tree, rock or the ground. Pull or push against the surface to climb and launch. Make real hand contact to finish." if xr else "Press Try exercise. Press Space while on the ground to jump. Use the rocks as stepping stones. Jump above your starting height to finish."
		3: return "Press Try exercise. Chase a monkey and touch it with a tracked hand to tag it. Tag one monkey to finish." if xr else "Press Try exercise. Chase a monkey, move within reach and hold E to tag it. Tag one monkey to finish."
		4: return "Open Multiplayer and host or join the host's IPv4 address on the same Wi-Fi. Quest and PC share a lobby; the host starts the round. Voice starts off. Open Voice from the main menu (F6 on PC), enable listening, then unmute your microphone. On PC, hold V during captured gameplay to talk. Lobby voice reaches the room; game voice reaches nearby players within 14 metres. You can mute yourself or other players."
		5: return "You can now explore, climb and play tag. Your profile shows your level and picture. F1 or right B opens the main menu. Tutorial stays available there; on PC, F4 also opens it."
	return ""

func refresh_status() -> void:
	if _desktop_title == null: return
	_desktop_title.text = _lesson_title()
	_desktop_body.text = _lesson_body()
	_desktop_progress.text = "STEP %s / %s%s" % [lesson + 1, LESSON_COUNT, " · EXERCISE COMPLETE" if _exercise_done else ""]
	_world_title.text = _lesson_title().to_upper()
	_world_body.text = _lesson_body()
	_world_progress.text = _desktop_progress.text
	for action in _desktop_buttons:
		_desktop_buttons[action].disabled = not _action_enabled(action)
	_desktop_buttons["try"].visible = lesson in [1, 2, 3]
	_desktop_buttons["next"].text = "Finish tutorial" if lesson == LESSON_COUNT - 1 else "Next step"
	for button in _world_buttons:
		if button.action == "next": button.label.text = "FINISH" if lesson == LESSON_COUNT - 1 else "NEXT"
	_update_button_colors()

func _update_labels() -> void:
	# The parent invokes this during _ready before lesson widgets are complete.
	if _desktop_title != null and _world_title != null: refresh_status()

func _process(delta: float) -> void:
	super._process(delta)
	if practice_active and not is_open:
		_observe_exercise()
	_update_practice_hud()

func _observe_exercise() -> void:
	var player := _player()
	if player == null or _game_text("frontend_state", "main_menu") != "playing" or not bool(player.get("input_allowed")): return
	var position := player.global_position
	if not _practice_started:
		_practice_started = true
		_last_position = position
		_start_height = position.y
		_start_score = _tag_total()
		return
	var displacement := position - _last_position
	_last_position = position
	# Teleports/respawns do not count as movement practice.
	if displacement.length() < 1.5:
		_distance += Vector2(displacement.x, displacement.z).length()
	match lesson:
		1: _exercise_done = _distance >= 2.0
		2: _exercise_done = bool(player.get("contacts")) if _is_xr() else position.y > _start_height + 0.25
		3:
			var tags := _tag_total()
			# Starting a new network round resets its scores. Rebase the exercise
			# rather than crediting a teammate's tag or waiting for the old score.
			if tags < _start_score: _start_score = tags
			_exercise_done = tags > _start_score
	if _exercise_done:
		practice_active = false
		if game.has_method("play_ui_sound"): game.call("play_ui_sound", "success")
		set_open(true)
		refresh_status()

func _tag_total() -> int:
	# Root increments this monotonic counter only for locally attributed tags
	# accepted by the host. Shared round scores and cosmetic XP never count.
	return int(game.get("local_tag_count"))

func _update_practice_hud() -> void:
	if _practice_canvas == null: return
	var visible := practice_active and not is_open and _game_text("frontend_state", "main_menu") == "playing"
	_practice_canvas.visible = visible and not _is_xr()
	if is_instance_valid(_practice_world): _practice_world.visible = visible and _is_xr()
	var text := "TUTORIAL · %s\n%s\nF4 / Main menu → Tutorial: instructions · Skip is always available." % [_lesson_title(), _practice_hint()]
	_practice_label.text = text
	if is_instance_valid(_practice_world): _practice_world.text = "TUTORIAL · " + _practice_hint()

func _practice_hint() -> String:
	match lesson:
		1: return "Move %0.1f / 2.0 metres. %s" % [minf(_distance, 2.0), "Push with your hands." if _is_xr() else "WASD + hold right mouse to look."]
		2: return "Put a tracked hand against a solid surface." if _is_xr() else "Press Space on the ground to jump."
		3: return "Touch a monkey with your hand." if _is_xr() else "Chase a monkey; hold E within reach."
	return ""

func _create_desktop_menu() -> void:
	var frame := ThemeScript.desktop_frame(self, "TutorialOverlay", 42, 670)
	_canvas = frame.canvas
	var content: VBoxContainer = frame.content
	_desktop_progress = ThemeScript.label(content, "", 13, ThemeScript.ORANGE)
	_desktop_title = ThemeScript.label(content, "", 30, ThemeScript.CREAM, true)
	_desktop_body = ThemeScript.label(content, "", 19, ThemeScript.MUTED, true)
	_desktop_body.custom_minimum_size.y = 160
	ThemeScript.button(self, content, "Try exercise", "try", true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	ThemeScript.button(self, row, "Back", "back")
	ThemeScript.button(self, row, "Next step", "next", true)
	ThemeScript.button(self, row, "Close", "close")
	ThemeScript.button(self, content, "Skip tutorial and play", "skip", false, true)
	ThemeScript.label(content, "Tutorial is optional. Reopen it from the main menu or press F4.", 13, ThemeScript.MUTED, true)

func _create_world_menu() -> void:
	_world_panel = Node3D.new()
	_world_panel.name = "WorldTutorial"
	add_child(_world_panel)
	_world_box(Vector2.ZERO, panel_size, -0.035, ThemeScript.FOREST)
	_world_progress = _world_label("", Vector2(0, 0.61), 24)
	_world_progress.modulate = ThemeScript.ORANGE
	_world_title = _world_label("", Vector2(0, 0.49), 36)
	_world_body = _world_label("", Vector2(0, 0.18), 27)
	_world_body.width = 1100
	_world_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_button("TRY EXERCISE", "try", Vector2(0, -0.16), Vector2(1.65, 0.12), Color("426d3b"))
	_world_button("BACK", "back", Vector2(-0.57, -0.34), Vector2(0.5, 0.12))
	_world_button("NEXT", "next", Vector2(0, -0.34), Vector2(0.5, 0.12), Color("426d3b"))
	_world_button("CLOSE", "close", Vector2(0.57, -0.34), Vector2(0.5, 0.12))
	_world_button("SKIP TUTORIAL", "skip", Vector2(0, -0.52), Vector2(1.65, 0.1))
	_world_label("Aim + trigger · Replay from main menu", Vector2(0, -0.66), 22)
	ThemeScript.world_text(_world_panel)
	_pointer = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.009
	dot.height = 0.018
	_pointer.mesh = dot
	_pointer.material_override = _material(ThemeScript.GREEN)
	_pointer.material_override.render_priority = 3
	add_child(_pointer)

func _create_practice_hud() -> void:
	_practice_canvas = CanvasLayer.new()
	_practice_canvas.layer = 8
	add_child(_practice_canvas)
	_practice_label = Label.new()
	_practice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_practice_label.add_theme_color_override("font_color", ThemeScript.CREAM)
	_practice_label.add_theme_font_size_override("font_size", 16)
	_practice_label.add_theme_color_override("font_shadow_color", ThemeScript.FOREST)
	_practice_label.add_theme_constant_override("shadow_offset_x", 2)
	_practice_label.add_theme_constant_override("shadow_offset_y", 2)
	_practice_canvas.add_child(_practice_label)
	_practice_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_practice_label.position = Vector2(24, -105)
	var player := _player()
	var head: Node3D = player.get("head") as Node3D if player != null else null
	if head != null:
		_practice_world = Label3D.new()
		_practice_world.position = Vector3(0, -0.34, -0.85)
		_practice_world.font_size = 22
		_practice_world.pixel_size = 0.0008
		_practice_world.modulate = ThemeScript.CREAM
		_practice_world.outline_size = 5
		_practice_world.no_depth_test = true
		_practice_world.width = 920
		_practice_world.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(_practice_world)
	_update_practice_hud()
