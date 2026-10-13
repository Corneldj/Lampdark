extends GutTest
## Typed access, conversions, ppm, ticks and access errors (FND-05).

const Fixture = preload("res://tests/unit/shared/tuning/tuning_fixture.gd")

var tuning: TuningSet


func before_each() -> void:
	tuning = Fixture.valid_set()


func test_typed_values() -> void:
	assert_almost_eq(tuning.f(&"moth.windup_s"), 1.0, 0.0001)
	assert_eq(tuning.i(&"moth.lamps"), 3)
	assert_typeof(tuning.i(&"moth.lamps"), TYPE_INT, "int keys convert from JSON floats")
	assert_true(tuning.b(&"moth.on"))
	assert_eq(tuning.s(&"moth.name_kind"), "brightest")
	assert_eq(tuning.s(&"moth.label"), "heap")
	assert_eq(tuning.list_i(&"moth.ints"), [1, 2, 3] as Array[int])
	assert_eq(tuning.list_f(&"moth.floats"), [0.5, 1.5] as Array[float])
	assert_eq(tuning.list_s(&"moth.words"), ["a", "b"] as Array[String])
	assert_eq(tuning.range_f(&"moth.window_s"), Vector2(2, 4))
	assert_eq(tuning.table(&"moth.weights"), {"brightest": 1.0, "widow": 2.0})


func test_int_reads_as_float() -> void:
	assert_eq(tuning.f(&"moth.lamps"), 3.0)


func test_by_ring_and_by_crew() -> void:
	assert_eq(tuning.by_ring(&"moth.per_ring_s", 0), 60.0)
	assert_eq(tuning.by_ring(&"moth.per_ring_s", 2), 45.0)
	assert_eq(tuning.by_ring(&"moth.per_ring_s", 4), 30.0)
	assert_eq(tuning.by_crew(&"moth.per_crew", 1), 2.0)
	assert_eq(tuning.by_crew(&"moth.per_crew", 5), 3.0)


func test_ppm_and_ticks() -> void:
	assert_eq(tuning.ppm(&"moth.wake_ppm_share"), 600000)
	assert_eq(tuning.ticks(&"moth.windup_s"), 20, "1.0 s at 20 Hz")
	assert_eq(tuning.ticks(&"moth.floats") if false else tuning.ticks(&"moth.client_radius_tiles"), 80)


func test_unknown_key_is_an_error() -> void:
	assert_eq(tuning.f(&"moth.no_such_key"), 0.0)
	assert_push_error("unknown key 'moth.no_such_key'")


func test_wrong_type_is_an_error() -> void:
	assert_eq(tuning.i(&"moth.windup_s"), 0)
	assert_push_error("is float, not int")
	assert_eq(tuning.b(&"moth.lamps"), false)
	assert_push_error("is int, not bool")


func test_ring_and_crew_out_of_range_are_errors() -> void:
	tuning.by_ring(&"moth.per_ring_s", 5)
	assert_push_error("ring 5 out of 0-4")
	tuning.by_crew(&"moth.per_crew", 0)
	assert_push_error("crew count 0 out of 1-5")


func test_canonical_values_are_platform_independent() -> void:
	assert_eq(TuningSet.canonical_value(3.0), "3")
	assert_eq(TuningSet.canonical_value(0.6), "0.6")
	assert_eq(TuningSet.canonical_value({"b": 2.0, "a": 1.5}), "{a:1.5,b:2}")
	assert_eq(TuningSet.canonical_value([1.0, 0.25]), "[1,0.25]")
