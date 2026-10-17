extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-05: the Power job's steps in order, what they spend and what they refuse. The links take 4 s
## and the cutters, which are kept; let go early and nothing changes. Fuses come after the links,
## 2 s and one fuse each, a fourth refused. The switch is there only with three fuses in; a throw on
## the trip's cue closes it with one 20 np clunk, power on once, Power done; a miss changes nothing.
## A Hand works none of it. The fixtures show their steps; the state survives a save.

const P = preload("res://tests/unit/lift/power_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _room(run_seed: int, cfg: Dictionary = {}) -> Scenario:
	var c: Dictionary = {"seed": run_seed, "fixture": P.room()}
	c.merge(cfg, true)
	var s: Scenario = make(c)
	P.substation(s)
	return s


func test_the_links_take_four_seconds_and_the_cutters_which_are_kept() -> void:
	var s: Scenario = _room(5501)
	var ann: MinerHandle = P.beside(s, "ann", P.BOARD)
	s.step(3)
	P.hold(s, ann, 10)
	assert_false(s.run.power.links_cleared)
	assert_eq(str(s.run.power.refused.back()["why"]), "no cutters")
	P.give(s, ann, ItemKinds.Kind.WIRE_CUTTERS)
	P.hold(s, ann, 40)
	assert_false(s.run.power.links_cleared, "let go after 2 s: nothing changes")
	P.hold(s, ann, 86)
	assert_true(s.run.power.links_cleared, "4 s of held interact clears the links")
	assert_eq(s.run.inventory.hands_of(ann.entity_id).count_of(ItemKinds.Kind.WIRE_CUTTERS), 1, "the cutters kept")
	assert_eq(P.events(s, NoiseTypes.Type.MAIN_SWITCH).size(), 0)


func test_fuses_after_the_links_two_seconds_and_one_fuse_each() -> void:
	var s: Scenario = _room(5502)
	var ann: MinerHandle = P.beside(s, "ann", P.BOARD)
	s.step(3)
	P.give(s, ann, ItemKinds.Kind.FUSE, 3)
	P.give(s, ann, ItemKinds.Kind.FUSE, 1)
	assert_eq(s.run.power.why_not_fit(s.run, ann.entity_id), "links", "no fuse before the links are cleared")
	P.hold(s, ann, 46)
	assert_eq(s.run.power.fuses_fitted, 0)
	assert_eq(str(s.run.power.refused.back()["why"]), "no cutters", "the board's step is the links: refused without the cutters")
	assert_eq(s.run.tools_parts.count_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE), 4, "no fuse spent")
	P.give(s, ann, ItemKinds.Kind.WIRE_CUTTERS)
	P.hold(s, ann, 86)
	assert_true(s.run.power.links_cleared)
	var tp: ToolsParts = s.run.tools_parts
	P.hold(s, ann, 20)
	assert_eq(s.run.power.fuses_fitted, 0, "let go after 1 s: no fuse in")
	assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE), 4, "and none spent")
	for i: int in 3:
		P.hold(s, ann, 46)
		assert_eq(s.run.power.fuses_fitted, i + 1, "fuse %d in after 2 s" % (i + 1))
		assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE), 3 - i, "one fuse spent a fit")
	P.hold(s, ann, 46)
	assert_eq(s.run.power.fuses_fitted, 3, "a fourth is refused")
	assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE), 1)


