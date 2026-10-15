extends "res://tests/scenario/kit/scenario_test.gd"
## NET-09: the server killed 20 s after a fall resumes from the snapshot before it with the fall
## standing, as recorded: the miner unconscious where they fell, the lamp where the cause left it
## (a drag: snuffed at the grab point), the belt on the body. A fall already inside the snapshot is
## not applied twice; a death journaled after the snapshot stands, through every later resume.

const S = preload("res://tests/scenario/net/save_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_kill_after_fall() -> void:
	S.clear(901)
	var s: Scenario = make(S.cfg(901))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	var bob: MinerHandle = S.miner(s, "bob", Vector2i(8, 3))
	var lamp: GauzeLamp = S.L.lit_in_hand(s, ann)
	var flask: Item = s.run.inventory.world.make(ItemKinds.Kind.OIL_FLASK, 1, {"fill": 1.0})
	s.run.inventory.hands_of(ann.entity_id).slots[0] = flask
	assert_true(S.until_saved(s, 1), "the first snapshot")
	var snap_tick: int = int(Variants.number(s.run.saves.written[0]["tick"]))
	s.step(100)
	var grab: Vector2i = Vector2i(5, 4)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.DRAG, {"grab_point": grab}))
	s.step(2)
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	var fell_tile: Vector2i = s.run.registry.get_entity(ann.entity_id).tile()
	var want_lamp: Dictionary = S.lamp_place(s, lamp.uid)
	var want_belt: Array = S.belt(s, ann.entity_id)
	var want_tile: Vector2i = want_lamp["tile"]
	assert_eq(want_tile, grab, "the drag left the lamp at the grab point")
	assert_false(Variants.flag(want_lamp["lit"]), "snuffed")
	assert_eq(s.run.saves.journal.entries.size(), 1, "the fall journaled the tick it happened")
	s.step(400)  # 20 s later: no snapshot since
	assert_eq(s.run.saves.written.size(), 1, "still only the snapshot before the fall")
	var path: String = S.snapshot_path(s)
	S.kill(s)

	var resumed: Array = S.resume(make, 901, path)
	var b: Scenario = resumed[0]
	var summary: Dictionary = resumed[1]
	assert_eq(b.run.tick, snap_tick, "resumed at the snapshot")
	assert_eq(int(Variants.number(summary["journal_applied"])), 1, "the fall after it applied")
	assert_eq(b.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UNCONSCIOUS, "unconscious")
	assert_eq(b.run.registry.get_entity(ann.entity_id).tile(), fell_tile, "where she fell")
	assert_not_null(b.run.falls.body_of(ann.entity_id), "a body")
	assert_eq(S.belt(b, ann.entity_id), want_belt, "the belt on the body")
	var got_lamp: Dictionary = S.lamp_place(b, lamp.uid)
	var got_where: String = got_lamp.get("where", "")
	var got_tile: Vector2i = got_lamp.get("tile", Vector2i(-1, -1))
	assert_eq(got_where, "floor")
	assert_eq(got_tile, grab, "the lamp where the cause left it")
	assert_false(Variants.flag(got_lamp.get("lit", true)), "snuffed")
	assert_null(b.run.inventory.hands_of(ann.entity_id).lamp_hand, "not in her hand")
	assert_eq(b.run.miner_state.life(bob.entity_id), MinerTransitions.Life.UPRIGHT, "Bob as he was")
	assert_true(b.run.drops.hand_driven.has(bob.entity_id), "a Hand holds him until he is back")
	b.step(5)
	var adopted: GauzeLamp = b.run.lamps.lamps.get(lamp.uid, null)
	assert_not_null(adopted, "the lamp system has the lamp again")
	if adopted != null:
		assert_false(adopted.burning(), "out")
	var bob2: MinerHandle = b.rejoin("bob")
	b.step(3)
	assert_eq(bob2.entity_id, bob.entity_id, "his miner")
	assert_false(b.run.drops.hand_driven.has(bob.entity_id), "handed back")
	assert_eq(b.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UNCONSCIOUS, "still down")


func test_a_fall_inside_the_snapshot_is_not_applied_twice() -> void:
	S.clear(902)
	var s: Scenario = make(S.cfg(902))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	S.miner(s, "bob", Vector2i(8, 3))
	S.L.lit_in_hand(s, ann)
	s.step(20)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(2)
	var fall_id: int = s.run.falls.body_of(ann.entity_id).fall_id
	assert_true(S.until_saved(s, 1))
	var path: String = S.snapshot_path(s)
	S.kill(s)
	var resumed: Array = S.resume(make, 902, path)
	var b: Scenario = resumed[0]
	assert_eq(int(Variants.number(resumed[1]["journal_applied"])), 0, "its entry is before the snapshot")
	assert_eq(b.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	assert_eq(b.run.falls.body_of(ann.entity_id).fall_id, fall_id, "the same fall, once")
	assert_eq(b.run.falls.journal.size(), s.run.falls.journal.size(), "no second record")


func test_a_death_after_the_snapshot_stands_through_every_resume() -> void:
	S.clear(903)
	var s: Scenario = make(S.cfg(903))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	S.miner(s, "bob", Vector2i(8, 3))
	assert_true(S.until_saved(s, 1))
	s.step(40)
	s.run.miner_state.kill(ann.entity_id, "kit")
	s.step(2)
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.DEAD)
	var path: String = S.snapshot_path(s)
	S.kill(s)
	var first: Array = S.resume(make, 903, path)
	var b: Scenario = first[0]
	assert_eq(int(Variants.number(first[1]["journal_applied"])), 1)
	assert_eq(b.run.miner_state.life(ann.entity_id), MinerTransitions.Life.DEAD, "the death stands")
	assert_true(b.run.falls.body_of(ann.entity_id).dead)
	# The resumed run snapshots again (the death inside it now), and is killed again.
	assert_true(S.until_saved(b, 1, 700), "the resumed run's next snapshot")
	assert_eq(int(Variants.number(b.run.saves.written[0]["seq"])), 2, "the chain goes on")
	S.kill(b)
	var second: Array = S.resume(make, 903, path)
	var c: Scenario = second[0]
	assert_eq(int(Variants.number(second[1]["journal_applied"])), 0, "inside the snapshot now: not applied again")
	assert_eq(c.run.miner_state.life(ann.entity_id), MinerTransitions.Life.DEAD, "still dead")
