extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-13 (grey box): a body lifted 20 tiles out along the west road is carried in through the open
## gate in 13.3 s (20 tiles at 1.5 tiles/s) plus the 2 s lift, and set down beside a medbay table:
## it lies on the table. With both tables taken it lies on the floor.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## A walkable tile beside `table` (within touch range of its centre), nearest the gate first.
func _beside(s: Scenario, table: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if s.run.mine.native.is_walkable(table + d):
			return table + d
	return table


func _lift(s: Scenario, ann: MinerHandle, bob: MinerHandle) -> void:
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(41)
	assert_true(s.run.carry.is_carrying(ann.entity_id), "lifted in 2 s")
	s.step(2)


func test_carry_home_onto_a_table() -> void:
	var s: Scenario = make({"seed": 91, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	var start: Vector2i = west.middle() + west.outward * 20
	for i: int in 21:
		assert_true(s.run.mine.native.is_walkable(west.middle() + west.outward * i), "the road runs straight %d tiles out" % i)
	var ann: MinerHandle = s.add_miner("ann", start)
	var bob: MinerHandle = s.add_miner("bob", start)
	s.step(1)
	L.lit_in_hand(s, ann)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	_lift(s, ann, bob)
	# Twenty tiles straight in along the road.
	var from: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var home: Vector2 = Vector2(west.middle()) + Vector2(0.5, 0.5)
	var moving_from: Array[int] = [-1]
	var arrived_at: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		var p: Vector2 = sc.run.registry.get_entity(ann.entity_id).position
		if moving_from[0] < 0 and p.distance_to(from) > 1e-6:
			moving_from[0] = sc.run.tick - 1
		if arrived_at[0] < 0 and p.distance_to(from) >= from.distance_to(home) - 1e-6:
			arrived_at[0] = sc.run.tick - 1
	var inward: float = rad_to_deg(Vector2(-west.outward).angle())
	ann.at(s.run.tick).move(inward, InputRecord.Gait.WALK, 280)
	s.step(282)
	var ticks: int = arrived_at[0] - moving_from[0] + 1
	var expected: float = from.distance_to(home) / Tuning.f(&"movement.carry_fireman_speed") * Tuning.f(&"net.tick_hz")
	assert_almost_eq(float(ticks), expected, 1.0, "20 tiles in 13.3 s, to a tick")
	gut.p("carry: %d ticks for %.2f tiles (expected %.1f)" % [ticks, from.distance_to(home), expected])
	assert_eq(s.run.falls.body_of(bob.entity_id).carried_by, ann.entity_id, "still on the shoulder")
	# On to a table, and set it down.
	var table: Vector2i = camp.medbay_tables()[0]
	ann.at(s.run.tick).walk_to(_beside(s, table))
	s.step(400)
	assert_lte(s.run.registry.get_entity(ann.entity_id).position.distance_to(Vector2(table) + Vector2(0.5, 0.5)),
		Tuning.f(&"vision.touch_range_tiles"), "beside the table")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 3)
	s.step(4)
	var b: BodyState = s.run.falls.body_of(bob.entity_id)
	assert_true(b.on_table, "the body lies on the table")
	assert_false(b.on_floor)
	assert_eq(int(Variants.number(camp.medbay.bodies[table])), bob.entity_id)
	assert_eq(s.run.registry.get_entity(bob.entity_id).tile(), table)
	assert_false(s.run.carry.is_carrying(ann.entity_id))


func test_both_tables_taken_it_lies_on_the_floor() -> void:
	var s: Scenario = make({"seed": 92, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var table: Vector2i = camp.medbay_tables()[0]
	var spot: Vector2i = _beside(s, table)
	var ann: MinerHandle = s.add_miner("ann", spot)
	var bob: MinerHandle = s.add_miner("bob", spot)
	s.step(1)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	_lift(s, ann, bob)
	for t: Vector2i in camp.medbay_tables():
		assert_true(camp.medbay.lay(t, 900 + t.x))
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 3)
	s.step(4)
	var b: BodyState = s.run.falls.body_of(bob.entity_id)
	assert_false(b.on_table, "both taken")
	assert_true(b.on_floor, "on the floor")
	assert_eq(s.run.registry.get_entity(bob.entity_id).tile(), spot, "on the carrier's tile")


func test_lifting_off_a_table_frees_it() -> void:
	var s: Scenario = make({"seed": 93, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var table: Vector2i = camp.medbay_tables()[0]
	var spot: Vector2i = _beside(s, table)
	var ann: MinerHandle = s.add_miner("ann", spot)
	var bob: MinerHandle = s.add_miner("bob", spot)
	s.step(1)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	_lift(s, ann, bob)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 3)
	s.step(4)
	assert_true(s.run.falls.body_of(bob.entity_id).on_table)
	_lift(s, ann, bob)
	assert_eq(int(Variants.number(camp.medbay.bodies[table])), 0, "lifted off: the table is free")