func test_the_switch_waits_for_three_fuses_then_closes_once() -> void:
	var s: Scenario = _room(5503)
	var ann: MinerHandle = P.beside(s, "ann", P.BOARD)
	var bob: MinerHandle = P.beside(s, "bob", P.SWITCH, Vector2i(-1, 0))
	s.step(3)
	var fired: Array[int] = []
	s.run.power.power_on.connect(func(tick: int) -> void: fired.append(tick))
	P.ready_switch(s, ann, 2)
	assert_eq(s.run.power.fuses_fitted, 2)
	assert_null(s.run.power.main_switch, "no switch to throw with two fuses in")
	P.hold(s, bob, 6)
	assert_false(s.run.power.is_on(), "a throw with two fuses does nothing")
	P.give(s, ann, ItemKinds.Kind.FUSE)
	P.hold(s, ann, 46)
	assert_eq(s.run.power.fuses_fitted, 3)
	s.step(2)
	assert_not_null(s.run.power.main_switch, "three fuses in: the switch can be thrown")
	# Ann takes the trip; Bob throws too late, then on time.
	s.run.movement.place(s.run, ann.entity_id, Vector2(P.TRIP + Vector2i(1, 0)) + Vector2(0.5, 0.5))
	ann.at(s.run.tick).face(180.0)
	s.step(2)
	var from: int = s.run.noise.event_log.size()
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 60)
	assert_true(P.throw_after_cue(s, bob, 1.6))
	assert_false(s.run.power.is_on(), "a throw after the 1 s window misses")
	assert_true(P.whats(s.run.power).has("miss"))
	assert_eq(P.events(s, NoiseTypes.Type.MAIN_SWITCH, from).size(), 0, "a miss is silent")
	# The trip let go, and taken again for a new cue.
	s.step(30)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 200)
	assert_true(P.throw_after_cue(s, bob, 0.3))
	assert_true(s.run.power.is_on(), "on 'Now!' within the window: closed")
	var clunks: Array[NoiseSystem.Event] = P.events(s, NoiseTypes.Type.MAIN_SWITCH, from)
	assert_eq(clunks.size(), 1, "one clunk")
	if clunks.size() == 1:
		assert_eq(clunks[0].level_np, 20.0)
		assert_eq(clunks[0].origins, [P.SWITCH] as Array[Vector2i], "at the switch")
	assert_eq(fired, [s.run.power.on_tick] as Array[int], "power_on fires once")
	assert_true(s.run.repair.is_done(&"power"), "Power marked done")
	assert_true(P.events(s, NoiseTypes.Type.TRIP_LEVER, from).size() >= 2, "each take of the trip catches it")
	s.step(10)
	assert_null(s.run.power.main_switch, "closed: nothing left to throw")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 40)
	s.step(20)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 4)
	s.step(30)
	assert_eq(fired.size(), 1, "never twice")
	assert_eq(P.events(s, NoiseTypes.Type.MAIN_SWITCH, from).size(), 1)


func test_a_hand_never_clears_fits_holds_or_throws() -> void:
	var s: Scenario = _room(5504, {"mode": ServerConfig.Mode.PUBLIC})
	var hand: MinerHandle = P.beside(s, "hand", P.BOARD)
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id
	s.step(3)
	P.give(s, hand, ItemKinds.Kind.WIRE_CUTTERS)
	P.give(s, hand, ItemKinds.Kind.FUSE, 3)
	P.hold(s, hand, 86)
	assert_false(s.run.power.links_cleared, "a Hand never clears the links")
	assert_eq(str(s.run.power.refused.back()["why"]), "a Hand")
	assert_eq(s.run.power.why_not_fit(s.run, hand.entity_id), "a Hand")
	# With the switch ready, a Hand takes no place at it.
	s.run.power.links_cleared = true
	s.run.power.fuses_fitted = 3
	s.step(2)
	assert_not_null(s.run.power.main_switch)
	s.run.movement.place(s.run, hand.entity_id, Vector2(P.TRIP + Vector2i(1, 0)) + Vector2(0.5, 0.5))
	hand.at(s.run.tick).face(180.0)
	s.step(2)
	P.hold(s, hand, 40)
	assert_eq(s.run.power.main_switch.state, CuePress.State.IDLE, "a Hand never holds the trip")
	assert_false(s.run.two_miner.refused.is_empty(), "its take refused and logged")


