extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-01 (Gameplay §8.2, §11.3, §4.6, §8.3): freeing a man-trap. A teammate's "Free" takes both hands
## (the lamp hooked while it runs) and exactly 60 ticks, or 40 with the wire cutters on the belt;
## letting go early keeps nothing, and one freer works at a time. A POINTed Hired Hand frees in 60;
## Hands are never offered the ring's Free. Freed, every gait is x0.8 (never x0.64 with Hurt on top),
## TrapEvents says freed once, and the jaws stay sprung.

const T = preload("res://tests/unit/hazards/trap_world.gd")

var freed: Array[Array] = []


func before_all() -> void:
	assert_true(Tuning.load_server())


## Bob caught at the trap, Ann a tile west of him facing him, the road lit.
func _caught(run_seed: int) -> Dictionary:
	var s: Scenario = make(T.cfg(run_seed))
	T.light(s)
	var ann: MinerHandle = T.miner_at(s, "ann", Vector2(T.TRAP) + Vector2(-0.5, 0.5))
	var bob: MinerHandle = T.miner_at(s, "bob", Vector2(T.TRAP) + Vector2(2.5, 0.5))
	ann.at(0).face(0.0)
	s.step(3)
	var trap: int = T.catch(s, bob)
	bob.at(s.run.tick).face(180.0)
	s.step(2)
	freed.clear()
	s.run.trap_events.freed.connect(func(miner: int, kind: CaughtHold.Kind) -> void: freed.append([miner, kind, s.run.tick]))
	return {"s": s, "ann": ann, "bob": bob, "trap": trap}


func _free_from_ring(s: Scenario, freer: MinerHandle, hold_ticks: int) -> int:
	T.RW.tap(s, freer)
	var options: Array = Variants.array(freer.connection.ring.get("options", []))
	assert_true(options.has(ManTraps.FREE_OPTION), "the ring offers Free: %s" % [options])
	freer.at(s.run.tick).press(ActionRecord.Kind.RING_CHOICE, options.find(ManTraps.FREE_OPTION))
	s.step(3)
	freer.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, hold_ticks)
	return T.started(s, freer.entity_id, ManTraps.FREE_VERB, 20)


func test_a_teammate_frees_in_sixty_ticks_with_both_hands() -> void:
	var w: Dictionary = _caught(4201)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var bob: MinerHandle = w["bob"]
	T.L.lit_in_hand(s, ann)
	var started: int = _free_from_ring(s, ann, 80)
	assert_gt(started, 0, "the free begins")
	s.step(2)
	var hands: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	assert_true(hands.two_handed, "both hands on the jaws")
	assert_true(hands.hooked, "her lamp hooked")
	s.step(70)
	assert_eq(freed.size(), 1, "freed")
	var f: Array = freed[0]
	assert_eq(Variants.whole(f[2]) - started, 60, "in exactly 60 ticks")
	assert_eq(Variants.whole(f[1]), CaughtHold.Kind.MAN_TRAP)
	assert_false(hands.two_handed, "her hands free again")
	assert_false(hands.hooked, "the lamp back in her hand")
	_wounded(s, bob, Variants.whole(w["trap"]))


func test_the_wire_cutters_free_in_forty_ticks() -> void:
	var w: Dictionary = _caught(4202)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.WIRE_CUTTERS)))
	s.step(2)
	var started: int = _free_from_ring(s, ann, 60)
	assert_gt(started, 0)
	s.step(50)
	assert_eq(freed.size(), 1, "freed")
	var f: Array = freed[0]
	assert_eq(Variants.whole(f[2]) - started, 40, "in exactly 40 ticks with the cutters")


func test_letting_go_keeps_nothing_and_one_freer_at_a_time() -> void:
	var w: Dictionary = _caught(4203)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var bob: MinerHandle = w["bob"]
	var cat: MinerHandle = T.miner_at(s, "cat", Vector2(T.TRAP) + Vector2(0.5, -0.5))
	s.step(2)
	var started: int = _free_from_ring(s, ann, 30)
	assert_gt(started, 0)
	s.step(5)
	assert_false(s.run.man_traps.may_free(s.run, cat.entity_id, bob.entity_id), "one freer at a time: Cat is not offered it")
	assert_false(s.run.ring.registry.offered(s.run, cat.entity_id, bob.entity_id).has(ManTraps.FREE_OPTION))
	s.step(40)
	assert_eq(freed.size(), 0, "let go at 30: still held")
	assert_false(s.run.inventory.actions.has(ann.entity_id), "the free gone")
	assert_true(s.run.man_traps.may_free(s.run, cat.entity_id, bob.entity_id), "now Cat may")
	var again: int = _free_from_ring(s, ann, 80)
	assert_gt(again, 0)
	s.step(70)
	assert_eq(freed.size(), 1)
	var f: Array = freed[0]
	assert_eq(Variants.whole(f[2]) - again, 60, "the full 60 again: nothing kept")


func test_a_pointed_hand_frees_in_sixty_and_hands_get_no_ring_free() -> void:
	var w: Dictionary = _caught(4204)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var bob: MinerHandle = w["bob"]
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == ann.entity_id
	assert_false(s.run.ring.registry.offered(s.run, ann.entity_id, bob.entity_id).has(ManTraps.FREE_OPTION), "a Hand frees only when POINTed")
	var job: Dictionary = HandJobs.pick(s.run, ann.entity_id, T.TRAP)
	assert_eq(Variants.whole(job.get("kind", 0)), HandJobs.Kind.FREE, "POINTed at him, the Hand's job is to free him")
	var worked: int = 0
	while s.run.holds.caught.has(bob.entity_id) and worked < 100:
		HandJobs.act(s.run, ann.entity_id, job, worked)
		worked += 1
	assert_eq(worked, 61, "freed on its 60th tick of work")
	assert_eq(freed.size(), 1)


func test_freed_the_wound_slows_every_gait_once() -> void:
	var w: Dictionary = _caught(4205)
	var s: Scenario = w["s"]
	var bob: MinerHandle = w["bob"]
	s.run.man_traps.free_victim(s.run, bob.entity_id, "test", 0)
	s.step(2)
	_wounded(s, bob, Variants.whole(w["trap"]))
	s.run.miner_state.make_hurt(bob.entity_id, "test")
	s.step(2)
	var slot: int = ManTraps._slot_of(s.run, bob.entity_id)
	assert_almost_eq(s.run.movement.modifiers(slot).factor(), 0.8, 1e-9, "Hurt as well: still x0.8, never x0.64")


func _wounded(s: Scenario, h: MinerHandle, trap: int) -> void:
	s.step(1)
	assert_eq(s.run.miner_state.life(h.entity_id), MinerTransitions.Life.UPRIGHT, "out of the jaws")
	assert_true(s.run.miner_state.miner(h.entity_id).overlays.marks.has(MinerOverlays.TRAP_WOUND), "with the trap wound")
	var slot: int = ManTraps._slot_of(s.run, h.entity_id)
	assert_almost_eq(s.run.movement.modifiers(slot).factor(), 0.8, 1e-9, "every gait x0.8")
	assert_false(s.run.man_traps.is_set(trap), "the jaws stay sprung")
	assert_eq(freed.size(), 1, "freed once")
