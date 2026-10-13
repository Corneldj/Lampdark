extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-13: the fireman's carry. Lift is offered only on an unconscious or dead miner in touch range,
## takes 40 ticks of held interact, spends nothing if released and hooks the lamp at its start; it
## is refused with a blocker in the free hand or on a body a trap holds. Carrying walks at 1.5
## tiles/s (1.2 Hurt), never runs or crouches, on 12 np steps every 10 ticks; only shutter, voice
## and callouts work; interact sets the body down at once on the carrier's tile, the lamp back in
## the hand.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const F = preload("res://tests/unit/mnr/input_frames.gd")

const ROWS: PackedStringArray = [
	"##########################",
	"#........................#",
	"#..a.b...................#",
	"#........................#",
	"##########################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


## Ann (lit lamp in hand) beside Bob, who has fallen unconscious.
func _setup(run_seed: int, fall: bool = true) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": FixtureMap.from_ascii(ROWS)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("a") + Vector2i(1, 0))
	s.step(1)
	var lamp: GauzeLamp = L.lit_in_hand(s, ann)
	if fall:
		assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	return [s, ann, bob, lamp]


func test_offered_only_on_the_fallen() -> void:
	var parts: Array = _setup(1, false)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var carry: FiremanCarry = s.run.carry
	assert_false(carry.may_lift(s.run, ann.entity_id, bob.entity_id), "Upright: no lift")
	assert_false(s.run.ring.registry.offered(s.run, ann.entity_id, bob.entity_id).has("lift"))
	s.run.miner_state.enter_caught(bob.entity_id, &"man_trap", 1)
	s.step(1)
	assert_false(carry.may_lift(s.run, ann.entity_id, bob.entity_id), "Caught: no lift")
	var cases: Dictionary = {"grabbed": false, "unconscious": true, "dead": true}
	var n: int = 2
	for raw: Variant in cases.keys():
		var case: String = str(raw)
		var p: Array = _setup(n, case == "unconscious")
		n += 1
		var t: Scenario = p[0]
		var a2: MinerHandle = p[1]
		var b2: MinerHandle = p[2]
		if case == "grabbed":
			t.run.miner_state.enter_grabbed(b2.entity_id, &"stythe_drag", 999)
		elif case == "dead":
			t.run.miner_state.kill(b2.entity_id, "test")
		t.step(2)
		var want: bool = Variants.flag(cases[raw])
		assert_eq(t.run.carry.may_lift(t.run, a2.entity_id, b2.entity_id), want, case)
		assert_eq(t.run.ring.registry.offered(t.run, a2.entity_id, b2.entity_id).has("lift"), want, "%s: the ring" % case)


func test_lift_takes_40_ticks_and_hooks_at_start() -> void:
	var parts: Array = _setup(5)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var a: TimedAction = s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)
	assert_eq(a.ticks_needed, 40, "2 s at 20 Hz")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 60)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, a))
	assert_true(W.belt(s, ann.entity_id).hooked, "the lamp hooks when the lift starts")
	s.step(39)
	assert_false(s.run.carry.is_carrying(ann.entity_id), "39 ticks: still lifting")
	assert_eq(a.ticks_done, 39)
	s.step(1)
	assert_true(s.run.carry.is_carrying(ann.entity_id), "40 ticks of held interact")
	assert_eq(s.run.falls.body_of(bob.entity_id).carried_by, ann.entity_id)


func test_released_early_spends_nothing() -> void:
	var parts: Array = _setup(6)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var lamp: GauzeLamp = parts[3]
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(40)
	assert_false(s.run.carry.is_carrying(ann.entity_id), "released at 1.5 s: no carry")
	assert_false(W.belt(s, ann.entity_id).hooked, "the lamp back in the hand")
	assert_false(W.belt(s, ann.entity_id).two_handed)
	assert_true(s.run.falls.body_of(bob.entity_id).on_floor)
	assert_eq(s.run.falls.body_of(bob.entity_id).carried_by, 0)
	assert_eq(s.run.lamps.lamp_in_hand(ann.entity_id), lamp, "the same lamp, in hand, burning")
	assert_true(lamp.burning())


