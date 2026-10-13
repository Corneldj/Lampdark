extends RefCounted
## Writes a tuning fixture (tests/fixtures/tuning/<name>.json) out as a data directory under
## user://, so the loader reads it exactly as it reads data/tuning.

const FIXTURES: String = "res://tests/fixtures/tuning"
const ROOT: String = "user://tuning_fixtures"


static func read(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES.path_join(name + ".json")))
	return Variants.dict(parsed)


## Writes the fixture's files and units to user://tuning_fixtures/<name>/ and returns the path.
static func write(name: String) -> String:
	var fixture: Dictionary = read(name)
	var dir: String = ROOT.path_join(name)
	clear(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	_store(dir.path_join("_units.json"), {"units": fixture.get("units", [])})
	var files: Dictionary = Variants.dict(fixture.get("files", {}))
	for file: Variant in files.keys():
		_store(dir.path_join(str(file)), files[file])
	return dir


static func store(path: String, data: Variant) -> void:
	_store(path, data)


static func _store(path: String, data: Variant) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


static func clear(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		clear(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


## A valid set loaded from the valid_set fixture.
static func valid_set() -> TuningSet:
	var tuning: TuningSet = TuningSet.new()
	var errors: Array[String] = tuning.load_directory(write("valid_set"), false)
	assert(errors.is_empty(), "valid_set fixture must load: %s" % [errors])
	return tuning
