extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-01 (Gameplay §8.2, §11.3, §10.1): the trigger. A miner walking onto a set trap gives, in the
## one tick, one snap at the trap (noise.mantrap_snap_np), one involuntary cry in the victim's own
## voice (noise.trapped_cry_np) and RSC-03's catch, the Draught rising by 15 once; the jaws stay
## sprung, and nobody steps into them twice. A Hired Hand springs one; a creature, Bess, a body
## (being dragged, carried or lying) and feeling never do; a carrier does, setting the body down at
## once.

const T = preload("res://tests/unit/hazards/trap_world.gd")
const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_snap_the_cry_and_the_catch_in_one_tick() -> void:
	var s: Scenario = make(T.cfg(4101, {"director": true}))
	var bob: MinerHandle = T.miner_at(s, "bob", Vector2(6.5, 2.5))
	var trap: int = s.run.man_traps.place(s.run, T.TRAP)
	s.step(3)
	D.stand_in(s, {bob.entity_id: 0.6})
	s.step(2)
	var values: Array[float] = []
	var caught: Array[Array] = []
	s.run.holds.caught_begun.connect(func(trap_id: int, kind: CaughtHold.Kind, victim: int) -> void: caught.append([trap_id, kind, victim, s.run.tick]))
	var snaps_before: int = T.events_of(s, NoiseTypes.Type.MANTRAP_SNAP).size()
	var cries_before: int = T.events_of(s, NoiseTypes.Type.TRAPPED_CRY).size()
	# He walks east onto it.
	bob.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 40)
	for _i: int in 60:
		values.append(D.value(s, bob.entity_id))
		s.step()
		if not caught.is_empty():
			break
	values.append(D.value(s, bob.entity_id))
	assert_eq(caught.size(), 1, "caught once")
	var first: Array = caught[0]
	assert_eq(Variants.whole(first[0]), trap, "by this trap")
	assert_eq(Variants.whole(first[1]), CaughtHold.Kind.MAN_TRAP)
	assert_eq(Variants.whole(first[2]), bob.entity_id)
	var at: int = Variants.whole(first[3])
	var snaps: Array[NoiseSystem.Event] = T.events_of(s, NoiseTypes.Type.MANTRAP_SNAP)
	var cries: Array[NoiseSystem.Event] = T.events_of(s, NoiseTypes.Type.TRAPPED_CRY)
	assert_eq(snaps.size() - snaps_before, 1, "one snap")
	assert_eq(cries.size() - cries_before, 1, "one cry")
	assert_eq(snaps[snaps.size() - 1].tick, at, "the snap in the catch's tick")
	assert_eq(cries[cries.size() - 1].tick, at, "and the cry")
	assert_eq(snaps[snaps.size() - 1].level_np, Tuning.f(&"noise.mantrap_snap_np"))
	assert_eq(snaps[snaps.size() - 1].origins, [T.TRAP] as Array[Vector2i], "at the trap")
	assert_eq(cries[cries.size() - 1].level_np, Tuning.f(&"noise.trapped_cry_np"))
	assert_eq(cries[cries.size() - 1].source_entity, bob.entity_id, "in his own voice")
	assert_eq(s.run.miner_state.life(bob.entity_id), MinerTransitions.Life.CAUGHT)
	assert_false(s.run.man_traps.is_set(trap), "the jaws sprung")
	var jump: float = values[values.size() - 1] - values[values.size() - 2]
	assert_almost_eq(jump, Tuning.f(&"director.gain_caught"), 0.5, "the Draught rises by 15 as the jaws close")
	var biggest: float = 0.0
	for _i: int in 40:
		var before: float = D.value(s, bob.entity_id)
		s.step()
		biggest = maxf(biggest, D.value(s, bob.entity_id) - before)
	assert_lt(biggest, 1.0, "and only once")
	assert_eq(caught.size(), 1, "one catch")
	assert_eq(T.events_of(s, NoiseTypes.Type.MANTRAP_SNAP).size() - snaps_before, 1, "no second snap")


