extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-03 (Gameplay §8.2, §11.3, §4.6, A.5): freeing a timber pin. A teammate with the crowbar on
## their belt levers it off in exactly 40 ticks; two miners both holding interact lift it in exactly
## 60, and either letting go cancels it with nothing done; alone, the victim struggles free after 400
## ticks of holding in all, pauses keeping the progress, with a struggle every 40 ticks while
## holding. Freed, the miner is Hurt for 60 s, and TrapEvents says so. Hired Hands are never offered
## the lever or the lift (they hold only as a lift's second miner, MOD-08).

const W = preload("res://tests/unit/hazards/collapse_world.gd")
const RW = preload("res://tests/unit/mnr/ring_world.gd")

var freed: Array[Array] = []


func before_all() -> void:
	assert_true(Tuning.load_server())


## Bob pinned at (8, 2) in the lit room, Ann a tile west of him facing him.
func _pinned(run_seed: int) -> Dictionary:
	var s: Scenario = make(W.cfg(run_seed))
	W.B.light(s)
	var ann: MinerHandle = s.add_miner("ann", Vector2i(7, 2))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(8, 2))
	ann.brain = null
	bob.brain = null
	ann.at(0).face(0.0)
	bob.at(0).face(180.0)
	s.step(4)
	assert_true(s.run.holds.catch(s.run, bob.entity_id, CaughtHold.Kind.TIMBER_PIN, 77))
	s.step(2)
	freed.clear()
	s.run.trap_events.freed.connect(func(miner: int, kind: CaughtHold.Kind) -> void: freed.append([miner, kind, s.run.tick]))
	return {"s": s, "ann": ann, "bob": bob}


## The tick an action of `verb` started for `miner`, stepping until it does (-1 if never).
func _started(s: Scenario, miner: int, verb: StringName, ticks: int) -> int:
	for _i: int in ticks:
		var a: TimedAction = s.run.inventory.actions.get(miner, null)
		if a != null and a.verb == verb:
			return a.started_tick
		s.step()
	return -1


func test_the_crowbar_in_forty_ticks() -> void:
	var w: Dictionary = _pinned(3301)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var bob: MinerHandle = w["bob"]
	RW.tap(s, ann)
	assert_false(Variants.array(ann.connection.ring.get("options", [])).has("lever_prop"), "no crowbar, no lever")
	assert_true(Variants.array(ann.connection.ring.get("options", [])).has("lift_prop"), "but the lift is offered")
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.CROWBAR)))
	s.step(3)
	var options: Array = Variants.array(ann.connection.ring.get("options", []))
	assert_true(options.has("lever_prop"), "with the crowbar on her belt: %s" % [options])
	ann.at(s.run.tick).press(ActionRecord.Kind.RING_CHOICE, options.find("lever_prop"))
	s.step(3)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 60)
	var started: int = _started(s, ann.entity_id, &"lever_prop", 20)
	assert_gt(started, 0, "the lever begins")
	s.step(50)
	assert_eq(freed.size(), 1, "freed")
	assert_eq(Variants.whole(freed[0][2]) - started, 40, "in exactly 40 ticks")
	assert_eq(Variants.whole(freed[0][1]), CaughtHold.Kind.TIMBER_PIN)
	_hurt_sixty_seconds(s, bob, Variants.whole(freed[0][2]))


