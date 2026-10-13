extends GutTest
## lampblack_core is loaded and 64-bit values cross the boundary intact (FND-02).

const INT64_MAX: int = 0x7FFFFFFFFFFFFFFF
const INT64_MIN: int = -0x7FFFFFFFFFFFFFFF - 1


func _call(method: StringName, args: Array = []) -> Variant:
	var call_args: Array = [&"LbCoreInfo", method]
	call_args.append_array(args)
	return Callable(ClassDB, &"class_call_static").callv(call_args)


func test_class_is_registered() -> void:
	assert_true(ClassDB.class_exists(&"LbCoreInfo"), "lampblack_core loaded")


func test_add_i64() -> void:
	var sum: int = _call(&"add_i64", [2, 3])
	assert_eq(sum, 5)


func test_int64_extremes_wrap() -> void:
	var wrapped_up: int = _call(&"add_i64", [INT64_MAX, 1])
	assert_eq(wrapped_up, INT64_MIN, "max + 1 wraps to min")
	var wrapped_down: int = _call(&"add_i64", [INT64_MIN, -1])
	assert_eq(wrapped_down, INT64_MAX, "min - 1 wraps to max")
	var identity: int = _call(&"add_i64", [INT64_MIN, 0])
	assert_eq(identity, INT64_MIN, "no truncation at the boundary")


func test_build_type_matches_template() -> void:
	var build_type: String = _call(&"build_type")
	var has_tools: bool = _call(&"has_debug_tools")
	var expected: String = "debug" if OS.is_debug_build() else "release"
	assert_eq(build_type, expected)
	assert_eq(has_tools, OS.is_debug_build())


func test_version_format() -> void:
	var version: String = _call(&"version")
	var pattern: RegEx = RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+(-[0-9A-Za-z.]+)?\\+([0-9a-f]{7}|nogit)$")
	assert_not_null(pattern.search(version), "version '%s' is <semver>+<sha>" % version)
	var pinned: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://versions.json"))
	var game_version: String = str(Variants.dict(Variants.dict(pinned).get("game", {})).get("version", ""))
	assert_true(version.begins_with(game_version + "+"), "starts with versions.json's game version")
