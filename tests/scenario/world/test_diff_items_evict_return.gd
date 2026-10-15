extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-13: items left in a cell are recorded there the tick they land; the cell evicted, they are
## gone from the world but kept in its log; committed again, each is back where it lay with the
## same uid and every state. An item taken leaves a taken record; set down in another cell it is
## recorded there, so it is in exactly one place.

const W = preload("res://tests/scenario/world/diff_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_items_leave_with_their_cell_and_come_back() -> void:
	var s: Scenario = make({"seed": 1301, "fixture": W.road()})
	W.miner(s, "ann", Vector2i(3, 1))
	s.step(2)
	var flask: int = W.put(s, ItemKinds.Kind.OIL_FLASK, Vector2i(50, 1), {"fill": 0.4})
	var fuses: int = W.put(s, ItemKinds.Kind.FUSE, Vector2i(52, 1), {}, 3)
	var stay: int = W.put(s, ItemKinds.Kind.SPANNER, Vector2i(25, 1))
	var flask_uid: int = s.run.inventory.world.items[flask].uid
	var at_put: int = s.run.tick
	var rec: Dictionary = s.run.diff_log.payload_of(W.FAR, DiffLog.Kind.ITEM, "u%d" % flask_uid)
	assert_eq(str(rec.get("where", "")), "floor", "recorded in its cell")
	assert_eq(s.run.diff_log.tick_of(W.FAR, DiffLog.Kind.ITEM, "u%d" % flask_uid), at_put, "the same tick")
	var before: Dictionary = W.floor_items(s)
	s.step(5)
	W.evict(s, W.FAR)
	assert_false(s.run.mine.native.is_loaded(W.FAR), "the cell is gone")
	assert_false(s.run.registry.has(flask), "its items with it")
	assert_false(s.run.registry.has(fuses))
	assert_true(s.run.registry.has(stay), "items elsewhere stay")
	assert_eq(s.run.diff_log.store.records(W.FAR).size(), 2, "both kept in its log")
	s.step(20)
	W.restore(s, W.FAR)
	assert_eq(W.floor_items(s), before, "every item back where it lay, same uid and state")
	assert_ne(W.entity_of(s, flask_uid), 0)


func test_taken_and_set_down_elsewhere_is_in_one_place() -> void:
	var s: Scenario = make({"seed": 1302, "fixture": W.road()})
	var ann: MinerHandle = W.miner(s, "ann", Vector2i(3, 1))
	s.step(2)
	var e: int = W.put(s, ItemKinds.Kind.HAMMER, Vector2i(50, 1))
	var it: Item = s.run.inventory.world.items[e]
	var key: String = "u%d" % it.uid
	var taken: Item = s.run.inventory.world.lift(s.run, e, &"take", ann.entity_id)
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	h.slots[0] = taken
	assert_eq(str(s.run.diff_log.payload_of(W.FAR, DiffLog.Kind.ITEM, key).get("where", "")), DiffLog.TAKEN,
		"the cell's record says taken")
	h.slots[0] = null
	s.run.inventory.world.put(s.run, taken, Vector2(10.5, 1.5), &"set_down", ann.entity_id)
	var home: Vector2i = Vector2i(0, 0)
	assert_eq(str(s.run.diff_log.payload_of(home, DiffLog.Kind.ITEM, key).get("where", "")), "floor", "recorded where it lies now")
	W.evict(s, W.FAR)
	W.restore(s, W.FAR)
	var copies: int = 0
	for raw: Variant in s.run.inventory.world.items.values():
		var live: Item = raw
		if live.uid == taken.uid:
			copies += 1
	assert_eq(copies, 1, "never duplicated by its old cell's replay")
	s.run.diff_log.compact(s.run)
	assert_true(s.run.diff_log.payload_of(W.FAR, DiffLog.Kind.ITEM, key).is_empty(),
		"compaction drops a runtime item's taken record: generation never makes it")


func test_a_gate_moved_item_follows_its_record() -> void:
	var s: Scenario = make({"seed": 1303, "fixture": W.road()})
	W.miner(s, "ann", Vector2i(3, 1))
	s.step(2)
	var e: int = W.put(s, ItemKinds.Kind.CROWBAR, Vector2i(39, 1))
	var uid: int = s.run.inventory.world.items[e].uid
	s.run.registry.move(e, Vector2(40.5, 1.5))
	s.run.inventory.world.moved(s.run, e)
	assert_eq(str(s.run.diff_log.payload_of(Vector2i(1, 0), DiffLog.Kind.ITEM, "u%d" % uid).get("where", "")), DiffLog.TAKEN)
	assert_eq(str(s.run.diff_log.payload_of(W.FAR, DiffLog.Kind.ITEM, "u%d" % uid).get("where", "")), "floor")
