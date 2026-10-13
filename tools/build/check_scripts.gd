extends SceneTree
## Compiles every GDScript outside addons/ and exits non-zero if any fails.
## GUT skips a test script that fails to parse, so the unit runner calls this first.
## Usage: godot --headless --path <game> -s tools/build/check_scripts.gd

const SKIPPED_DIRS: Array[String] = ["res://addons", "res://.godot", "res://native"]


func _initialize() -> void:
	var paths: Array[String] = []
	_collect("res://", paths)
	var failed: Array[String] = []
	for path: String in paths:
		var script: GDScript = GDScript.new()
		script.source_code = FileAccess.get_file_as_string(path)
		script.take_over_path(path)
		if script.reload() != OK:
			failed.append(path)
	if failed.is_empty():
		print("check_scripts: %d scripts compiled cleanly" % paths.size())
		quit(0)
	else:
		printerr("check_scripts: %d of %d scripts failed to compile:" % [failed.size(), paths.size()])
		for path: String in failed:
			printerr("  " + path)
		quit(1)


func _collect(dir: String, out: Array[String]) -> void:
	if dir.trim_suffix("/") in SKIPPED_DIRS:
		return
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "gd":
			out.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), out)
