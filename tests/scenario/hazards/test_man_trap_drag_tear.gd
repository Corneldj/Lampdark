extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-01 (Gameplay §11.3, §8.2): a Stythe's drag tears a Caught miner out of the jaws (RSC-03's
## TORN_OUT): the trap wound stays with them, the trap stays sprung, and TrapEvents says nobody was
## freed. The jaws catch nobody after.

const T = preload("res://tests/unit/hazards/trap_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_drag_tears_the_victim_out_with_the_wound() -> void:
	var s: Scenario = make(T.cfg(4601))
	var bob: MinerHandle = T.miner_at(s, "bob", Vector2(6.5, 2.5))
	s.step(2)
	var trap: int = T.catch(s, bob)
	var freed: Array[int] = []
	var ended: Array[CaughtHold.Outcome] = []
	s.run.trap_events.freed.connect(func(miner: int, _kind: CaughtHold.Kind) -> void: freed.append(miner))
	s.run.holds.caught_ended.connect(func(_trap: int, outcome: CaughtHold.Outcome, _victim: int) -> void: ended.append(outcome))
	var stythe: int = s.place_stand_in(WorldIds.EntityKind.STYTHE, T.TRAP + Vector2i(1, 0))
	assert_gt(stythe, 0)
	assert_gt(s.run.holds.grab(s.run, bob.entity_id, GrabHold.Kind.STYTHE_DRAG, stythe, 400), 0, "the drag")
	s.step(2)
	assert_eq(ended, [CaughtHold.Outcome.TORN_OUT] as Array[CaughtHold.Outcome], "torn out of the jaws")
	assert_null(s.run.holds.caught_in(bob.entity_id))
	assert_true(s.run.miner_state.miner(bob.entity_id).overlays.marks.has(MinerOverlays.TRAP_WOUND), "the wound with him")
	assert_true(freed.is_empty(), "torn, not freed")
	assert_false(s.run.man_traps.is_set(trap), "the jaws stay sprung")
	s.run.holds.end_grab(s.run, s.run.holds.grab_of(bob.entity_id).id, GrabHold.Outcome.BROKEN)
	s.step(2)
	s.run.movement.place(s.run, bob.entity_id, Vector2(T.TRAP) + Vector2(0.5, 0.5))
	s.step(3)
	assert_null(s.run.holds.caught_in(bob.entity_id), "spent: they catch nobody")
