extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-12 (Gameplay §6.6, §3.5, §4.10; A.3): the phone's side of a call. The crank takes exactly 40
## ticks and makes one 14 np crank at the phone; before power, or on a cut or unrouted line, that is
## all; on a live, free line it calls the board. The operator's answer opens SND-07's line both ways
## and marks both heard; the caller leaving, grabbed or fallen ends it in that tick, and interact
## again hangs up. A ring makes one 20 np bell at a live phone and nothing at a dead one, and an
## interact while it rings answers it with no crank. A Hired Hand never cranks, answers or hangs up.

const P = preload("res://tests/unit/phones/phone_world.gd")

var calls: Array[Array] = []
var ends: Array[Array] = []


func before_all() -> void:
	assert_true(Tuning.load_server())


## Ann beside a phone at (6, 2); Bob, the operator, far east (his slot stands for the board's headset).
func _world(run_seed: int) -> Dictionary:
	var s: Scenario = make({"seed": run_seed, "fixture": P.road()})
	var p: PitPhone = P.phone(s, "p1", Vector2i(6, 2))
	var ann: MinerHandle = P.miner(s, "ann", Vector2i(5, 2))
	var bob: MinerHandle = P.miner(s, "bob", Vector2i(36, 2))
	s.step(3)
	calls.clear()
	ends.clear()
	s.run.phones.calling.connect(func(n: int, m: int) -> void: calls.append([n, m, s.run.tick]))
	s.run.phones.ended.connect(func(n: int, why: String) -> void: ends.append([n, why, s.run.tick]))
	return {"s": s, "p": p, "ann": ann, "bob": bob}


## The tick a crank by `h` started, holding until it is done.
func _crank(s: Scenario, h: MinerHandle) -> int:
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 50)
	for _i: int in 20:
		s.step()
		var a: TimedAction = s.run.inventory.actions.get(h.entity_id, null)
		if a != null and a.verb == &"crank":
			var started: int = a.started_tick
			s.step(50)
			return started
	return -1


func test_a_dead_line_cranks_and_nothing_more() -> void:
	var w: Dictionary = _world(4301)
	var s: Scenario = w["s"]
	var p: PitPhone = w["p"]
	var ann: MinerHandle = w["ann"]
	var started: int = _crank(s, ann)
	assert_gt(started, 0, "the crank begins")
	var cranks: Array[NoiseSystem.Event] = P.events_of(s, NoiseTypes.Type.PHONE_CRANK)
	assert_eq(cranks.size(), 1, "one crank")
	assert_eq(cranks[0].tick - started, 40, "after exactly 40 ticks")
	assert_eq(cranks[0].level_np, 14.0, "at 14 np")
	assert_true(cranks[0].origins.has(p.tile), "at the phone")
	assert_eq(calls.size(), 0, "before power, nothing reaches the board")
	assert_eq(p.caller, 0)
	P.power(s)
	p.cut = true
	_crank(s, ann)
	assert_eq(calls.size(), 0, "nor on a cut line")
	p.cut = false
	p.routed = false
	_crank(s, ann)
	assert_eq(calls.size(), 0, "nor on an unrouted one")
	assert_eq(P.events_of(s, NoiseTypes.Type.PHONE_CRANK).size(), 3, "though every crank is heard")


func test_a_live_call_and_its_ends() -> void:
	var w: Dictionary = _world(4302)
	var s: Scenario = w["s"]
	var p: PitPhone = w["p"]
	var ann: MinerHandle = w["ann"]
	var bob: MinerHandle = w["bob"]
	P.power(s)
	_crank(s, ann)
	assert_eq(calls.size(), 1, "a live, free line calls the board")
	var call: Array = calls[0]
	assert_eq(Variants.whole(call[0]), p.number)
	assert_eq(Variants.whole(call[1]), ann.entity_id)
	assert_eq(p.state, PitPhone.State.CALLING)
	var heard_before: int = s.run.heard.heard_log.size()
	assert_true(s.run.phones.answer(s.run, p.number, bob.slot), "the operator answers")
	assert_true(Variants.dict(s.run.voice.direct.get(ann.slot, {})).has(bob.slot), "the line open both ways")
	assert_true(Variants.dict(s.run.voice.direct.get(bob.slot, {})).has(ann.slot))
	var marks: Array = s.run.heard.heard_log.slice(heard_before).filter(func(r: Dictionary) -> bool: return r["cause"] == &"call")
	var slots: Array = marks.map(func(r: Dictionary) -> int: return int(Variants.number(r["slot"])))
	assert_true(slots.has(ann.slot) and slots.has(bob.slot), "both ends heard")
	# She steps away: the call ends.
	s.run.movement.place(s.run, ann.entity_id, Vector2(10.5, 2.5))
	s.step(2)
	assert_eq(ends.size(), 1)
	assert_eq(str(ends[0][1]), "left", "leaving the phone ends it")
	assert_false(Variants.dict(s.run.voice.direct.get(ann.slot, {})).has(bob.slot), "the line closed")
	# Back, on the line again; interact hangs up.
	s.run.movement.place(s.run, ann.entity_id, Vector2(5.5, 2.5))
	s.step(2)
	_crank(s, ann)
	assert_true(s.run.phones.answer(s.run, p.number, bob.slot))
	P.press(s, ann)
	assert_eq(str(ends[ends.size() - 1][1]), "hung up", "interact again hangs up")
	assert_eq(p.caller, 0)


