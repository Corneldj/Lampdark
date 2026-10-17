extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-05: an absent miner keeps waiting through every later knock-off. The Full run is played over
## evenings: Cat misses the second evening and the third; her miner waits off the map through the
## second knock-off's save, and returns on the third evening's resume with her marks and her Hurt as
## they were when she left, however long the others played. Waiting miners are no one's to take: the
## unconscious stay bodies, and nobody is parked twice.

const K = preload("res://tests/unit/modes/knock_off_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_waiting_miner_waits_through_the_next_knock_off() -> void:
	K.S.clear(5051)
	var s: Scenario = make(K.cfg(5051))
	K.camp(s)
	var ann: MinerHandle = K.miner(s, "ann", 0)
	var cat: MinerHandle = K.miner(s, "cat", 2)
	s.run.miner_state.miner(cat.entity_id).overlays.marks[MinerOverlays.SOOT_LUNG] = true
	s.run.miner_state.miner(cat.entity_id).overlays.hurt_until = s.run.tick + 400
	s.step(3)
	var uuid: String = s.run.header.run_uuid
	assert_eq(K.knock_off(s), "")
	var first: String = K.client_copy(s, ann, uuid)
	K.S.kill(s)
	# The second evening: Ann alone. Cat waits.
	var b: Scenario = K.resume(make, 5051, first)[0]
	b.rejoin("ann")
	assert_eq(b.run.absent.park_absent(b.run), 1)
	assert_eq(b.run.absent.park_absent(b.run), 0, "nobody parked twice")
	b.step(600)
	K.C.shut_all(b, true)  # the test world shuts its gates outside the gate system, so no save keeps them
	b.step(2)
	assert_true(b.run.knock_off.available, "Ann in base camp, the gates shut")
	assert_eq(K.knock_off(b), "", "the second knock-off, Cat still waiting")
	var second: String = K.knockoff_path(b)
	K.S.kill(b)
	# The third evening: Cat is back.
	var c: Scenario = K.resume(make, 5051, second)[0]
	assert_true(c.run.absent.is_waiting("cat"), "she waited through the second save")
	c.rejoin("ann")
	var back: MinerHandle = c.rejoin("cat")
	assert_false(c.run.absent.is_waiting("cat"))
	var e: int = back.entity_id
	assert_true(c.run.registry.has(e))
	assert_true(c.run.miner_state.miner(e).overlays.marks.has(MinerOverlays.SOOT_LUNG), "her marks")
	assert_eq(c.run.miner_state.miner(e).overlays.hurt_until - c.run.tick, 400 - 3, "her Hurt as it was when she left")
	assert_eq(c.net.seats.seat_of("cat").miner, e, "her seat holds her miner again")
