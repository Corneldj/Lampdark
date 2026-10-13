extends GutTest
## The real data in data/tuning: every domain file validates, and the generated files are
## fresh (FND-05).

const GenKeys = preload("res://tools/build/gen_tuning_keys.gd")

var tuning: TuningSet


func before_all() -> void:
	tuning = TuningSet.new()
	_errors = tuning.load_directory(TuningSet.DATA_DIR)

var _errors: Array[String] = []


func test_every_domain_file_validates() -> void:
	assert_eq(_errors, [] as Array[String])
	for domain: String in TuningSchema.DOMAINS:
		assert_true(FileAccess.file_exists(TuningSet.DATA_DIR.path_join(domain + ".json")), "%s.json exists" % domain)
	assert_eq(TuningSchema.DOMAINS.size(), 29)


func test_edge_open_probability_ppm() -> void:
	assert_eq(tuning.ppm(&"mine.edge_open_probability"), 600000)


func test_tick_rate_is_client_visible() -> void:
	assert_eq(str(Variants.dict(tuning.entries["net.tick_hz"])["visibility"]), "client")


func test_wind_up_and_tell_reach_keys_meet_family_bounds() -> void:
	var checked: int = 0
	for key: Variant in tuning.entries.keys():
		var name: String = str(key)
		if name.ends_with("windup_s") and not name.ends_with("windup_min_s"):
			assert_gte(tuning.f(StringName(name)), 0.4, name)
			checked += 1
		if name.ends_with("tell_reach_tiles"):
			assert_gt(tuning.f(StringName(name)), 6.0, name)
			checked += 1
	assert_gt(checked, 3, "found the creature wind-up and tell-reach keys")


func test_generated_constants_are_fresh() -> void:
	var expected: String = GenKeys.render(tuning)
	assert_eq(FileAccess.get_file_as_string("res://shared/tuning/tuning_keys.gd"), expected,
		"run tools/build/gen_tuning_keys.gd")


func test_client_table_is_fresh() -> void:
	var expected: String = JSON.stringify(tuning.client_table(), "\t", false) + "\n"
	assert_eq(FileAccess.get_file_as_string(TuningSet.CLIENT_TABLE), expected,
		"run tools/build/gen_tuning_client.gd")


func test_coverage_manifest_names_only_real_keys() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/tuning/_coverage.json"))
	var rows: Dictionary = Variants.dict(Variants.dict(parsed).get("rows", {}))
	assert_gt(rows.size(), 300)
	for row: Variant in rows.keys():
		for key: Variant in Variants.array(rows[row]):
			assert_true(tuning.has_key(StringName(str(key))), "%s: %s exists" % [row, key])
