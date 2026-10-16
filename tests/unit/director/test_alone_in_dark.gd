extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-01: alone in the dark with no lamp (Gameplay §10.1) yields exactly +30 after 6 s, then nothing
## more until the miner stands in light of 0.30 or a relax begins. Company within 8 tiles by path
## stops it (a Hand never counts); so does a lit lamp in hand (open and burning: a shuttered gauze
## lamp is none).

const D = preload("res://tests/scenario/director/draught_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const DARK: float = 0.05
const LIT: float = 0.35


func before_all() -> void:
	assert_true(Tuning.load_server())


func _s(seed_value: int, names: Array[String], spots: Array[String]) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": D.hall(), "director": true})
	var ids: Array[int] = D.crew(s, names, spots)
	D.stand_in(s) # neutral until each test sets its own
	s.step(2)
	return [s, ids]


func _seconds(s: Scenario, seconds: float) -> void:
	s.step(roundi(seconds * Tuning.f(&"net.tick_hz")))


func test_30_after_6_s_then_nothing_until_light_or_a_relax() -> void:
	var w: Array = _s(501, ["ann"] as Array[String], ["a"] as Array[String])
	var s: Scenario = w[0]
	var ids: Array[int] = w[1]
	var ann: int = ids[0]
	var light: Dictionary = {ann: DARK}
	D.stand_in(s, light)
	_seconds(s, 3.0)
	assert_almost_eq(D.value(s, ann), 15.0, 1e-6, "+5 a second")
	_seconds(s, 3.0)
	assert_almost_eq(D.value(s, ann), 30.0, 1e-6, "exactly 30 after 6 s")
	_seconds(s, 10.0)
	assert_almost_eq(D.value(s, ann), 30.0, 1e-6, "and no more")
	# A tick in light of 0.30 renews it (and drains a twentieth of 5).
	light[ann] = LIT
	s.step(1)
	light[ann] = DARK
	_seconds(s, 6.0)
	assert_almost_eq(D.value(s, ann), 59.75, 1e-6, "another 30 once renewed in the light")
	_seconds(s, 4.0)
	assert_almost_eq(D.value(s, ann), 59.75, 1e-6, "and no more")
	# A relax beginning renews it too; the relax drains 5 a second meanwhile.
	s.run.draught.cycle.relax_begun.emit(600, 0)
	_seconds(s, 2.0)
	assert_almost_eq(D.value(s, ann), 69.75, 1e-6, "renewed by the relax: +10 in 2 s")


func test_company_within_8_by_path_stops_it_and_a_hand_never_counts() -> void:
	# Ann at a (x 1), Ben at b (x 5): 4 tiles by path. Cat at e (x 31), far off.
	var w: Array = _s(502, ["ann", "ben", "cat"] as Array[String], ["a", "b", "e"] as Array[String])
	var s: Scenario = w[0]
	var ids: Array[int] = w[1]
	D.stand_in(s, {ids[0]: DARK, ids[1]: DARK, ids[2]: DARK})
	_seconds(s, 2.0)
	assert_eq(D.value(s, ids[0]), 0.0, "Ben 4 tiles off: company")
	assert_almost_eq(D.value(s, ids[2]), 10.0, 1e-6, "Cat alone gains")
	# Ben is a Hand: no company.
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == ids[1]
	_seconds(s, 2.0)
	assert_almost_eq(D.value(s, ids[0]), 10.0, 1e-6, "a Hand is no company")
	assert_eq(D.value(s, ids[1]), -1.0, "and holds no intensity")


func test_company_beyond_8_tiles_is_none() -> void:
	# Ann at c (x 11), Ben at d (x 21): 10 tiles.
	var w: Array = _s(503, ["ann", "ben"] as Array[String], ["c", "d"] as Array[String])
	var s: Scenario = w[0]
	var ids: Array[int] = w[1]
	D.stand_in(s, {ids[0]: DARK, ids[1]: DARK})
	_seconds(s, 2.0)
	assert_almost_eq(D.value(s, ids[0]), 10.0, 1e-6, "10 tiles is alone")


func test_a_lit_lamp_in_hand_stops_it() -> void:
	var w: Array = _s(504, ["ann"] as Array[String], ["a"] as Array[String])
	var s: Scenario = w[0]
	var ids: Array[int] = w[1]
	var ann: int = ids[0]
	D.stand_in(s, {ann: DARK}, {ann: true})
	_seconds(s, 2.0)
	assert_eq(D.value(s, ann), 0.0, "a lit lamp in hand")


func test_a_shuttered_gauze_lamp_is_no_lamp() -> void:
	var s: Scenario = make({"seed": 505, "fixture": D.hall(), "director": true})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	D.stand_in(s, {ann.entity_id: DARK})
	s.run.draught.lit_lamp_in_hand = Callable() # the real lamps decide
	var lamp: GauzeLamp = L.lit_in_hand(s, ann)
	s.step(1)
	assert_eq(lamp.state(), GauzeLamp.State.OPEN, "open and burning in hand")
	_seconds(s, 1.0)
	assert_eq(s.state.intensity(ann), 0.0, "an open lamp in hand: not alone in the dark")
	assert_true(s.run.lamps.shutter(s.run, lamp, false))
	_seconds(s, 2.0)
	assert_eq(lamp.state(), GauzeLamp.State.SHUTTERED)
	assert_gt(s.state.intensity(ann), 0.0, "shuttered: no lamp")