func test_refused_with_a_blocker_or_a_trap() -> void:
	for kind: ItemKinds.Kind in [ItemKinds.Kind.REVOLVER, ItemKinds.Kind.PARAFFIN_CAN, ItemKinds.Kind.FLARE]:
		var parts: Array = _setup(7 + kind)
		var s: Scenario = parts[0]
		var ann: MinerHandle = parts[1]
		var bob: MinerHandle = parts[2]
		W.belt(s, ann.entity_id).free_hand = s.run.inventory.world.make(kind)
		assert_false(s.run.carry.may_lift(s.run, ann.entity_id, bob.entity_id), "free hand: %s" % kind)
		assert_false(s.run.ring.registry.offered(s.run, ann.entity_id, bob.entity_id).has("lift"))
		ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 50)
		s.step(1)
		s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id))
		s.step(45)
		assert_false(s.run.carry.is_carrying(ann.entity_id))
		assert_false(W.belt(s, ann.entity_id).two_handed)
	# A body a trap still holds: free it first.
	var p: Array = _setup(30, false)
	var t: Scenario = p[0]
	var lifter: MinerHandle = p[1]
	var trapped: MinerHandle = p[2]
	t.run.miner_state.enter_caught(trapped.entity_id, &"man_trap", 1)
	t.step(1)
	assert_true(t.run.falls.fall_unconscious(t.run, trapped.entity_id, FallCause.Cause.BLAST))
	t.step(2)
	assert_true(t.run.falls.body_of(trapped.entity_id).held_by_trap)
	assert_false(t.run.carry.may_lift(t.run, lifter.entity_id, trapped.entity_id), "held by a trap: no lift")


## Ann carrying Bob, the lift's hold released.
func _carrying(run_seed: int) -> Array:
	var parts: Array = _setup(run_seed)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(45)
	assert_true(s.run.carry.is_carrying(ann.entity_id))
	return parts


func _walk(s: Scenario, h: MinerHandle, gait: InputRecord.Gait, ticks: int) -> float:
	var x0: float = s.run.registry.get_entity(h.entity_id).position.x
	h.at(s.run.tick).move(0.0, gait, ticks)
	# Inputs apply a tick after they are scripted: step past the last one.
	s.step(ticks + 2)
	return s.run.registry.get_entity(h.entity_id).position.x - x0


func test_carry_pace_and_steps() -> void:
	var parts: Array = _carrying(40)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var speed: float = Tuning.f(&"movement.carry_fireman_speed")
	var before: int = s.run.noise.event_log.size()
	var moved: float = _walk(s, ann, InputRecord.Gait.WALK, 40)
	assert_almost_eq(moved, speed * 2.0, 0.08, "1.5 tiles/s walking")
	var steps: Array[NoiseSystem.Event] = []
	for i: int in range(before, s.run.noise.event_log.size()):
		var e: NoiseSystem.Event = s.run.noise.event_log[i]
		if e.type == NoiseTypes.Type.STEP_HEAVY or e.type == NoiseTypes.Type.STEP_WALK:
			steps.append(e)
	assert_eq(steps.size(), 4, "a step every 10 ticks")
	for e: NoiseSystem.Event in steps:
		assert_eq(e.type, NoiseTypes.Type.STEP_HEAVY)
		assert_almost_eq(e.level_np, 12.0, 1e-6, "12 np")
	for i: int in range(1, steps.size()):
		assert_eq(steps[i].tick - steps[i - 1].tick, 10)
	assert_almost_eq(_walk(s, ann, InputRecord.Gait.RUN, 40), speed * 2.0, 0.08, "never runs")
	assert_almost_eq(_walk(s, ann, InputRecord.Gait.CROUCH, 40), speed * 2.0, 0.08, "never crouches")
	assert_eq(s.run.registry.get_entity(bob.entity_id).position, s.run.registry.get_entity(ann.entity_id).position,
		"the body rides on the carrier")
	s.run.miner_state.make_hurt(ann.entity_id, "test")
	s.step(1)
	assert_almost_eq(_walk(s, ann, InputRecord.Gait.WALK, 40), speed * Tuning.f(&"movement.wound_gait_multiplier") * 2.0, 0.08,
		"Hurt: 1.2 tiles/s")


