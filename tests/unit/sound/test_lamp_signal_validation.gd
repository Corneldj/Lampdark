extends "res://tests/scenario/kit/scenario_test.gd"
## SND-12: a signal needs an open lamp in hand; it is refused shuttered or without one, carrying
## (two-handed or the can), Grabbed, unconscious or in the Aside, and a Caught miner may signal.
## HELP changes the light grid three times within 1.5 s, under 3 Hz. A signal is never heard and
## makes no Road Graph event.

const W = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _why_refused(s: Scenario, h: MinerHandle, kind: LampSignalKind.Kind) -> String:
	var before: int = s.run.lamp_signals.history.size()
	W.signal_press(s, h, kind)
	s.step(6)
	assert_gt(s.run.lamp_signals.history.size(), before, "the press reached the server")
	var row: Dictionary = s.run.lamp_signals.history[s.run.lamp_signals.history.size() - 1]
	assert_eq(int(Variants.number(row["kind"])), kind, "the wheel's slice decoded")
	return str(row["why"])


func test_refusals_and_the_caught_exception() -> void:
	var s: Scenario = make({"seed": 1101, "fixture": W.road()})
	var ann: MinerHandle = W.miner(s, "ann", s.fixture.spot("a"), 0.0)
	s.step(2)
	var events_before: int = s.run.noise.event_log.size()
	var heard_before: int = s.run.heard.heard_log.size()
	for kind: LampSignalKind.Kind in LampSignalKind.WHEEL:
		assert_eq(_why_refused(s, ann, kind), "", "%s made with an open lamp" % LampSignalKind.Kind.find_key(kind))
		s.step(45)
	var l: GauzeLamp = s.run.lamps.lamp_in_hand(ann.entity_id)
	s.run.lamps.shutter(s.run, l, false)
	s.step(8)
	assert_eq(_why_refused(s, ann, LampSignalKind.Kind.STOP), "no open lamp in hand", "shuttered")
	s.run.lamps.shutter(s.run, l, true)
	s.step(8)
	assert_true(s.run.inventory.begin_two_handed(s.run, ann.entity_id))
	assert_ne(_why_refused(s, ann, LampSignalKind.Kind.STOP), "", "carrying two-handed")
	s.run.inventory.end_two_handed(ann.entity_id)
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	h.free_hand = s.run.inventory.world.make(ItemKinds.Kind.PARAFFIN_CAN)
	assert_eq(_why_refused(s, ann, LampSignalKind.Kind.COME), "carrying", "the can (Proposed: any carry)")
	h.free_hand = null
	s.run.voice.set_route(ann.slot, VoiceRoutes.Route.ASIDE)
	assert_eq(_why_refused(s, ann, LampSignalKind.Kind.OK), "the Aside")
	s.run.voice.set_route(ann.slot, VoiceRoutes.Route.NORMAL)
	assert_true(s.run.holds.catch(s.run, ann.entity_id, CaughtHold.Kind.MAN_TRAP, 77))
	s.step(2)
	assert_eq(_why_refused(s, ann, LampSignalKind.Kind.HELP), "", "a Caught miner may signal")
	s.run.holds.release_caught(s.run, ann.entity_id, CaughtHold.Outcome.FREED)
	s.step(40)
	assert_gt(s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 400), 0)
	s.step(2)
	assert_ne(_why_refused(s, ann, LampSignalKind.Kind.STOP), "", "Grabbed")
	s.run.holds.end_grab(s.run, s.run.holds.grab_of(ann.entity_id).id, GrabHold.Outcome.RETREAT)
	s.step(2)
	# Every signal so far (the grab's own events aside): no Road Graph event, nobody heard.
	var hers: int = 0
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		if e.source_entity == ann.entity_id:
			hers += 1
	assert_eq(hers, 0, "no signal makes a Road Graph event")
	for row: Dictionary in s.run.heard.heard_log.slice(heard_before):
		assert_ne(int(Variants.number(row["slot"])), ann.slot, "and nobody is heard by one")
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(2)
	assert_ne(_why_refused(s, ann, LampSignalKind.Kind.STOP), "", "unconscious")


func test_help_blinks_three_times_under_three_hertz() -> void:
	var s: Scenario = make({"seed": 1102, "fixture": W.road()})
	var ann: MinerHandle = W.miner(s, "ann", s.fixture.spot("a"), 0.0)
	s.step(4)
	var probe: Vector2i = s.fixture.spot("a") + Vector2i(1, 0)
	var lit: float = s.run.light.light_at(probe)
	assert_gt(lit, 0.3)
	W.signal_press(s, ann, LampSignalKind.Kind.HELP)
	var samples: Array[bool] = []
	for _i: int in 45:
		s.step(1)
		samples.append(s.run.light.light_at(probe) < lit * 0.5)
	var pulses: Array[int] = []
	for i: int in range(1, samples.size()):
		if samples[i] and not samples[i - 1]:
			pulses.append(i)
	gut.p("dark pulses start at %s" % [pulses])
	assert_eq(pulses.size(), 3, "three blinks")
	assert_lte(pulses[2] - pulses[0], roundi(1.5 * 20.0), "within 1.5 s")
	for i: int in range(1, pulses.size()):
		assert_gte(pulses[i] - pulses[i - 1], 7, "under 3 Hz (at least 7 ticks apart)")
	assert_false(samples[samples.size() - 1], "lit again after")
