extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09: a 3 s silent pull frees the victim, Hurt and rock-touched; talk within 8 tiles during
## the pull brings a 0.5 s ReStrike 80 ticks later and the crush resumes at its elapsed time.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_clean_pull() -> void:
	var s: Scenario = make({"seed": 40, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	var t: Tapper = r[1]
	var bob: MinerHandle = s.add_miner("bob", Vector2i(11, 5))
	s.step(2)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 70)
	s.step(75)
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.UPRIGHT, "freed by the silent pull")
	var m: MinerStateSystem.Miner = s.run.miner_state.miner(ann.entity_id)
	assert_gt(m.overlays.hurt_until, s.run.tick, "Hurt")
	assert_true(m.overlays.rock_touched(s.run.tick), "rock-touched")
	assert_eq(t.state.name, &"listen")


func test_spoiled_pull_restrikes() -> void:
	var s: Scenario = make({"seed": 41, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	var bob: MinerHandle = s.add_miner("bob", Vector2i(11, 5))
	s.step(2)
	var g: GrabHold = s.run.holds.grab_of(ann.entity_id)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 70)
	s.step(10)
	W.talk(s, bob)
	s.step(2)
	var spoiled: Array[Dictionary] = s.run.creatures.log.of_type(&"tapper_pull_spoiled")
	assert_eq(spoiled.size(), 1, "the talk spoiled the pull")
	var at_spoil: int = spoiled[0]["tick"]
	s.step(55)
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.UPRIGHT, "the pull still freed her")
	var elapsed: int = g.elapsed
	var landed: Array[int] = [-1]
	var elapsed_at_landing: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		if landed[0] < 0 and W.life(sc, ann.entity_id) == MinerTransitions.Life.GRABBED:
			landed[0] = sc.run.tick
			elapsed_at_landing[0] = g.elapsed
	s.step(120)
	var windups: Array[Dictionary] = s.run.creatures.log.of_type(&"wind_up_started")
	var restrike: Dictionary = windups[windups.size() - 1]
	assert_eq(int(Variants.number(restrike["start"])) - at_spoil, 80, "the ReStrike 80 ticks after the spoiling word")
	assert_eq(int(Variants.number(restrike["end"])) - int(Variants.number(restrike["start"])), 10, "a 0.5 s wind-up")
	assert_gt(landed[0], 0, "it landed: pinned again")
	assert_eq(s.run.holds.grab_of(ann.entity_id).id, g.id, "the same grab")
	gut.p("crush at the pull: %d ticks; at the ReStrike's landing: %d" % [elapsed, elapsed_at_landing[0]])
	assert_between(elapsed_at_landing[0] - elapsed, 0, 1, "the crush runs on from where it stopped, never restarting")
