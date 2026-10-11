extends SceneTree

# Exercise the real game's terrain, menus, camera, playtest, and local files.
# No network room, account request, microphone, or real XR tracker is opened.
var checks := 0
var failures := 0
var scratch := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func settle(frames := 3) -> void:
	for index in range(frames): await physics_frame

func run() -> void:
	scratch = "/tmp/primal-monke-creator-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var game = load("res://forest.tscn").instantiate()
	root.add_child(game)
	await settle()
	var creator: Node3D = game.map_creator
	check(is_instance_valid(creator) and creator.document != null and is_instance_valid(creator.menu), "forest creates a map document, editor controls, and a renderer")
	creator.document.storage_directory = scratch
	check(not creator.active and not creator.renderer.visible and not creator.menu.is_open, "map creation starts closed")
	check(creator.renderer.solids.size() == 4, "editor owns its four fixed boundary walls")
	for body in creator.renderer.solids: check(body.collision_layer == 0, "closed editor boundary cannot block the forest")
	check(not game.account.busy and not game.voice.enabled and game.voice.mic_muted, "map startup does not sign in or open voice")
	check(game.main_menu._desktop_buttons.has("map_creator"), "main menu exposes map creation")
	game.frontend_state = "loading"
	check(not creator.begin() and not creator.active, "loading blocks direct editor entry")
	game.frontend_state = "main_menu"
	game.session.mode = "client"
	check(not creator.begin() and not creator.active, "connected client cannot replace its lobby map")
	game.session.mode = "host"
	check(not creator.begin() and not creator.active, "connected host cannot replace its lobby map")
	game.session.mode = "offline"
	check(creator.begin() and creator.active and creator.is_open, "offline player enters map creation")
	await settle()
	check(game.frontend_state == "creating" and not game.player.input_allowed, "editor pauses player locomotion")
	check(creator._camera.current and not game.player.head.current, "desktop editor uses its own fly camera")
	check(not game.main_menu.is_open and not game.lobby.is_open and not game.account_menu.is_open, "editor closes ordinary game overlays")
	check(game.get_node("ForestFloor").collision_layer == 1, "custom map keeps the original walkable ground")
	for body in game.forest_map.solids:
		if body.name != "ForestFloor": check(body.collision_layer == 0, "default obstacle is disabled while editing")
	for bot in game.bots: check(not bot.visible and not bot.active, "editor disables each bot")
	for menu in [game.main_menu, game.lobby, game.account_menu, game.settings_menu, game.profile_menu, game.voice_menu, game.tutorial]:
		menu.set_open(true)
		check(not menu.is_open, "ordinary overlay cannot steal editor input")
	await test_editing(game, creator)
	await test_files(creator)
	await test_playtest(game, creator)
	await test_world_pages(game, creator)
	await test_exit(game, creator)
	game.voice.shutdown()
	game.queue_free()
	await process_frame
	for slot in range(1, 7):
		DirAccess.remove_absolute(scratch.path_join("slot-%d.json" % slot))
		DirAccess.remove_absolute(scratch.path_join("slot-%d.json.tmp" % slot))
	DirAccess.remove_absolute(scratch)
	print("Map creator checks complete; %s checks, failures: %s" % [checks, failures])
	quit(0 if failures == 0 else 1)

