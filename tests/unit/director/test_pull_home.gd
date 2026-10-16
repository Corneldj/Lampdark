extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-03 (Gameplay §10.5, §3.2): inside base camp with every gate shut, −20 a minute, the operator
## included (−10 for solo and lone humans); with a gate open, base camp counts as ring 0, so a lone
## operator gains +3 a minute. LFT-01's sealing through DIR-05's provider; base camp on GEN-03's grey box.

const D = preload("res://tests/scenario/director/draught_world.gd")
const MAP: String = "m1_greybox"


func before_all() -> void:
	assert_true(Tuning.load_server())


func _minute(s: Scenario, e: int, from: float) -> float:
	assert_true(s.run.pull.set_value(e, from))
	var start: float = s.run.pull.value_of(e)
	s.step(roundi(60.0 * Tuning.f(&"net.tick_hz")))
	return s.run.pull.value_of(e) - start


func test_a_sealed_base_camp_drains_20_a_minute_10_for_solo() -> void:
	var s: Scenario = make({"seed": 2201, "fixture": D.hall(), "director": true})
	var ids: Array[int] = D.crew(s, ["ellis", "ada"] as Array[String], ["a", "e"] as Array[String])
	D.stand_in(s)
	s.run.crew.is_sealed_inside = func(e: int) -> bool: return e == ids[0]
	s.step(2)
	assert_almost_eq(_minute(s, ids[0], 50.0), -20.0, 0.01, "home, gates shut")
	var solo: Scenario = make({"seed": 2202, "fixture": D.hall(), "director": true})
	var only: Array[int] = D.crew(solo, ["ellis"] as Array[String], ["a"] as Array[String])
	D.stand_in(solo)
	solo.run.crew.lobby = CrewCensus.Lobby.SOLO
	solo.run.crew.is_sealed_inside = func(e: int) -> bool: return e == only[0]
	solo.step(2)
	assert_almost_eq(_minute(solo, only[0], 50.0), -10.0, 0.01, "solo at home")


func test_with_a_gate_open_a_lone_operator_gains_3() -> void:
	var s: Scenario = make({"seed": 2203, "fixture": MAP, "director": true})
	FixedMapLoader.populate(s.run, MAP, true, true)
	var inside: Array = Basecamp.inside_tiles(FixedMapLoader.run_seed(FixedMapLoader.manifest(MAP)),
		FixedMapLoader.blind_side(FixedMapLoader.manifest(MAP))).keys()
	inside.sort()
	var home: Vector2i = inside[0]
	var ellis: MinerHandle = s.add_miner("ellis", home)
	s.add_miner("ada", Vector2i(31, 14)) # out on the east arm, far off
	D.stand_in(s)
	s.run.pull.ring_of = func(_m: int) -> int: return 3 # base camp overrules the ring
	s.step(10)
	assert_true(s.run.base_camp.is_inside(ellis.entity_id))
	if s.run.base_camp.is_sealed():
		gut.p("(the grey box starts sealed: its gate opens through the provider instead)")
	s.run.crew.is_sealed_inside = func(_e: int) -> bool: return false # a gate open
	assert_almost_eq(_minute(s, ellis.entity_id, 50.0), 3.0, 0.01, "inside base camp, a gate open: ring 0, alone")
