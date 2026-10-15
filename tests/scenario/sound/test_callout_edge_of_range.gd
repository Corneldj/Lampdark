extends "res://tests/scenario/kit/scenario_test.gd"
## SND-11: a callout carries as live voice does (Gameplay §6.2, §6.7). Talk reaches 12 tiles and not
## 13; at 9 it loses about a fifth of its frames, in runs of 3-10; a shut gate cuts it. Its speaker is
## heard when a conscious teammate keeps at least half; its Road Graph events are the same whatever
## the listeners lost.

const N = preload("res://tests/scenario/net/net04_world.gd")
const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _wait(s: Scenario) -> void:
	s.step(80)


func test_talk_reaches_twelve_not_thirteen() -> void:
	var s: Scenario = make({"seed": 421, "fixture": N.road(40)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(12, 0))
	var cid: MinerHandle = s.add_miner("cid", a + Vector2i(13, 0))
	s.step(3)
	assert_gt(s.run.callouts.speak(s.run, ann.slot, "here", CalloutLines.TALK), 0)
	s.step(4)
	assert_eq(bob.connection.callouts.size(), 1, "12 tiles: heard")
	assert_eq(cid.connection.callouts.size(), 0, "13 tiles: nothing")


func test_nine_tiles_loses_a_fifth_in_runs() -> void:
	var s: Scenario = make({"seed": 422, "fixture": N.road(40)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(9, 0))
	s.step(3)
	var frames: int = 0
	var dropped: int = 0
	var runs: Array[int] = []
	for i: int in 40:
		assert_gt(s.run.callouts.speak(s.run, ann.slot, CalloutLines.WHEEL[i % 12], CalloutLines.TALK), 0)
		_wait(s)
	for r: CalloutRecord in bob.connection.callouts:
		var run_len: int = 0
		for k: int in r.mask.size():
			frames += 1
			if r.mask[k] == 0:
				dropped += 1
				run_len += 1
			elif run_len > 0:
				if k - run_len > 0:
					runs.append(run_len)  # a whole run, not one cut by the line's start
				run_len = 0
	var share: float = float(dropped) / frames
	gut.p("9 tiles: %d of %d frames dropped (%.1f%%), %d whole runs %s..%s" % [dropped, frames, share * 100.0, runs.size(), runs.min(), runs.max()])
	assert_eq(bob.connection.callouts.size(), 40)
	assert_almost_eq(share, 0.2, 0.05, "about 20%")
	var shortest: int = runs.min()
	var longest: int = runs.max()
	assert_gte(shortest, 3)
	assert_lte(longest, 10)


func test_a_shut_gate_cuts_it() -> void:
	var s: Scenario = make({"seed": 423, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	var ann: MinerHandle = s.add_miner("ann", west.middle() - west.outward)
	var bob: MinerHandle = s.add_miner("bob", west.middle() + west.outward * 2)
	s.step(3)
	assert_gt(s.run.callouts.speak(s.run, ann.slot, "gate", CalloutLines.SHOUT), 0)
	_wait(s)
	assert_eq(bob.connection.callouts.size(), 0, "a shut gate cuts a shout")
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	s.step(2)
	assert_gt(s.run.callouts.speak(s.run, ann.slot, "gate", CalloutLines.SHOUT), 0)
	s.step(4)
	assert_eq(bob.connection.callouts.size(), 1, "open: heard")


func test_heard_at_half_and_events_whatever_was_lost() -> void:
	# The rule itself: half kept counts, a hair under does not.
	var s: Scenario = make({"seed": 424, "fixture": N.road(40)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(2, 0))
	s.step(3)
	assert_true(s.run.heard.callout_counts(ann.slot, {bob.slot: 0.5}, 2), "50% heard")
	assert_false(s.run.heard.callout_counts(ann.slot, {bob.slot: 0.49}, 2), "49% not")
	# The callout itself makes its speaker heard when it arrives.
	s.step(100)
	var before: float = s.run.heard.unheard_seconds(ann.slot)
	assert_gt(s.run.callouts.speak(s.run, ann.slot, "here", CalloutLines.TALK), 0)
	s.step(1)
	assert_lt(s.run.heard.unheard_seconds(ann.slot), before, "heard: the timer starts again")
	# Band events: the same ticks and levels with a listener losing frames and with one losing none.
	var events: Array = []
	for d: int in [2, 9]:
		var t: Scenario = make({"seed": 425, "fixture": N.road(40)})
		var s0: Vector2i = t.fixture.spot("a")
		var x: MinerHandle = t.add_miner("x", s0)
		t.add_miner("y", s0 + Vector2i(d, 0))
		t.step(3)
		var start: int = t.run.tick
		assert_gt(t.run.callouts.speak(t.run, x.slot, "moth", CalloutLines.SHOUT), 0)
		t.step(90)
		var mine: Array = []
		for e: NoiseSystem.Event in t.run.noise.event_log:
			if e.type == NoiseTypes.Type.CALLOUT:
				mine.append([e.tick - start, e.level_np, e.mode, e.to_players])
		events.append(mine)
	var first: Array = events[0]
	assert_gt(first.size(), 2, "events through the bark")
	var second: Array = events[1]
	assert_eq(first, second, "identical whatever the listener lost")
	for ev: Variant in first:
		var row: Array = ev
		assert_almost_eq(float(Variants.number(row[1])), Tuning.f(&"voice.shout_np"), 1e-6, "at the band's np")
		assert_false(Variants.flag(row[3]), "creatures only: players hear the bark itself")
