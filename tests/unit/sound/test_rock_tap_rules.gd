extends "res://tests/scenario/kit/scenario_test.gd"
## SND-12: a tap on the wall is one 10 np rock_tap event; a ring-1 Tapper stub hears it 6 tiles off,
## not 7; a tap that reaches only a deafened teammate marks nobody heard and sends them nothing; a
## carrier, a Grabbed miner or one in the Aside cannot tap, a Caught one can, and taps come at most
## one per 0.12 s.

const W = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	WorldCoords.ring_override = -1


## Ann against the north wall, facing it.
func _ann(s: Scenario) -> MinerHandle:
	return W.miner(s, "ann", s.fixture.spot("a") + Vector2i(0, -1), 270.0, false)


func _tap(s: Scenario, ann: MinerHandle) -> Dictionary:
	var before: int = s.run.rock_taps.taps.size()
	W.tap_press(s, ann)
	s.step(5)
	return s.run.rock_taps.taps[before] if s.run.rock_taps.taps.size() > before else {}


func test_ten_np_heard_by_a_ring_one_tapper_at_six() -> void:
	WorldCoords.ring_override = 1
	var s: Scenario = make({"seed": 1131, "fixture": W.road(30)})
	var ann: MinerHandle = _ann(s)
	s.step(2)
	var heard: Dictionary = {}
	var mult: float = CreatureTables.tapper_hearing_mult(1)
	var air: Vector2i = s.fixture.spot("a") + Vector2i(0, -1)
	s.run.noise.set_creature_listener(9001, air + Vector2i(6, 0), mult)
	s.run.noise.set_creature_listener(9002, air + Vector2i(7, 0), mult)
	s.run.noise.creature_hooks.append(func(e: NoiseSystem.Event, d: Dictionary) -> void:
		if e.type == NoiseTypes.Type.ROCK_TAP:
			heard[int(Variants.number(d["listener"]))] = true)
	var events_before: int = s.run.noise.event_log.size()
	var t: Dictionary = _tap(s, ann)
	assert_false(Variants.flag(t["refused"]), "a wall in reach, facing it")
	var taps: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		if e.type == NoiseTypes.Type.ROCK_TAP:
			taps.append(e)
	assert_eq(taps.size(), 1, "one event a tap")
	assert_almost_eq(taps[0].level_np, 10.0, 1e-6, "10 np")
	assert_true(heard.has(9001), "the Tapper hears it 6 tiles off")
	assert_false(heard.has(9002), "not 7")


func test_only_a_deafened_listener_marks_nobody_heard() -> void:
	var s: Scenario = make({"seed": 1132, "fixture": W.road(30)})
	var ann: MinerHandle = _ann(s)
	var bob: MinerHandle = W.miner(s, "bob", s.fixture.spot("a") + Vector2i(3, 0), 180.0, false)
	s.run.deafen.deafen(s.run, bob.slot, 30.0)
	s.step(2)
	var heard_before: int = s.run.heard.heard_log.size()
	var deliveries_before: int = s.run.audio.deliveries.size()
	assert_false(Variants.flag(_tap(s, ann)["refused"]))
	for row: Dictionary in s.run.heard.heard_log.slice(heard_before):
		assert_ne(int(Variants.number(row["slot"])), ann.slot, "nobody heard her")
	for d: Dictionary in s.run.audio.deliveries.slice(deliveries_before):
		assert_ne(int(Variants.number(d["client"])), bob.slot, "and Bob got no record")
	s.step(700)
	heard_before = s.run.heard.heard_log.size()
	assert_false(Variants.flag(_tap(s, ann)["refused"]))
	var marked: bool = false
	for row: Dictionary in s.run.heard.heard_log.slice(heard_before):
		marked = marked or (int(Variants.number(row["slot"])) == ann.slot and StringName(str(row["cause"])) == &"tap")
	assert_true(marked, "once Bob hears again, her tap makes her heard")


func test_who_may_tap() -> void:
	var s: Scenario = make({"seed": 1133, "fixture": W.road(30)})
	var ann: MinerHandle = _ann(s)
	s.step(2)
	assert_true(s.run.inventory.begin_two_handed(s.run, ann.entity_id))
	assert_true(Variants.flag(_tap(s, ann)["refused"]), "a carrier")
	s.run.inventory.end_two_handed(ann.entity_id)
	s.run.voice.set_route(ann.slot, VoiceRoutes.Route.ASIDE)
	assert_true(Variants.flag(_tap(s, ann)["refused"]), "the Aside")
	s.run.voice.set_route(ann.slot, VoiceRoutes.Route.NORMAL)
	assert_true(s.run.holds.catch(s.run, ann.entity_id, CaughtHold.Kind.MAN_TRAP, 77))
	s.step(2)
	assert_false(Variants.flag(_tap(s, ann)["refused"]), "Caught: may tap")
	s.run.holds.release_caught(s.run, ann.entity_id, CaughtHold.Outcome.FREED)
	s.step(2)
	assert_gt(s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 400), 0)
	s.step(2)
	assert_true(Variants.flag(_tap(s, ann)["refused"]), "Grabbed")
	s.run.holds.end_grab(s.run, s.run.holds.grab_of(ann.entity_id).id, GrabHold.Outcome.RETREAT)
	s.step(2)
	# Two taps a tick apart: the second is too soon.
	var before: int = s.run.rock_taps.taps.size()
	W.tap_press(s, ann, s.run.tick + 1)
	W.tap_press(s, ann, s.run.tick + 2)
	s.step(6)
	var rows: Array[Dictionary] = s.run.rock_taps.taps.slice(before)
	assert_eq(rows.size(), 2)
	assert_false(Variants.flag(rows[0]["refused"]))
	assert_eq(str(rows[1]["why"]), "too soon", "one tap per 0.12 s at most")
	# Facing away from every wall: nothing to tap.
	var bob: MinerHandle = W.miner(s, "bob", s.fixture.spot("a") + Vector2i(10, 0), 0.0, false)
	s.step(2)
	before = s.run.rock_taps.taps.size()
	W.tap_press(s, bob)
	s.step(5)
	assert_eq(str(s.run.rock_taps.taps[before]["why"]), "no wall in reach", "the middle of the road, facing along it")
