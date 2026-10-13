extends GutTest
## MNR-01's speed modifiers: owners multiply, the wound slot is single, step levels override.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_factors() -> void:
	var m: SpeedModifiers = SpeedModifiers.new()
	assert_eq(m.factor(), 1.0)
	m.set_modifier(&"mud", 0.5, 12.0)
	m.set_modifier(&"carry", 0.8)
	assert_almost_eq(m.factor(), 0.4, 1e-12)
	m.set_wound(true)
	assert_almost_eq(m.factor(), 0.32, 1e-12)
	assert_eq(m.step_np_override(), 12.0)
	m.clear(&"mud")
	assert_eq(m.step_np_override(), 0.0)
	m.set_wound(false)
	assert_almost_eq(m.factor(), 0.8, 1e-12)