func test_editing(game: Node3D, creator: Node3D) -> void:
	check(not creator.choose_kind("executable"), "palette rejects unsupported objects")
	check(creator.choose_kind("block") and creator.placing, "block palette enters placement mode")
	var id: int = creator.place_at_surface(Vector3(4.1, 0, 0.1))
	check(id >= 1 and creator.document.object_count == 1 and creator.selected_id == id, "placing selects the newly created object")
	check(creator._vector(creator.selected_object().position).is_equal_approx(Vector3(4, 1, 0)), "ground placement snaps X/Z and preserves half-height")
	check(creator.document.dirty and creator.menu._summary.text.contains("Unsaved changes"), "object placement marks the map visibly unsaved")
	await settle()
	var hit: Dictionary = creator.ray_hit(Vector3(4, 6, 0), Vector3.DOWN)
	check(not hit.is_empty() and hit.collider.get_meta("map_object_id", -1) == id, "placed object has a selectable real collider")
	creator.set_select_mode()
	creator.select_object(-1)
	creator._apply_world_ray({"origin": Vector3(4, 6, 0), "direction": Vector3.DOWN})
	check(creator.selected_id == id and creator.renderer.selected_id == id, "world ray selects the collider and displays its outline")
	check(creator.nudge(0, 0.5), "position nudge applies to the selection")
	check(creator.resize_axis(2, 0.5), "size nudge applies to the selection")
	check(creator.rotate_selected() and is_equal_approx(float(creator.selected_object().yaw), 45), "rotation changes the selected object's yaw")
	check(creator.color_selected() and int(creator.selected_object().color) == 4, "color control cycles the selected object palette")
	var prior: Dictionary = creator.selected_object()
	check(not creator.update_selected({"position": Vector3(NAN, 0, 0)}) and creator.selected_object() == prior, "non-finite inspector edits cannot corrupt a map")
	check(not creator.update_selected({"size": Vector3(9, 1, 1)}) and creator.selected_object() == prior, "oversized inspector edits cannot corrupt a map")
	check(creator.history_action("undo") and int(creator.selected_object().color) == 3, "undo restores the prior visible object color")
	check(creator.history_action("redo") and int(creator.selected_object().color) == 4, "redo restores the accepted color edit")
	var duplicate: int = creator.duplicate_selected()
	check(duplicate != id and duplicate >= 1 and creator.document.object_count == 2 and creator.selected_id == duplicate, "duplicate gets a new ID and becomes the selection")
	check(creator.nudge(0, 3), "duplicate can move independently")
	check(creator.delete_selected() and creator.document.object_count == 1 and creator.selected_id == -1, "delete removes only the selected copy")
	check(creator.history_action("undo") and creator.document.object_count == 2, "undo brings back a deleted object")
	creator.cycle_selection()
	check(creator.selected_id == id, "next-object control starts at the first object")
	creator.cycle_selection()
	check(creator.selected_id == duplicate, "next-object control cycles through stable IDs")
	check(creator.menu._fields["size:0"].min_value == 0.25 and creator.menu._fields["size:0"].max_value == 8, "size inspector exposes the actual supported limits")
	check(creator.menu._fields["position:0"].min_value == -14 and creator.menu._fields["position:0"].max_value == 14, "position inspector exposes the actual supported limits")
	creator.menu._fields["position:2"].value = 3
	check(is_equal_approx(creator._vector(creator.selected_object().position).z, 3), "actual SpinBox signal updates the selected object")
	creator.menu._desktop_buttons.rotate.emit_signal("pressed")
	check(is_equal_approx(float(creator.selected_object().yaw), 90), "actual desktop rotate button updates the object")
	var grid: float = creator.grid_step
	creator.cycle_grid()
	check(creator.grid_step != grid and creator.menu._desktop_buttons.grid.text.contains("1.00"), "grid control updates its visible spacing")
	creator.cycle_grid()
	creator.cycle_grid()
	check(is_equal_approx(creator.grid_step, grid), "grid cycles through its three supported values")
	creator.choose_kind("platform")
	await settle()
	var ray := {"origin": Vector3(10, 6, 0), "direction": Vector3.DOWN}
	creator._update_preview(ray)
	check(creator._ghost.visible and creator._preview_valid, "valid surface shows a valid placement preview")
	creator._update_preview(ray)
	check(creator._preview_valid, "stationary valid preview remains valid on subsequent frames")
	creator._update_preview({"origin": Vector3(0, 6, -5), "direction": Vector3.DOWN})
	check(creator._ghost.visible and not creator._preview_valid, "reserved spawn headroom shows an invalid preview")
	check(creator.place_at_surface(Vector3(0, 0, -5)) == -1, "spawn placement is rejected by the same map rules")
	creator.choose_kind("tree")
	creator._update_preview({"origin": Vector3(14.5, 6, 0), "direction": Vector3.DOWN})
	check(not creator._preview_valid, "preview obeys center limits even when the extent fits inside the wall")
	check(creator.place_at_surface(Vector3(INF, 0, 0)) == -1, "placement rejects non-finite ray surfaces")
	creator.set_select_mode()
	check(not creator._ghost.visible, "selection mode hides the placement preview")
	check(game.network_mode == "offline", "editing has not opened a network room")