func test_hands_full() -> void:
	var parts: Array = _carrying(41)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var lamp: GauzeLamp = parts[3]
	var inv: InventorySystem = s.run.inventory
	for action: StringName in [&"flare", &"flint", &"kit", &"lever", &"phone", &"revolver", &"chalk", &"signal", &"pick_up"]:
		assert_true(inv.free_hand_blocked(ann.entity_id, action), "%s refused" % action)
	# Nothing from the belt: a kit's (or flare's, or the revolver's) use never runs.
	var used: Array[int] = [0]
	inv.use_handlers[ItemKinds.Kind.HEALING_KIT] = func(_run: RunState, _e: int, _slot: int) -> void: used[0] += 1
	assert_true(inv.give(s.run, ann.entity_id, inv.world.make(ItemKinds.Kind.HEALING_KIT)))
	ann.at(s.run.tick).select_slot(0).hold(InputRecord.HOLD_USE, 5)
	s.step(6)
	assert_eq(used[0], 0, "no kit while carrying")
	# The hooked lamp still shutters.
	ann.at(s.run.tick).lamp(true, LampRules.WICK_NORMAL)
	s.step(LampRules.step_ticks() + 2)
	assert_true(lamp.shutter_closed, "'Douse!' obeyed with the body on the shoulder")
	# Voice and callouts stay.
	var caps: Dictionary = s.run.miner_state.capabilities(ann.entity_id)
	assert_true(Variants.flag(caps["voice"]), "voice, and with it callouts")
	# The owner's client learns both hands are full: the job page replaces the callout wheel.
	var wire: Dictionary = InventoryWire.decode(inv.own_bytes(ann.entity_id))
	assert_true(Variants.flag(wire["two_handed"]))
	var r: InputRouter = F.router()
	r.know_inventory(wire)
	assert_true(r.carrying)
	assert_false(r.lamp_in_hand, "a hooked lamp is no lamp in hand: pad A never sets it down")
	r.sample(F.frame(1.0, {"callout": true}))
	assert_true(r.wheel.job_page, "the job page")
	# Others see a body over the shoulder.
	assert_eq(inv.held_bits(ann.entity_id) >> 8, ItemKinds.LOAD_BODY)


func test_set_down_is_instant() -> void:
	var parts: Array = _carrying(42)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	_walk(s, ann, InputRecord.Gait.WALK, 30)
	var ended: Array = []
	s.run.carry.carry_ended.connect(func(c: int, b: int, reason: StringName) -> void: ended.append([c, b, reason, s.run.tick]))
	var pressed_at: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		var view: Dictionary = sc.state.miner(ann)
		if pressed_at[0] < 0 and view["input"] != null:
			var record: InputRecord = view["input"]
			if (record.holds & InputRecord.HOLD_INTERACT) != 0:
				pressed_at[0] = sc.run.tick - 1
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 3)
	s.step(4)
	assert_eq(ended.size(), 1)
	var first: Array = ended[0]
	assert_eq(int(Variants.number(first[3])), pressed_at[0], "the same tick the press arrives")
	assert_eq(StringName(str(first[2])), FiremanCarry.SET_DOWN)
	var b: BodyState = s.run.falls.body_of(bob.entity_id)
	assert_true(b.on_floor)
	assert_eq(b.carried_by, 0)
	assert_eq(s.run.registry.get_entity(bob.entity_id).tile(), s.run.registry.get_entity(ann.entity_id).tile(), "on the carrier's tile")
	assert_false(W.belt(s, ann.entity_id).hooked, "the lamp back in the hand")
	assert_false(W.belt(s, ann.entity_id).two_handed)
	assert_almost_eq(_walk(s, ann, InputRecord.Gait.RUN, 20), Tuning.f(&"movement.run_speed"), 0.1, "free to run again")
	assert_eq(s.run.carry.diff_log.size(), 1, "logged for the diff log")


func test_no_crawl_moves_a_carried_body() -> void:
	var parts: Array = _carrying(43)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	# RSC-04's crawl window open, and Bob's client pushing hard the other way.
	s.run.miner_state.set_crawl_window(bob.entity_id, true)
	bob.at(s.run.tick).move(180.0, InputRecord.Gait.WALK, 40)
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 40)
	for _i: int in 42:
		s.step(1)
		assert_eq(s.run.registry.get_entity(bob.entity_id).position, s.run.registry.get_entity(ann.entity_id).position,
			"on the shoulder, tick %d" % s.run.tick)
