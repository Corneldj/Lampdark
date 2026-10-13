extends GutTest
## Each invalid fixture in tests/fixtures/tuning/ fails validation with its expected error (FND-05).

const Fixture = preload("res://tests/unit/shared/tuning/tuning_fixture.gd")

const FAILING: Array[String] = [
	"missing_value", "missing_source", "missing_unit", "missing_starting", "missing_visibility",
	"missing_kind", "unknown_unit", "prefix_mismatch", "duplicate_key", "wrong_type",
	"non_integral_int", "bool_not_bool", "by_ring_length", "by_crew_length",
	"range_min_above_max", "below_min", "windup_too_short", "tell_reach_too_short", "bad_source",
]


func test_valid_fixture_loads() -> void:
	var tuning: TuningSet = TuningSet.new()
	var errors: Array[String] = tuning.load_directory(Fixture.write("valid_set"), false)
	assert_eq(errors, [] as Array[String])
	assert_eq(tuning.entries.size(), 16)


func test_every_failure_fixture_fails_with_its_error() -> void:
	for name: String in FAILING:
		var expect: String = str(Fixture.read(name).get("expect", ""))
		assert_ne(expect, "", "%s names its expected error" % name)
		var tuning: TuningSet = TuningSet.new()
		var errors: Array[String] = tuning.load_directory(Fixture.write(name), false)
		assert_false(errors.is_empty(), "%s fails validation" % name)
		var joined: String = "\n".join(PackedStringArray(errors))
		assert_string_contains(joined, expect, false)


func test_every_fixture_file_is_covered() -> void:
	for file: String in DirAccess.get_files_at(Fixture.FIXTURES):
		var name: String = file.get_basename()
		assert_true(name == "valid_set" or name in FAILING, "fixture %s is tested" % name)


func test_missing_domain_file_when_all_required() -> void:
	var tuning: TuningSet = TuningSet.new()
	var errors: Array[String] = tuning.load_directory(Fixture.write("valid_set"), true)
	assert_string_contains("\n".join(PackedStringArray(errors)), "missing domain file camera.json")


func test_family_bounds_apply_without_entry_bounds() -> void:
	var entry: Dictionary = {"value": 0.39, "type": "float"}
	assert_false(TuningSchema.validate_value("stythe.windup_s", "float", 0.39,
		TuningSchema.with_family_bounds("stythe.windup_s", entry)).is_empty(), "0.39 s wind-up rejected")
	assert_true(TuningSchema.validate_value("stythe.windup_s", "float", 0.4,
		TuningSchema.with_family_bounds("stythe.windup_s", entry)).is_empty(), "0.4 s wind-up accepted")
	assert_false(TuningSchema.validate_value("moth.tell_reach_tiles", "float", 6.0,
		TuningSchema.with_family_bounds("moth.tell_reach_tiles", entry)).is_empty(), "6-tile reach rejected")
	assert_true(TuningSchema.validate_value("moth.tell_reach_tiles", "float", 6.5,
		TuningSchema.with_family_bounds("moth.tell_reach_tiles", entry)).is_empty(), "6.5-tile reach accepted")
