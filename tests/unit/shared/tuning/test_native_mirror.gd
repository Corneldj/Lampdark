extends GutTest
## C++ reads the same effective tuning values as GDScript, after load and after reload (FND-05).


func _native(key: String) -> Variant:
	return ClassDB.class_call_static(&"LbTuning", &"get_value", key)


func _assert_mirror_matches() -> void:
	var current: TuningSet = Tuning.current
	var count: int = ClassDB.class_call_static(&"LbTuning", &"count")
	assert_eq(count, current.entries.size(), "the mirror holds every key")
	var mismatches: Array[String] = []
	for key: Variant in current.entries.keys():
		var gd_value: Variant = Variants.dict(current.entries[key])["value"]
		if TuningSet.canonical_value(_native(str(key))) != TuningSet.canonical_value(gd_value):
			mismatches.append(str(key))
	assert_eq(mismatches, [] as Array[String], "every key matches between GDScript and C++")


func before_all() -> void:
	assert_true(ClassDB.class_exists(&"LbTuning"), "lampblack_core provides LbTuning")
	assert_true(Tuning.load_server(), "the real tuning loads")


func after_all() -> void:
	Tuning.clear_dev_overrides()


func test_mirror_matches_after_load() -> void:
	_assert_mirror_matches()
	var native_ppm: int = ClassDB.class_call_static(&"LbTuning", &"ppm", "mine.edge_open_probability")
	assert_eq(native_ppm, 600000)
	assert_eq(native_ppm, Tuning.ppm(&"mine.edge_open_probability"))


func test_mirror_matches_after_reload() -> void:
	var before: float = Tuning.f(&"moth.windup_s")
	assert_eq(Tuning.set_dev_override("moth.windup_s", before + 0.25), [] as Array[String])
	var native_value: float = _native("moth.windup_s")
	assert_almost_eq(native_value, before + 0.25, 0.000001, "C++ sees the reloaded value")
	_assert_mirror_matches()
	Tuning.clear_dev_overrides()
	var restored: float = _native("moth.windup_s")
	assert_almost_eq(restored, before, 0.000001)


func test_unknown_key_reads_null() -> void:
	var value: Variant = _native("moth.no_such_key")
	assert_true(value == null, "an unknown key mirrors as null")
