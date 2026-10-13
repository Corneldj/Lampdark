extends GutTest
## The running engine must match the pin in versions.json (FND-01).

const VERSIONS_PATH: String = "res://versions.json"


func _load_versions() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VERSIONS_PATH))
	assert_true(parsed is Dictionary, "versions.json parses to an object")
	if parsed is Dictionary:
		var versions: Dictionary = parsed
		return versions
	return {}


func _section(name: String) -> Dictionary:
	var section: Variant = _load_versions().get(name, {})
	if section is Dictionary:
		var as_dict: Dictionary = section
		return as_dict
	return {}


func test_engine_matches_pin() -> void:
	var info: Dictionary = Engine.get_version_info()
	var running: String = "%d.%d.%d-%s" % [info["major"], info["minor"], info["patch"], info["status"]]
	assert_eq(running, str(_section("engine").get("version")), "running engine matches the pin")


func test_pin_records_checksums() -> void:
	var pin: Dictionary = _section("engine")
	var sums_value: Variant = pin.get("sha512", {})
	assert_true(sums_value is Dictionary, "engine.sha512 is an object")
	var sums: Dictionary = sums_value if sums_value is Dictionary else {}
	var version: String = str(pin.get("version", ""))
	for platform: String in ["linux.x86_64.zip", "win64.exe.zip", "export_templates.tpz"]:
		var key: String = "Godot_v%s_%s" % [version, platform]
		var digest: String = str(sums.get(key, ""))
		assert_eq(digest.length(), 128, "SHA-512 recorded for " + key)


func test_gut_matches_pin() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load("res://addons/gut/plugin.cfg"), OK, "GUT plugin.cfg loads")
	var installed: String = str(cfg.get_value("plugin", "version", ""))
	assert_eq(installed, str(_section("gut").get("version")), "GUT version matches the pin")
