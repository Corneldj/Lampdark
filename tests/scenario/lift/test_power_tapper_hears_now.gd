extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-05 with SND-11 (Gameplay §3.3): out in the roads the Tapper hears 'Now!'. Listening from the
## rock behind the substation's switchgear, it takes Wilf's 'Now!' (the callout wheel's line, at
## talk), the trip's catch as it is taken and the switch's 20 np clunk.

const P = preload("res://tests/unit/lift/power_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_tapper_hears_now_the_catch_and_the_clunk() -> void:
	var s: Scenario = make({"seed": 5531, "fixture": P.room()})
	P.substation(s)
	s.run.power.links_cleared = true
	s.run.power.fuses_fitted = s.run.power.fuses_required()
	var wilf: MinerHandle = P.beside(s, "wilf", P.TRIP, Vector2i(-1, 0))
	var ellis: MinerHandle = P.beside(s, "ellis", P.SWITCH, Vector2i(1, 0))
	s.step(4)
	# A Tapper's ears in the rock south of the bay, between the trip and the switch.
	var ears: TapperHearing = TapperHearing.new(s.run, Tapper.LISTENER_BASE + 1)
	ears.listen_from(Vector2(9.5, 8.5))
	ears.take()
	wilf.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 120)
	wilf.at(s.run.tick + 2).callout("now", CalloutLines.TALK)
	assert_true(P.throw_after_cue(s, ellis, 0.4, 20))
	assert_true(s.run.power.is_on())
	var kinds: Array[NoiseTypes.Type] = []
	for e: TapperHearing.HeardEvent in ears.take():
		if not kinds.has(e.kind):
			kinds.append(e.kind)
	assert_true(kinds.has(NoiseTypes.Type.CALLOUT), "the rock hears 'Now!': %s" % str(kinds))
	assert_true(kinds.has(NoiseTypes.Type.TRIP_LEVER), "and the trip's catch")
	assert_true(kinds.has(NoiseTypes.Type.MAIN_SWITCH), "and the clunk")