func test_grabbed_or_fallen_the_call_ends_that_tick() -> void:
	var w: Dictionary = _world(4303)
	var s: Scenario = w["s"]
	var p: PitPhone = w["p"]
	var ann: MinerHandle = w["ann"]
	var bob: MinerHandle = w["bob"]
	P.power(s)
	_crank(s, ann)
	assert_true(s.run.phones.answer(s.run, p.number, bob.slot))
	var stythe: int = s.place_stand_in(WorldIds.EntityKind.STYTHE, Vector2i(20, 2))
	s.run.miner_state.enter_grabbed(ann.entity_id, &"drag", stythe)
	s.step(1)
	assert_eq(ends.size(), 1, "grabbed")
	assert_eq(str(ends[0][1]), "grabbed")
	var ended: Array = ends[0]
	assert_eq(Variants.whole(ended[2]), s.run.tick - 1, "in the tick it happened")
	assert_false(Variants.dict(s.run.voice.direct.get(bob.slot, {})).has(ann.slot), "the operator's end closed")
	# Another caller, fallen.
	var cat: MinerHandle = P.miner(s, "cat", Vector2i(7, 2))
	s.step(3)
	_crank(s, cat)
	assert_true(s.run.phones.answer(s.run, p.number, bob.slot))
	assert_true(s.run.falls.fall_unconscious(s.run, cat.entity_id, FallCause.Cause.BLAST))
	s.step(1)
	assert_eq(str(ends[ends.size() - 1][1]), "fell", "fallen")
	assert_eq(p.caller, 0)


func test_the_bell_rings_only_a_live_phone_and_answering_needs_no_crank() -> void:
	var w: Dictionary = _world(4304)
	var s: Scenario = w["s"]
	var p: PitPhone = w["p"]
	var ann: MinerHandle = w["ann"]
	var bob: MinerHandle = w["bob"]
	assert_false(s.run.phones.ring(s.run, p.number, bob.slot), "before power a ring does nothing")
	s.step(2)
	assert_eq(P.events_of(s, NoiseTypes.Type.PHONE_BELL).size(), 0)
	P.power(s)
	assert_true(s.run.phones.ring(s.run, p.number, bob.slot))
	s.step(2)
	var bells: Array[NoiseSystem.Event] = P.events_of(s, NoiseTypes.Type.PHONE_BELL)
	assert_eq(bells.size(), 1, "one bell")
	assert_eq(bells[0].level_np, 20.0, "at 20 np")
	assert_true(bells[0].origins.has(p.tile), "at the phone")
	assert_almost_eq(bells[0].duration_s, Tuning.f(&"phones.ring_burst_s"), 1e-6, "for the burst")
	P.press(s, ann)
	assert_eq(p.state, PitPhone.State.ON_CALL, "an interact answers it")
	assert_eq(P.events_of(s, NoiseTypes.Type.PHONE_CRANK).size(), 0, "with no crank")
	assert_true(Variants.dict(s.run.voice.direct.get(ann.slot, {})).has(bob.slot), "on the line to the operator who rang")


func test_a_hand_never_cranks_answers_or_hangs_up() -> void:
	var w: Dictionary = _world(4305)
	var s: Scenario = w["s"]
	var p: PitPhone = w["p"]
	var ann: MinerHandle = w["ann"]
	var bob: MinerHandle = w["bob"]
	P.power(s)
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == ann.entity_id
	assert_false(s.run.phones.interact(s.run, ann.entity_id, p.entity), "no crank")
	_crank(s, ann)
	assert_eq(P.events_of(s, NoiseTypes.Type.PHONE_CRANK).size(), 0, "a Hand's hold cranks nothing")
	assert_true(s.run.phones.ring(s.run, p.number, bob.slot))
	assert_false(s.run.phones.interact(s.run, ann.entity_id, p.entity), "nor answers")
	assert_eq(p.caller, 0)
	# On the line as herself (her earlier hold let go first), then a Hand drives her (a drop): she
	# leaves it, and the Hand hangs up nothing.
	s.step(60)
	s.run.crew.is_hand_driven = func(_e: int) -> bool: return false
	_crank(s, ann)
	assert_eq(p.caller, ann.entity_id)
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == ann.entity_id
	s.step(2)
	assert_eq(str(ends[ends.size() - 1][1]), "dropped", "a dropped caller leaves the line")
	assert_false(s.run.phones.interact(s.run, ann.entity_id, p.entity), "nor hangs up")
