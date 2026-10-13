extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-01 with CRT-04: a creature following someone in. A Moth hunting a lamp-bearer on the west road
## follows her through the open gate into base camp, where its 0.6 light shows her to it anyway.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_follows_in() -> void:
	var s: Scenario = make({"seed": 86, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	s.step(2)
	var m: Moth = A.awake(s, west.middle() + west.outward * 16, false)
	var ann: MinerHandle = A.lit_miner(s, "ann", west.middle() + west.outward * 3)
	ann.at(s.run.tick).walk_to(Basecamp.deck_rect(C.SEED, 0).get_center(), InputRecord.Gait.RUN)
	var inside_at: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		if inside_at[0] < 0 and camp.inside_tiles.has(m.tile(sc.run)):
			inside_at[0] = sc.run.tick
	s.step(400)
	assert_gte(inside_at[0], 0, "the Moth followed her in through the open gate")
	assert_true(camp.inside_tiles.has(s.run.registry.get_entity(ann.entity_id).tile()) or A.life(s, ann.entity_id) != MinerTransitions.Life.UPRIGHT)
	gut.p("in at tick %d; ann %s" % [inside_at[0], MinerTransitions.Life.find_key(A.life(s, ann.entity_id))])
