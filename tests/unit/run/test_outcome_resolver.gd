extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-11 (Gameplay §3.8, §11.9): every row of the outcome table, set once at the surface. Aboard,
## the conscious and the unconscious escape, and a dead rider is Dead, brought home (escaped, dead).
## Everyone else is Left Below: a conscious miner in base camp, a Caught miner, a body lying out in
## the mine. Up counts those who came up; each outcome is set exactly once.

const K = preload("res://tests/unit/lift/cage_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_every_row_at_the_surface() -> void:
	var s: Scenario = make({"seed": 11101, "fixture": K.E.T.C.scenario_fixture(), "slots": 6})
	K.ready(s)
	var cage: Cage = s.run.cage
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var dot: MinerHandle = K.aboard(s, "dot", 1)
	var bob: MinerHandle = K.at_home(s, "bob")
	var cid: MinerHandle = K.at_home(s, "cid")
	var eve: MinerHandle = K.at_home(s, "eve")
	var fay: MinerHandle = K.at_home(s, "fay")
	# Bob lies on the deck unconscious, Cid lies there dead; Eve is Caught below, Fay out cold below.
	K.move_to(s, bob, K.far_deck_tile(s))
	K.move_to(s, cid, s.run.cage.deck.position)
	s.run.miner_state.fall_unconscious(bob.entity_id, "test")
	s.run.miner_state.kill(cid.entity_id, "revolver")
	s.run.miner_state.enter_caught(eve.entity_id, &"man_trap", 1)
	s.run.miner_state.fall_unconscious(fay.entity_id, "test")
	s.step(3)
	K.pull(s, ann)
	K.pull(s, dot)
	assert_eq(cage.state, Cage.State.BELL, "Ann and Dot of the three conscious")
	K.move_to(s, dot, s.run.base_camp.medbay_tables()[0])
	var ended: Array[Dictionary] = []
	s.run.outcomes.run_ended.connect(func(rec: Dictionary) -> void: ended.append(rec))
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.state == Cage.State.SURFACED,
		K.bell_ticks() + ShaftRide.ride_ticks() + 20))
	s.step(1)
	assert_eq(ended.size(), 1, "the run ends at the surface")
	var by: Dictionary = {}
	for raw: Variant in Variants.array(ended[0]["miners"]):
		var m: Dictionary = raw
		by[int(Variants.number(m["miner_id"]))] = m
	for h: MinerHandle in [ann, bob]:
		assert_eq(str(by[h.entity_id]["outcome"]), "escaped", "%s came up" % h.name)
		assert_false(Variants.flag(by[h.entity_id]["dead"]))
	assert_eq(str(by[cid.entity_id]["outcome"]), "escaped")
	assert_true(Variants.flag(by[cid.entity_id]["dead"]), "Cid: Dead, brought home")
	for h: MinerHandle in [dot, eve, fay]:
		assert_eq(str(by[h.entity_id]["outcome"]), "left_below", "%s is Left Below" % h.name)
	assert_eq(int(Variants.number(ended[0]["up_count"])), 3, "Up 3 of 6")
	assert_eq(int(Variants.number(ended[0]["crew_size"])), 6)
	assert_false(Variants.flag(ended[0]["wipe"]))
	# Set once, on the miners, the life states kept.
	assert_eq(s.run.miner_state.miner(cid.entity_id).outcome, MinerTransitions.Outcome.ESCAPED)
	assert_eq(s.run.miner_state.life(cid.entity_id), MinerTransitions.Life.DEAD)
	assert_eq(s.run.miner_state.miner(dot.entity_id).outcome, MinerTransitions.Outcome.LEFT_BELOW)
	s.run.cage.cage_surfaced.emit({})
	s.step(2)
	assert_eq(s.run.miner_state.miner(dot.entity_id).outcome, MinerTransitions.Outcome.LEFT_BELOW, "never set twice")
	assert_eq(ended.size(), 1, "and the run ends once")
