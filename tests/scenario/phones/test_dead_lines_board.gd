extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-13 under Dead Lines (Gameplay §13.6): no board. Base camp's alcove holds an empty cabinet: no
## switchboard is made or seen, the seat is never offered, and a miner holding interact there never
## sits; nothing is sent as a board. Power still comes on through LFT-05's job and works the
## relighter, the rack and the brake.

const W = preload("res://tests/unit/phones/board_world.gd")
const PW = preload("res://tests/unit/lift/power_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_no_board_and_power_works_the_rest() -> void:
	var s: Scenario = make(W.cfg(5801))
	s.run.power.dead_lines = true
	W.camp(s)
	s.run.repair.set_list(RepairList.for_run(s.run.header.run_seed, RepairList.Kind.SHORT, false))
	var o: Vector2i = PW.room_at(s, Vector2i(4, 0))
	PW.substation(s, false, 0.6, o)
	var power: PowerJob = s.run.power
	power.links_cleared = true
	power.fuses_fitted = power.fuses_required()
	var wilf: MinerHandle = PW.beside(s, "wilf", o + PW.TRIP, Vector2i(-1, 0))
	var ellis: MinerHandle = PW.beside(s, "ellis", o + PW.SWITCH, Vector2i(1, 0))
	s.step(4)
	wilf.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 120)
	assert_true(PW.throw_after_cue(s, ellis, 0.4, 20))
	assert_true(power.is_on(), "power comes on")
	# No board: nothing made, nothing seen, no seat.
	assert_false(Switchboard.exists(s.run), "no board under Dead Lines")
	assert_false(Switchboard.awake(s.run))
	assert_eq(s.run.switchboard.fixture, 0, "no cabinet made")
	var seats: Array[Dictionary] = Basecamp.fixture(s.run.base_camp.seed_value, "switchboard_seat", s.run.base_camp.side)
	var seat: Vector2i = seats[0]["position"]
	for id: int in s.run.registry.ids():
		var e: SimEntity = s.run.registry.get_entity(id)
		if e.kind == WorldIds.EntityKind.FIXTURE:
			assert_gt(e.position.distance_to(Vector2(seat) + Vector2(0.5, 0.5)), 2.0, "no cabinet before the seat")
	var ann: MinerHandle = s.add_miner("ann", seat)
	ann.brain = null
	s.step(2)
	var offered: Dictionary = s.run.inventory.targets.pick(s.run, ann.entity_id, ann.slot, s.run.inventory.world)
	assert_ne(StringName(str(offered.get("kind", ""))), &"switchboard_seat", "the seat is never offered")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 60)
	s.step(70)
	assert_eq(s.run.closeups.operator(), 0, "nobody sits")
	assert_eq(ann.connection.board_messages, 0, "and no board is sent")
	# Power works the relighter, the rack and the brake.
	assert_true(s.run.base_camp.powered, "base camp powered")
	var lamp: GauzeLamp = s.run.lamps.create(s.run, 0.5, 2, false, 1, Vector2(9.5, 10.5))
	assert_true(s.run.base_camp.relighter.begin(s.run, s.run.base_camp.powered, lamp), "the relighter")
	assert_true(s.run.base_camp.rack.put(s.run.base_camp.powered, 0, 0.0), "the rack")
	s.run.repair.mark_done(s.run, &"fuel")
	assert_true(s.run.repair.can_start(), "the brake releases")