func test_two_miners_in_sixty_ticks_and_either_letting_go_cancels() -> void:
	var w: Dictionary = _pinned(3302)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var bob: MinerHandle = w["bob"]
	var cat: MinerHandle = s.add_miner("cat", Vector2i(8, 1))
	cat.brain = null
	cat.at(s.run.tick).face(90.0)
	s.step(3)
	RW.tap(s, ann)
	var options: Array = Variants.array(ann.connection.ring.get("options", []))
	ann.at(s.run.tick).press(ActionRecord.Kind.RING_CHOICE, options.find("lift_prop"))
	s.step(3)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 20)
	s.step(24)
	assert_true(s.run.holds.caught.has(bob.entity_id), "one miner alone cannot lift it")
	assert_false(s.run.inventory.actions.has(ann.entity_id), "nothing starts without the second")
	# Cat holds beside him; Ann's press then starts the lift, and Cat letting go cancels it.
	cat.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(6)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 80)
	var started: int = _started(s, ann.entity_id, &"lift_prop", 20)
	assert_gt(started, 0, "two miners: the lift begins")
	s.step(40)
	assert_true(s.run.holds.caught.has(bob.entity_id), "Cat let go: cancelled, nothing done")
	assert_false(s.run.inventory.actions.has(ann.entity_id))
	assert_eq(freed.size(), 0)
	# Both hold to the end (Ann's first hold over, so her press is fresh): freed in exactly 60 ticks.
	s.step(50)
	cat.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 100)
	s.step(6)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 90)
	started = _started(s, ann.entity_id, &"lift_prop", 20)
	assert_gt(started, 0)
	s.step(70)
	assert_eq(freed.size(), 1, "freed")
	assert_eq(Variants.whole(freed[0][2]) - started, 60, "in exactly 60 ticks")
	_hurt_sixty_seconds(s, bob, Variants.whole(freed[0][2]))


func test_alone_a_struggle_of_four_hundred_ticks() -> void:
	var w: Dictionary = _pinned(3303)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var bob: MinerHandle = w["bob"]
	s.run.movement.place(s.run, ann.entity_id, Vector2(3.5, 2.5))
	s.step(2)
	var before: int = W.events_of(s, NoiseTypes.Type.STRUGGLE).size()
	assert_ne(int(Variants.number(OwnStatus.of(s.run, bob.entity_id)["flags"])) & StatusWire.TRAP_STRUGGLE, 0, "his status says he may struggle")
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 200)
	s.step(210)
	var progress: int = int(Variants.number(s.run.timber_pins.struggle.get(bob.entity_id, 0)))
	assert_between(progress, 195, 200, "200 ticks held")
	s.step(60)
	assert_eq(int(Variants.number(s.run.timber_pins.struggle.get(bob.entity_id, 0))), progress, "a pause keeps the progress")
	assert_true(s.run.holds.caught.has(bob.entity_id))
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 260)
	s.step(270)
	assert_eq(freed.size(), 1, "struggled free")
	assert_false(s.run.holds.caught.has(bob.entity_id))
	assert_eq(int(Variants.number(OwnStatus.of(s.run, bob.entity_id)["flags"])) & StatusWire.TRAP_STRUGGLE, 0, "free: no more")
	var struggles: Array[NoiseSystem.Event] = W.events_of(s, NoiseTypes.Type.STRUGGLE)
	assert_eq(struggles.size() - before, 10, "a struggle every 40 ticks of the 400")
	assert_eq(struggles[struggles.size() - 1].level_np, Tuning.f(&"noise.struggle_np"))
	_hurt_sixty_seconds(s, bob, Variants.whole(freed[0][2]))


func test_hands_are_never_offered_the_lever_or_the_lift() -> void:
	var w: Dictionary = _pinned(3304)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var bob: MinerHandle = w["bob"]
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.CROWBAR)))
	var offered: Array[String] = s.run.ring.registry.offered(s.run, ann.entity_id, bob.entity_id)
	assert_true(offered.has("lever_prop") and offered.has("lift_prop"))
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == ann.entity_id
	offered = s.run.ring.registry.offered(s.run, ann.entity_id, bob.entity_id)
	assert_false(offered.has("lever_prop"), "a Hand never uses a tool")
	assert_false(offered.has("lift_prop"), "nor starts a lift")


func _hurt_sixty_seconds(s: Scenario, h: MinerHandle, at_tick: int) -> void:
	s.step(1)
	var m: MinerStateSystem.Miner = s.run.miner_state.miner(h.entity_id)
	assert_eq(s.run.miner_state.life(h.entity_id), MinerTransitions.Life.UPRIGHT, "out of the pin")
	assert_between(m.overlays.hurt_until - at_tick, 1199, 1201, "Hurt for 60 s")