func test_files(creator: Node3D) -> void:
	check(creator.rename_map("Creator integration map"), "map name is editable")
	creator.select_slot(4)
	check(creator.save() and not creator.document.dirty, "map save creates a clean local slot")
	check(FileAccess.file_exists(scratch.path_join("slot-4.json")) and not FileAccess.file_exists(scratch.path_join("slot-4.json.tmp")), "map save completes its atomic replacement")
	check(creator.menu._slot_description().begins_with("Slot 4 · Creator integration map"), "slot summary shows the saved name once")
	var saved: Dictionary = creator.document.data
	check(creator.rename_map("Unsaved draft"), "new map name creates unsaved changes")
	check(not creator.request_action("new:blank") and creator.pending_action == "new:blank" and creator.menu._confirm.visible, "new-map request protects unsaved work")
	check(not creator.update_selected({"yaw": 120}) and not creator.history_action("undo"), "unsaved confirmation prevents hidden edit actions")
	check(creator.resolve_pending("cancel") and creator.pending_action.is_empty() and creator.document.data.name == "Unsaved draft", "cancel keeps the entire draft")
	check(not creator.request_action("load"), "load request protects the unsaved draft")
	check(creator.resolve_pending("discard") and creator.document.data == saved and not creator.document.dirty, "discard and load restores the saved slot")
	creator.select_slot(3)
	check(not creator.request_action("load") and creator.document.data == saved and creator.status.contains("empty"), "failed empty-slot load preserves the current map with feedback")
	creator.select_slot(6)
	check(creator.save(), "another local save slot is supported")
	check(creator.request_action("new:climb") and creator.document.object_count > 0, "climbing starter is available through the editor")
	check(creator.document.dirty and creator.document.data.name == "Climbing garden", "starter map is marked unsaved with its descriptive name")
	creator.menu._dispatch("new_parkour")
	check(creator.pending_action == "new:parkour", "actual starter button asks before discarding an edited map")
	check(creator.resolve_pending("save") and creator.document.data.name == "Canopy circuit", "save-and-continue stores the previous map before starting another")
	check(creator.document.slot_summary(6).contains("Climbing garden"), "save-and-continue retains the old map in the selected slot")
	creator.save()
	creator.menu._tabs.current_tab = 2
	creator.menu._name_edit.grab_focus()
	creator.menu._name_edit.text = "Keyboard draft name"
	check(not creator.request_exit() and creator.pending_action == "exit" and creator.document.data.name == "Keyboard draft name", "exit commits a focused map name before deciding whether to confirm")
	creator.resolve_pending("cancel")
	creator.menu._name_edit.release_focus()
	creator.menu._name_edit.text = ""
	check(not creator.menu._commit_name() and creator.status.contains("1–48"), "invalid map name has actionable feedback")
	creator.menu._name_edit.text = "Keyboard draft name"
	check(creator.menu._commit_name(), "valid map name can resume the workflow")
	creator.save()

func test_playtest(game: Node3D, creator: Node3D) -> void:
	creator.cycle_selection()
	check(creator.selected_id >= 1 and creator.renderer.selected_id == creator.selected_id, "map selection is visible before playtest")
	game.remaining = 77
	game.score = 2
	var xp: int = game.profile.xp
	check(creator.start_playtest() and creator.playtesting and not creator.is_open, "playtest closes editor controls")
	check(creator.renderer.selected_id == -1, "playtest hides editor selection outlines")
	await settle(8)
	check(game.frontend_state == "map_playtest" and game.player.input_allowed and game.player.head.current and not creator._camera.current, "playtest returns control to the real player and camera")
	check((-game.player.head.global_basis.z).z > 0.9 and is_equal_approx(game.player.desktop_pitch, 0), "desktop playtest faces the custom arena from its spawn")
	check(is_equal_approx(game.remaining, 77) and game.score == 2 and game.profile.xp == xp, "custom playtest advances no timer, score, or XP")
	for bot in game.bots: check(not bot.active and not bot.visible, "playtest keeps each round bot inactive")
	game.tag_bot(game.bots[0])
	check(game.score == 2 and game.profile.xp == xp, "custom-map playtest cannot farm bot rewards")
	check(not creator.choose_kind("wall") and not creator.update_selected({"yaw": 90}), "playtest cannot mutate map objects")
	check(not game.can_open_lobby_menu() and not game.can_open_map_creator(), "playtest keeps network and editor entry isolated")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F8
	key.pressed = true
	creator._input(key)
	await settle()
	check(not creator.playtesting and creator.is_open and game.frontend_state == "creating" and creator._camera.current, "F8 returns from playtest to the same editor document")
	check(creator.renderer.selected_id == creator.selected_id, "returning from playtest restores the editor selection")
	check(not game.player.input_allowed and not creator._test_canvas.visible, "returning to the editor pauses walking and hides the playtest notice")
	key = InputEventKey.new()
	key.physical_keycode = KEY_F8
	key.pressed = true
	creator._input(key)
	check(not creator.is_open and creator.active, "F8 can hide tools while keeping map editing active")
	creator.set_open(true)

