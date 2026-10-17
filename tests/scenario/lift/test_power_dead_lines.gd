extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-05 under Dead Lines (Gameplay §13.6): there is no switchboard and there are no phones, so
## power wakes neither; it still works base camp's relighter and battery rack and releases the
## winder's brake (Start counts once the list is done). A generated run reads the variant from its
## header.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const P = preload("res://tests/unit/lift/power_world.gd")
const Specs = preload("res://tests/unit/gen/template_specs.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_only_the_relighter_the_rack_and_the_brake_answer() -> void:
	var s: Scenario = make({"seed": 5541, "fixture": C.scenario_fixture()})
	C.load_camp(s)
	s.run.repair.set_list(RepairList.for_run(s.run.header.run_seed, RepairList.Kind.SHORT, false))
	var o: Vector2i = P.room_at(s, Vector2i(4, 0))
	P.substation(s, false, 0.6, o)
	var power: PowerJob = s.run.power
	power.dead_lines = true
	power.links_cleared = true
	power.fuses_fitted = power.fuses_required()
	var wilf: MinerHandle = P.beside(s, "wilf", o + P.TRIP, Vector2i(-1, 0))
	var ellis: MinerHandle = P.beside(s, "ellis", o + P.SWITCH, Vector2i(1, 0))
	s.step(4)
	wilf.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 120)
	assert_true(P.throw_after_cue(s, ellis, 0.4, 20))
	assert_true(power.is_on(), "power still comes on")
	assert_false(power.board_wakes(), "no board to wake")
	assert_false(power.lines_live(), "no line to make live")
	assert_true(s.run.base_camp.powered, "the relighter and the rack work")
	var lamp: GauzeLamp = s.run.lamps.create(s.run, 0.5, 2, false, 1, Vector2(9.5, 10.5))
	assert_true(s.run.base_camp.relighter.begin(s.run, s.run.base_camp.powered, lamp))
	assert_true(s.run.base_camp.rack.put(s.run.base_camp.powered, 0, 0.0))
	s.run.repair.mark_done(s.run, &"fuel")
	assert_true(s.run.repair.can_start(), "the brake releases: Start can count")


func test_a_generated_run_reads_dead_lines_from_its_header() -> void:
	var plain: Scenario = make({"seed": 5542, "generated": {"pack": Specs.road_pack(), "plan": true}})
	plain.step(2)
	assert_false(plain.run.power.dead_lines)
	var dead: Scenario = make({"seed": 5542, "generated": {"pack": Specs.road_pack(), "plan": true,
		"plan_overrides": {"hard_variant": "dead_lines"}}})
	dead.step(2)
	assert_eq(str(dead.generation.layouts.plan_dict()["hard_variant"]), "dead_lines")
	assert_true(dead.run.power.dead_lines, "the header's hard variant")