func test_sprung_jaws_catch_nobody_else() -> void:
	var s: Scenario = make(T.cfg(4102))
	var bob: MinerHandle = T.miner_at(s, "bob", Vector2(6.5, 2.5))
	var cat: MinerHandle = T.miner_at(s, "cat", Vector2(14.5, 2.5))
	T.catch(s, bob)
	s.run.man_traps.free_victim(s.run, bob.entity_id, "test", 0)
	s.run.movement.place(s.run, bob.entity_id, Vector2(5.5, 1.5))
	s.step(2)
	s.run.movement.place(s.run, cat.entity_id, Vector2(T.TRAP) + Vector2(0.5, 0.5))
	s.step(3)
	assert_null(s.run.holds.caught_in(cat.entity_id), "spent: Cat steps on it freely")


func test_a_hired_hand_springs_one() -> void:
	var s: Scenario = make(T.cfg(4103))
	var hand: MinerHandle = T.miner_at(s, "hand", Vector2(6.5, 2.5))
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id
	T.catch(s, hand)
	assert_eq(s.run.holds.caught_in(hand.entity_id).kind, CaughtHold.Kind.MAN_TRAP, "Hired Hands are miners to the jaws")


func test_creatures_bess_bodies_and_feeling_never_spring_one() -> void:
	var s: Scenario = make(T.cfg(4104))
	T.light(s)
	var trap: int = s.run.man_traps.place(s.run, T.TRAP)
	var on_it: Vector2 = Vector2(T.TRAP) + Vector2(0.5, 0.5)
	for kind: WorldIds.EntityKind in [WorldIds.EntityKind.STYTHE, WorldIds.EntityKind.MOTH, WorldIds.EntityKind.BESS]:
		var e: int = s.run.registry.create(kind, on_it).id
		s.step(2)
		assert_true(s.run.man_traps.is_set(trap), "a %s on its tile springs nothing" % WorldIds.EntityKind.find_key(kind))
		s.run.registry.destroy(e)
	# A body lying on it, then dragged across it.
	var bob: MinerHandle = T.miner_at(s, "bob", Vector2(8.5, 2.5))
	s.step(1)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	s.run.movement.place(s.run, bob.entity_id, on_it)
	s.step(3)
	assert_true(s.run.man_traps.is_set(trap), "a body lying on it springs nothing")
	assert_gt(s.run.holds.grab(s.run, bob.entity_id, GrabHold.Kind.STYTHE_DRAG, 0, 400), 0)
	s.run.movement.place(s.run, bob.entity_id, on_it + Vector2(1.0, 0.0))
	s.step(2)
	s.run.movement.place(s.run, bob.entity_id, on_it)
	s.step(2)
	assert_true(s.run.man_traps.is_set(trap), "nor a body dragged over it")
	# Feeling it from beside it.
	var ann: MinerHandle = T.miner_at(s, "ann", on_it - Vector2(1.0, 0.0))
	ann.at(s.run.tick).face(0.0)
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(32)
	assert_true(s.run.man_traps.is_set(trap), "feeling it never springs it")
	assert_null(s.run.holds.caught_in(ann.entity_id))
	assert_eq(s.run.feel.caption_key(s.run, trap), "feel.iron_jaws", "felt, it names itself: '[iron jaws]'")


func test_a_carrier_springs_one_and_sets_the_body_down() -> void:
	var s: Scenario = make(T.cfg(4105))
	T.light(s)
	var ann: MinerHandle = T.miner_at(s, "ann", Vector2(6.5, 2.5))
	var bob: MinerHandle = T.miner_at(s, "bob", Vector2(7.5, 2.5))
	s.step(1)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(45)
	assert_true(s.run.carry.is_carrying(ann.entity_id), "Ann carries Bob")
	var trap: int = s.run.man_traps.place(s.run, T.TRAP)
	s.run.movement.place(s.run, ann.entity_id, Vector2(T.TRAP) + Vector2(0.5, 0.5))
	s.step(2)
	assert_eq(s.run.holds.caught_in(ann.entity_id).trap_id, trap, "the carrier is caught")
	assert_false(s.run.carry.is_carrying(ann.entity_id), "the body set down at once")
	assert_null(s.run.holds.caught_in(bob.entity_id), "the body itself never")
