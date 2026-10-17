extends "res://tests/scenario/kit/scenario_test.gd"
## NET-11 under a bad connection: three miners on 250 ms links with 2% loss, and a 10 s outage
## every 5 minutes for each in turn. It ends with no stuck miner and no lost seat: everyone back in
## their own seat, driving their own miner, no Hand left holding a place. The nightly length is 30
## minutes (LB_SOAK_FULL=1); the round runs 6.

const R = preload("res://tests/unit/mnr/revolver_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_outages_leave_no_stuck_miner_and_no_lost_seat() -> void:
	var full: bool = not OS.get_environment("LB_SOAK_FULL").is_empty()
	var minutes: int = 30 if full else 6
	var hz: int = roundi(Tuning.f(&"net.tick_hz"))
	var s: Scenario = make({"seed": 1341, "fixture": R.hall(40)})
	R.lit(s, 40)
	var crew: Array[MinerHandle] = []
	var owned: Dictionary = {}
	for i: int in 3:
		var h: MinerHandle = R.miner(s, "m%d" % i, Vector2i(4 + i * 6, 2))
		crew.append(h)
	s.step(5)
	for h: MinerHandle in crew:
		h.link(250, 2.0)
		owned[h.name] = [h.slot, h.entity_id]
	var period: int = 5 * 60 * hz
	var outage: int = 10 * hz
	var outages: int = 0
	for t: int in minutes * 60 * hz:
		var phase: int = t % period
		var who: MinerHandle = crew[(t / period) % crew.size()]
		if phase == period / 2:
			who.at(s.run.tick).disconnect_at()
			outages += 1
		elif phase == period / 2 + outage:
			who.at(s.run.tick).reconnect_at()
		if t % 400 == 0:
			for h: MinerHandle in crew:
				h.at(s.run.tick).move(float((t / 400) % 4) * 90.0, InputRecord.Gait.WALK, 20)
		s.step(1)
	s.step(10 * hz)
	gut.p("%d minutes, %d outages, %d drops, %d retakes" % [minutes, outages, s.run.drops.drops.size(), s.run.drops.retakes.size()])
	assert_gt(outages, 0)
	assert_eq(s.run.drops.retakes.size(), s.run.drops.drops.size(), "every drop retaken")
	for h: MinerHandle in crew:
		var want: Array = owned[h.name]
		assert_true(h.is_connected_now(), "%s connected" % h.name)
		assert_eq(h.slot, int(Variants.number(want[0])), "%s in its own seat" % h.name)
		assert_eq(s.run.movement.miner(h.slot).entity_id, int(Variants.number(want[1])), "%s driving its own miner" % h.name)
		assert_eq(s.net.seats.seat_of(h.name).state, SeatTable.State.SEATED, "%s's seat is its own" % h.name)
	assert_true(s.run.hands.hands.is_empty(), "no Hand left holding a place")
