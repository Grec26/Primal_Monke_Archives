extends Node3D

const ModeScript = preload("res://scripts/play_mode.gd")
const LoadingScript = preload("res://scripts/loading_screen.gd")
const FOREST_SCENE := "res://forest.tscn"

var loading: LoadingScript
var _request_active := false
var _finishing := false
var _failed := false
var _retry_hand: XRController3D
var _trigger_held := false

func _ready() -> void:
	var mode := ModeScript.requested(OS.get_cmdline_user_args(), OS.has_feature("android"))
	var xr := XRServer.find_interface("OpenXR")
	if mode != "desktop" and DisplayServer.get_name() != "headless" and xr != null:
		if xr.is_initialized() or xr.initialize():
			get_viewport().use_xr = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("122b23")
	world.environment = environment
	add_child(world)
	var origin := XROrigin3D.new()
	add_child(origin)
	var camera := XRCamera3D.new()
	camera.current = true
	origin.add_child(camera)
	_retry_hand = XRController3D.new()
	_retry_hand.tracker = "right_hand"
	_retry_hand.pose = "aim"
	origin.add_child(_retry_hand)
	loading = LoadingScript.new()
	loading.name = "LoadingScreen"
	camera.add_child(loading)
	loading.retry_requested.connect(_retry_loading)
	loading.show_loading("Preparing your forest")
	call_deferred("_begin_loading")

func _begin_loading() -> void:
	# Present the screen before loading or instantiating the world. The progress
	# bar follows ResourceLoader rather than a timer or an invented percentage.
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	var error := ResourceLoader.load_threaded_request(FOREST_SCENE, "PackedScene", false)
	if error != OK:
		_show_failure()
		return
	_request_active = true
	_failed = false

func _process(_delta: float) -> void:
	if _request_active and not _finishing:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(FOREST_SCENE, progress)
		if not progress.is_empty(): loading.set_progress(float(progress[0]))
		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				_finishing = true
				_finish_loading.call_deferred()
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_show_failure()
	if _failed and get_viewport().use_xr and is_instance_valid(_retry_hand):
		var pressed := _retry_hand.get_has_tracking_data() and (_retry_hand.is_button_pressed("trigger_click") or _retry_hand.get_float("trigger") > 0.7)
		if pressed and not _trigger_held: _retry_loading()
		_trigger_held = pressed

func _finish_loading() -> void:
	loading.set_progress(1.0, "Opening your forest")
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	var resource := ResourceLoader.load_threaded_get(FOREST_SCENE) as PackedScene
	if resource == null:
		_show_failure()
		return
	var forest := resource.instantiate()
	if forest == null:
		_show_failure()
		return
	get_tree().root.add_child(forest)
	get_tree().current_scene = forest
	queue_free()

func _show_failure() -> void:
	_request_active = false
	_finishing = false
	_failed = true
	loading.show_error("The forest could not open. Try again, or reinstall the latest game download.")
	_trigger_held = true

func _retry_loading() -> void:
	if not _failed: return
	_failed = false
	loading.show_loading("Preparing your forest")
	_begin_loading()

func _unhandled_key_input(event: InputEvent) -> void:
	if _failed and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		_retry_loading()
		get_viewport().set_input_as_handled()
