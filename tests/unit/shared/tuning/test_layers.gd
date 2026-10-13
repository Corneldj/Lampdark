extends GutTest
## Overlays: values only, applied in full or not at all, and they move the hash (FND-05).

const Fixture = preload("res://tests/unit/shared/tuning/tuning_fixture.gd")

var tuning: TuningSet


func before_each() -> void:
	tuning = Fixture.valid_set()


func test_valid_overlay_changes_value_layer_and_hash() -> void:
	var before: String = tuning.content_hash()
	var errors: Array[String] = tuning.apply_overlay({"moth.windup_s": {"value": 1.2}}, "profile")
	assert_eq(errors, [] as Array[String])
	assert_almost_eq(tuning.f(&"moth.windup_s"), 1.2, 0.0001)
	assert_eq(str(tuning.layer_of["moth.windup_s"]), "profile")
	assert_eq(str(tuning.layer_of["moth.lamps"]), "base")
	assert_ne(tuning.content_hash(), before, "the content hash changes")


func test_overlay_may_not_add_a_key() -> void:
	var errors: Array[String] = tuning.apply_overlay({"moth.new_thing_s": {"value": 1.0}}, "profile")
	assert_string_contains("\n".join(PackedStringArray(errors)), "may not add a key")


func test_overlay_may_not_change_type_unit_or_visibility() -> void:
	for change: Dictionary in [
		{"value": 2, "type": "int"}, {"value": 1.0, "unit": "tiles"}, {"value": 1.0, "visibility": "client"},
	]:
		var copy: TuningSet = tuning.duplicate_set()
		var errors: Array[String] = copy.apply_overlay({"moth.windup_s": change}, "bundle")
		assert_false(errors.is_empty(), "rejected: %s" % [change])
		assert_almost_eq(copy.f(&"moth.windup_s"), 1.0, 0.0001, "value unchanged after a rejected overlay")


func test_overlay_values_are_validated_with_family_bounds() -> void:
	var errors: Array[String] = tuning.apply_overlay({"moth.windup_s": {"value": 0.39}}, "dev")
	assert_string_contains("\n".join(PackedStringArray(errors)), "below min 0.4")


func test_overlay_is_all_or_nothing() -> void:
	var errors: Array[String] = tuning.apply_overlay({
		"moth.lamps": {"value": 5}, "moth.ghost": {"value": 1}}, "dev")
	assert_false(errors.is_empty())
	assert_eq(tuning.i(&"moth.lamps"), 3, "the valid half was not applied")


func test_layers_stack_in_order() -> void:
	assert_eq(tuning.apply_overlay({"moth.lamps": {"value": 4}}, "profile"), [] as Array[String])
	assert_eq(tuning.apply_overlay({"moth.lamps": {"value": 5}}, "bundle"), [] as Array[String])
	assert_eq(tuning.apply_overlay({"moth.lamps": {"value": 6}}, "dev"), [] as Array[String])
	assert_eq(tuning.i(&"moth.lamps"), 6)
	assert_eq(str(tuning.layer_of["moth.lamps"]), "dev")


func test_base_is_not_an_overlay_layer() -> void:
	assert_false(tuning.apply_overlay({"moth.lamps": {"value": 4}}, "base").is_empty())


func test_profile_directory_overlay() -> void:
	var dir: String = Fixture.ROOT.path_join("profile_a")
	Fixture.clear(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	Fixture.store(dir.path_join("moth.json"), {"domain": "moth", "keys": {"moth.lamps": {"value": 7}}})
	assert_eq(tuning.apply_profile_directory(dir), [] as Array[String])
	assert_eq(tuning.i(&"moth.lamps"), 7)
	assert_eq(str(tuning.layer_of["moth.lamps"]), "profile")
