extends "res://tests/scenario/kit/scenario_test.gd"
## SND-11: on a live phone line (LFT-12's direct route, stood in here), the other end gets the whole
## bark with the telephone flag, however far away it is.

const N = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_whole_bark_down_the_line() -> void:
	var s: Scenario = make({"seed": 431, "fixture": N.road(40)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(34, 0))
	s.step(3)
	s.run.voice.open_direct(ann.slot, bob.slot)
	assert_gt(s.run.callouts.speak(s.run, ann.slot, "help", CalloutLines.WHISPER), 0)
	s.step(4)
	assert_eq(bob.connection.callouts.size(), 1, "34 tiles away, a whisper, down the line")
	var r: CalloutRecord = bob.connection.callouts[0]
	assert_true((r.flags & CalloutRecord.FLAG_TELEPHONE) != 0, "the telephone flag")
	assert_almost_eq(r.kept_share(), 1.0, 1e-9, "every frame")