func test_the_fixtures_show_their_steps_and_the_glyphs_follow() -> void:
	var s: Scenario = _room(5505)
	var power: PowerJob = s.run.power
	var board: int = int(Variants.number(power.fixtures["fuse_board"]))
	var trip: int = int(Variants.number(power.fixtures["trip_lever"]))
	var throw: int = int(Variants.number(power.fixtures["main_switch"]))
	assert_true(s.run.registry.has(board) and s.run.registry.has(trip) and s.run.registry.has(throw), "three fixtures")
	var bits: Dictionary = power.fixture_bits()
	var b: int = int(Variants.number(bits[board]))
	assert_eq(FixtureKinds.kind_of(b), FixtureKinds.Kind.FUSE_BOARD)
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.FIXTURE, 0, b), "verb.clear_links")
	power.links_cleared = true
	power.fuses_fitted = 1
	b = int(Variants.number(power.fixture_bits()[board]))
	assert_eq(FixtureKinds.read_fuse_board(b), {"cleared": true, "fuses": 1, "full": false})
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.FIXTURE, 0, b), "verb.fit_fuse")
	power.fuses_fitted = 3
	b = int(Variants.number(power.fixture_bits()[board]))
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.FIXTURE, 0, b), "", "full: nothing more to do at the board")
	var t: int = int(Variants.number(power.fixture_bits()[trip]))
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.FIXTURE, 0, t), "verb.hold_trip")
	assert_false(FixtureKinds.flag_of(t))
	var w: int = int(Variants.number(power.fixture_bits()[throw]))
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.FIXTURE, 0, w), "verb.throw")
	power.switch_closed = true
	w = int(Variants.number(power.fixture_bits()[throw]))
	assert_true(FixtureKinds.flag_of(w))
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.FIXTURE, 0, w), "", "closed: nothing to throw")


func test_the_state_survives_a_save_and_power_stays_on() -> void:
	var s: Scenario = _room(5506)
	var power: PowerJob = s.run.power
	power.links_cleared = true
	power.fuses_fitted = 2
	var saved: Dictionary = power.save_state()
	var b: Scenario = _room(5506)
	b.run.power.load_state(b.run, saved)
	assert_true(b.run.power.links_cleared)
	assert_eq(b.run.power.fuses_fitted, 2)
	assert_false(b.run.power.is_on())
	power.fuses_fitted = 3
	power.switch_closed = true
	power.on_tick = 77
	var c: Scenario = _room(5507)
	c.run.power.load_state(c.run, power.save_state())
	assert_true(c.run.power.is_on(), "power on after a resume")
	assert_eq(c.run.power.on_tick, 77)
	c.step(4)
	assert_null(c.run.power.main_switch, "and no switch left to throw")
	assert_true(c.run.power.lines_live() and c.run.power.board_wakes())
	c.run.power.dead_lines = true
	assert_false(c.run.power.lines_live() or c.run.power.board_wakes(), "Dead Lines: no board, no lines")


func test_a_hand_never_throws() -> void:
	var s: Scenario = _room(5508, {"mode": ServerConfig.Mode.PUBLIC})
	s.run.power.links_cleared = true
	s.run.power.fuses_fitted = s.run.power.fuses_required()
	var ann: MinerHandle = P.beside(s, "ann", P.TRIP, Vector2i(-1, 0))
	var hand: MinerHandle = P.beside(s, "hand", P.SWITCH, Vector2i(1, 0))
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id
	s.step(4)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 80)
	assert_true(P.throw_after_cue(s, hand, 0.3))
	assert_false(s.run.power.is_on(), "a Hand's throw never closes the switch")


func test_power_survives_a_save_and_resume() -> void:
	const S = preload("res://tests/scenario/net/save_world.gd")
	S.clear(5509)
	var s: Scenario = _room(5509, {"saves": true})
	var ann: MinerHandle = P.beside(s, "ann", P.TRIP, Vector2i(-1, 0))
	var bob: MinerHandle = P.beside(s, "bob", P.SWITCH, Vector2i(1, 0))
	s.run.power.links_cleared = true
	s.run.power.fuses_fitted = s.run.power.fuses_required()
	s.step(4)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 80)
	assert_true(P.throw_after_cue(s, bob, 0.3))
	assert_true(s.run.power.is_on())
	var on_tick: int = s.run.power.on_tick
	assert_true(S.until_saved(s, 1))
	var path: String = S.snapshot_path(s)
	S.kill(s)
	var opened: Dictionary = SaveResume.open_file(path)
	assert_true(Variants.flag(opened["ok"]), str(opened["message"]))
	var b: Scenario = _room(5509, {"saves": true})
	SaveResume.apply(b.run, b.net, opened)
	assert_true(b.run.power.is_on(), "power is on after the resume")
	assert_eq(b.run.power.on_tick, on_tick)
	assert_true(b.run.power.links_cleared)
	assert_eq(b.run.power.fuses_fitted, b.run.power.fuses_required())
	assert_true(b.run.repair.is_done(&"power"), "and Power still done")
	b.step(4)
	assert_null(b.run.power.main_switch, "nothing to throw again")
	assert_eq(b.run.power.fixtures.size(), 3, "its fixtures stand")
