extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-01: each row of the Draught's table (Gameplay §10.1) adds or drains exactly as tabled, every
## row on its own and the rows summing, and values stay within 0-100.

const D = preload("res://tests/scenario/director/draught_world.gd")
const W = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _run(seed_value: int, names: Array[String], spots: Array[String]) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": D.hall(), "director": true})
	var ids: Array[int] = D.crew(s, names, spots)
	D.stand_in(s)
	s.step(2)
	return [s, ids]


## The gains, each from 0: [name, gain, act(s, ids)]. Ann (ids[0]) gains; Ben, 30 tiles off, is there
## to fall, or to be out of a blast's reach.
func test_each_gain_as_tabled() -> void:
	var rows: Array = [["grabbed", 25.0, _grab], ["caught in a trap", 15.0, _catch],
		["hearing a fall (the knocks)", 15.0, _ben_falls], ["caught in a blast radius", 20.0, _blast]]
	var seed_value: int = 300
	for row: Array in rows:
		seed_value += 1
		var w: Array = _run(seed_value, ["ann", "ben"] as Array[String], ["a", "e"] as Array[String])
		var s: Scenario = w[0]
		var ids: Array[int] = w[1]
		assert_eq(D.value(s, ids[0]), 0.0, "%s: from 0" % row[0])
		var act: Callable = row[2]
		act.call(s, ids)
		s.step(roundi(Tuning.f(&"voice.knock_delay_s") * Tuning.f(&"net.tick_hz")) + 20)
		assert_eq(D.value(s, ids[0]), float(Variants.number(row[1])), "%s: +%s" % [row[0], row[1]])
		if act == _blast:
			assert_eq(D.value(s, ids[1]), 0.0, "a blast 30 tiles off: nothing")


func _grab(s: Scenario, ids: Array[int]) -> void:
	assert_gt(s.run.holds.grab(s.run, ids[0], GrabHold.Kind.STYTHE_DRAG, 0, 400), 0)


func _catch(s: Scenario, ids: Array[int]) -> void:
	assert_true(s.run.holds.catch(s.run, ids[0], CaughtHold.Kind.MAN_TRAP, 7))


func _ben_falls(s: Scenario, ids: Array[int]) -> void:
	assert_true(s.run.falls.fall_unconscious(s.run, ids[1], FallCause.Cause.ROOF_FALL))


func _blast(s: Scenario, ids: Array[int]) -> void:
	s.run.draught.on_blast(WorldCoords.tile_at(s.run.registry.get_entity(ids[0]).position) + Vector2i(4, 0), 1)


## Seeing a real creature within 6 tiles: +10. A stand-in Stythe 4 tiles ahead of Ann, then a lamp
## over it (a creature never spawns on a seen tile).
func test_seeing_a_creature() -> void:
	var s: Scenario = make({"seed": 310, "fixture": D.hall(), "director": true})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("c"), {"facing_deg": 0.0})
	D.stand_in(s)
	s.step(2)
	var at: Vector2i = s.fixture.spot("c") + Vector2i(4, 0)
	assert_gt(s.place_stand_in(WorldIds.EntityKind.STYTHE, at), 0)
	s.step(1)
	assert_eq(s.state.intensity(ann), 0.0, "unseen in the dark")
	W.lamp(s, Vector2(at) + Vector2(0.5, 0.5), 3.0)
	s.step(3)
	assert_eq(s.state.intensity(ann), 10.0, "+10 for a creature in sight within 6 tiles")


## The drains from 50, a second each: [name, setup(s, ann), after 1 s].
func test_each_drain_as_tabled_and_they_sum() -> void:
	var rows: Array = [["lit, no creature in sight", 45.0, _lit], ["in a relax", 45.0, _relax],
		["inside a shut base camp", 40.0, _sealed], ["all three at once", 30.0, _all_three]]
	var seed_value: int = 320
	for row: Array in rows:
		seed_value += 1
		var w: Array = _run(seed_value, ["ann"] as Array[String], ["a"] as Array[String])
		var s: Scenario = w[0]
		var ids: Array[int] = w[1]
		D.set_value(s, ids[0], 50.0)
		var setup: Callable = row[2]
		setup.call(s, ids[0])
		s.step(roundi(Tuning.f(&"net.tick_hz")))
		assert_almost_eq(D.value(s, ids[0]), float(Variants.number(row[1])), 1e-6, "%s: %s after 1 s" % [row[0], row[1]])


func _lit(s: Scenario, e: int) -> void:
	D.stand_in(s, {e: 0.35})


## Forces a long relax without a peak (the cycle is test_draught_cycle's).
func _relax(s: Scenario, _e: int) -> void:
	s.run.draught.cycle.phase = DraughtCycle.Phase.RELAX
	s.run.draught.cycle.left = 100000


func _sealed(s: Scenario, e: int) -> void:
	s.run.crew.is_sealed_inside = func(x: int) -> bool: return x == e


func _all_three(s: Scenario, e: int) -> void:
	_lit(s, e)
	_relax(s, e)
	_sealed(s, e)


func test_values_stay_within_0_and_100() -> void:
	var w: Array = _run(330, ["ann", "ben"] as Array[String], ["a", "e"] as Array[String])
	var s: Scenario = w[0]
	var ids: Array[int] = w[1]
	D.set_value(s, ids[0], 90.0)
	s.run.holds.grab(s.run, ids[0], GrabHold.Kind.STYTHE_DRAG, 0, 400)
	s.step(1)
	assert_eq(D.value(s, ids[0]), 100.0, "90 + 25 holds at 100")
	D.set_value(s, ids[1], 1.0)
	_sealed(s, ids[1])
	s.step(10)
	assert_eq(D.value(s, ids[1]), 0.0, "1 - 10 a second holds at 0")
