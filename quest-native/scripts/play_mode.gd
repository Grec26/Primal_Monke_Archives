extends RefCounted

static func requested(args: PackedStringArray, android: bool) -> String:
	if android: return "quest"
	for argument in args:
		if argument == "--play-mode=desktop": return "desktop"
		if argument == "--play-mode=pcvr": return "pcvr"
	return "auto"

static func launch_arguments(mode: String, editor_path := "") -> PackedStringArray:
	var result := PackedStringArray()
	if not editor_path.is_empty(): result.append_array(["--path", editor_path])
	result.append_array(["--xr-mode", "on" if mode == "pcvr" else "off", "--", "--play-mode=" + mode])
	return result
