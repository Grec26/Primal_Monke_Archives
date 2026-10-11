extends SceneTree

func _initialize() -> void:
	var action_map := OpenXRActionMap.new()
	action_map.create_default_action_sets()
	var result := ResourceSaver.save(action_map, "res://openxr_action_map.tres")
	if result != OK:
		push_error("Could not save OpenXR action map: %s" % result)
		quit(1)
	else:
		print("Default OpenXR action map generated.")
		quit(0)
