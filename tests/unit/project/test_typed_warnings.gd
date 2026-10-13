extends GutTest
## Typed-GDScript warnings are errors everywhere except addons/ (FND-01).

const FIXTURE_PATH: String = "res://tests/fixtures/untyped_fixture.gd.txt"
const STRICT_DIRS: Array[String] = ["server", "client", "shared"]
const UNTYPED_ERROR: String = "has no static type"


func _fixture_source() -> String:
	var text: String = FileAccess.get_file_as_string(FIXTURE_PATH)
	assert_ne(text, "", "fixture is readable")
	return text


## Compiles the fixture as though it lived at res_path.
func _reload_as(res_path: String) -> Error:
	var script: GDScript = GDScript.new()
	script.source_code = _fixture_source()
	script.take_over_path(res_path)
	return script.reload()


func test_untyped_var_fails_from_user_dir() -> void:
	var file: FileAccess = FileAccess.open("user://untyped_fixture.gd", FileAccess.WRITE)
	file.store_string(_fixture_source())
	file.close()
	var script: GDScript = load("user://untyped_fixture.gd") as GDScript
	assert_false(script != null and script.can_instantiate(), "untyped fixture does not load")
	assert_engine_error(UNTYPED_ERROR)
	assert_engine_error("Failed to load script")
	DirAccess.remove_absolute("user://untyped_fixture.gd")


func test_untyped_var_fails_in_strict_dirs() -> void:
	for dir: String in STRICT_DIRS:
		var err: Error = _reload_as("res://%s/__untyped_fixture.gd" % dir)
		assert_ne(err, OK, "untyped var fails to load under %s/" % dir)
		assert_engine_error(UNTYPED_ERROR)


func test_untyped_var_loads_in_addons() -> void:
	var err: Error = _reload_as("res://addons/__untyped_fixture.gd")
	assert_eq(err, OK, "untyped var loads under addons/")
