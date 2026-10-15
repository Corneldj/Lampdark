extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-13: each owner built so far records its change in the right cell in the same tick: a body
## (RSC-01) where it falls, moved with it, gone when the miner revives; a gate flip (LFT-02) in base
## camp's cell; a lamp on the floor snuffed (MNR-06). Items, doors and blood: the evict-return and
## door-chalk-blood scenarios. Owners not yet built (falls, traps, lines, fitted parts, the hoard,
## the lair, the map table, Pocket Books) add theirs with their tickets.

const W = preload("res://tests/scenario/world/diff_world.gd")
const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _body(s: Scenario, entity: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), W.FAR]:
		var p: Dictionary = s.run.diff_log.payload_of(cell, DiffLog.Kind.BODY, "m%d" % entity)
		if not p.is_empty():
			out.append({"cell": cell, "payload": p})
	return out


func test_a_body_is_recorded_where_it_lies() -> void:
	var s: Scenario = make({"seed": 1331, "fixture": W.road()})
	var ann: MinerHandle = W.miner(s, "ann", Vector2i(50, 1))
	W.miner(s, "bob", Vector2i(3, 1))
	s.step(2)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.falls.bodies.has(ann.entity_id), 40))
	var rows: Array[Dictionary] = _body(s, ann.entity_id)
	assert_eq(rows.size(), 1, "recorded the tick it fell")
	var first: Vector2i = rows[0]["cell"]
	assert_eq(first, W.FAR, "in its cell")
	s.run.movement.place(s.run, ann.entity_id, Vector2(30.5, 1.5))
	s.step(1)
	rows = _body(s, ann.entity_id)
	assert_eq(rows.size(), 1, "one record, moved with it")
	var moved: Vector2i = rows[0]["cell"]
	assert_eq(moved, Vector2i(1, 0))
	assert_almost_eq(float(Variants.number(Variants.dict(rows[0]["payload"])["x"])), 30.5, 0.01)
	s.run.miner_state.revive(ann.entity_id, &"test")
	s.step(2)
	assert_true(_body(s, ann.entity_id).is_empty(), "risen: no body to keep")


func test_a_gate_flip_is_recorded_in_base_camp() -> void:
	var s: Scenario = make({"seed": 1332, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	var ann: MinerHandle = s.add_miner("ann", C.lever(s, "west", "inside"))
	s.step(2)
	assert_true(west.open)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 31)
	s.step(50)
	assert_false(west.open, "shut by the lever")
	var flip: Dictionary = camp.gate_system.diff_log[camp.gate_system.diff_log.size() - 1]
	var key: String = GateSystem.DIFF_PREFIX + "west"
	assert_false(Variants.flag(s.run.diff_log.payload_of(Vector2i.ZERO, DiffLog.Kind.BARRIER, key).get("open", true)), "recorded shut")
	assert_eq(s.run.diff_log.tick_of(Vector2i.ZERO, DiffLog.Kind.BARRIER, key), int(Variants.number(flip["tick"])), "the same tick")


func test_a_lamp_snuffed_on_the_floor_is_recorded() -> void:
	var s: Scenario = make({"seed": 1333, "fixture": W.road()})
	W.miner(s, "ann", Vector2i(3, 1))
	s.step(2)
	var l: GauzeLamp = s.run.lamps.create(s.run, 0.6, 1, true, LampRules.WICK_NORMAL, Vector2(50.5, 1.5))
	s.step(2)
	var key: String = "u%d" % l.uid
	assert_true(Variants.flag(Variants.dict(s.run.diff_log.payload_of(W.FAR, DiffLog.Kind.ITEM, key)["state"])["lit"]))
	assert_true(s.run.lamps.snuff(s.run, l, "test"))
	var p: Dictionary = s.run.diff_log.payload_of(W.FAR, DiffLog.Kind.ITEM, key)
	assert_false(Variants.flag(Variants.dict(p["state"])["lit"]), "snuffed, at once")
	assert_eq(s.run.diff_log.tick_of(W.FAR, DiffLog.Kind.ITEM, key), s.run.tick)
	assert_eq(int(Variants.number(p["lamp_phase"])), LampRules.Phase.OUT)