func test_world_pages(game: Node3D, creator: Node3D) -> void:
	game.player.xr_running = true
	creator.set_open(false)
	creator.set_open(true)
	var menu: Node3D = creator.menu
	check(menu._world_panel.visible and not menu._canvas.visible, "headset editing presents the world panel instead of desktop controls")
	for page in range(4):
		menu._page = page
		menu.refresh_status()
		for index in range(menu._world_buttons.size()):
			var button: Dictionary = menu._world_buttons[index]
			if not button.mesh.visible: continue
			var center: Vector2 = button.rect.get_center()
			var ray_origin: Vector3 = menu._world_panel.to_global(Vector3(center.x, center.y, 1))
			var ray_direction: Vector3 = -menu._world_panel.global_basis.z
			var hit: Dictionary = menu._intersect_panel(ray_origin, ray_direction)
			check(not hit.is_empty() and hit.button == index, "VR page %d visible action %s owns its ray target" % [page + 1, button.action])
	menu._page = 0
	menu.refresh_status()
	menu._dispatch("kind:wall")
	check(creator.selected_kind == "wall" and creator.placing, "VR palette can select a wall")
	menu._dispatch("close")
	check(not creator.is_open and not menu._world_panel.visible, "VR build-in-world button hides the panel")
	creator.set_open(true)
	creator.rename_map("VR dirty draft")
	creator.request_exit()
	check(menu._world_title.text == "UNSAVED CHANGES", "VR exit displays the unsaved-work panel")
	for button in menu._world_buttons:
		check(button.mesh.visible == str(button.action).begins_with("confirm_"), "VR confirmation hides unrelated action %s" % button.action)
	menu._dispatch("confirm_cancel")
	check(creator.active and creator.pending_action.is_empty(), "VR confirmation can keep editing")
	game.player.xr_running = false
	creator.set_open(false)
	creator.set_open(true)
	creator.save()

func test_exit(game: Node3D, creator: Node3D) -> void:
	var data: Dictionary = creator.document.data
	check(creator.request_exit() and not creator.active, "saved map can return to the main menu")
	await settle()
	check(game.frontend_state == "main_menu" and game.main_menu.is_open and game.player.head.current, "editor exit restores the main menu and game camera")
	check(not creator.renderer.visible and not creator.menu.is_open and not creator._ghost.visible and not creator._world_cursor.visible and not creator._world_ray.visible, "editor exit hides every editing visual")
	for body in creator.renderer.solids: check(body.collision_layer == 0, "editor exit disables custom object and wall collision")
	for body in game.forest_map.solids: check(body.collision_layer == 1, "editor exit restores every default arena collider")
	check(not creator.choose_kind("tree") and not creator.save() and not creator.start_playtest(), "closed creator cannot edit, save, or start playtest")
	check(creator.begin() and creator.document.data == data, "opening the editor again retains the local working map")
	for body in creator.renderer.solids: check(body.collision_layer == 1, "reopening restores each custom collider")
	creator.rename_map("Discarded name")
	check(not creator.request_exit() and creator.pending_action == "exit", "leaving an unsaved map requires a concrete choice")
	check(creator.resolve_pending("discard") and not creator.active, "discard can finish the editor session")
	check(creator.begin() and creator.document.data == data and not creator.document.dirty, "reopening after discard restores the saved baseline, without discarded edits")
	creator.request_exit()
