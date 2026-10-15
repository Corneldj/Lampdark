extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-13: an air door worked open is a barrier record in its cell the same tick; a smeared tile is
## blood in its cell's packed set the same tick, a wiped one gone; both come back when the cell is
## committed again, from the log alone. Chalk (MNR-10) replays between items and fixtures, and a
## fall's erased chalk leaves the log.

const W = preload("res://tests/scenario/world/diff_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_door_worked_open_is_kept() -> void:
	var s: Scenario = make({"seed": 1321, "fixture": W.road()})
	var ann: MinerHandle = W.miner(s, "ann", W.DOOR - Vector2i(1, 0))
	s.step(2)
	assert_false(W.door(s).open)
	W.work_door(s, ann)
	var flipped_at: int = int(Variants.number(s.run.air_doors.diff_log[0]["tick"]))
	assert_true(W.door(s).open, "worked open")
	var key: String = AirDoorSystem.DIFF_PREFIX + W.door(s).key()
	assert_true(Variants.flag(s.run.diff_log.payload_of(W.FAR, DiffLog.Kind.BARRIER, key).get("open", false)), "recorded open")
	assert_eq(s.run.diff_log.tick_of(W.FAR, DiffLog.Kind.BARRIER, key), flipped_at, "the tick it opened")
	s.run.movement.place(s.run, ann.entity_id, Vector2(3.5, 1.5))
	s.step(2)
	W.evict(s, W.FAR)
	s.run.air_doors.states.clear()
	W.restore(s, W.FAR)
	assert_true(W.door(s).open, "open again, from the log")
	assert_true(s.mine.native.is_walkable(W.DOOR))


func test_blood_is_kept_packed_and_wiped() -> void:
	var s: Scenario = make({"seed": 1322, "fixture": W.road()})
	W.miner(s, "ann", Vector2i(3, 1))
	s.step(2)
	for x: int in range(48, 56):
		s.run.vision.mark_trail(Vector2i(x, 1), 4)
	s.run.vision.mark_trail(Vector2i(50, 1), 6)
	assert_eq(s.run.diff_log.store.blood_at(Vector2i(50, 1)), 6, "the latest smear wins, at once")
	assert_eq(s.run.diff_log.store.blood_count(), 8)
	s.run.vision.erase_trail(Vector2i(55, 1))
	assert_eq(s.run.diff_log.store.blood_at(Vector2i(55, 1)), -1, "a wiped tile is gone")
	W.evict(s, W.FAR)
	s.run.vision.trails.clear()
	W.restore(s, W.FAR)
	assert_eq(s.run.vision.trails.size(), 7, "every smear back, from the log")
	assert_eq(int(Variants.number(s.run.vision.trails[Vector2i(50, 1)])), 6)
	assert_eq(int(Variants.number(s.run.vision.trails[Vector2i(48, 1)])), 4)
	assert_false(s.run.vision.trails.has(Vector2i(55, 1)))
	assert_eq(s.run.diff_log.store.blood_count(), 7, "replay records nothing new")
	s.run.vision.trails.clear()
	s.run.diff_log.replay(s.run, W.FAR)
	assert_eq(s.run.vision.trails.size(), 7, "a resume, with nothing in the vision's memory, gets them all")


func test_chalk_replays_in_order_and_is_erased_with_its_record() -> void:
	var s: Scenario = make({"seed": 1323, "fixture": W.road()})
	W.miner(s, "ann", Vector2i(3, 1))
	s.step(2)
	var order: Array[String] = []
	s.run.diff_log.register(DiffLog.Kind.FIXTURE, func(_r: RunState, _c: Vector2i, key: String, _p: Dictionary, _t: int) -> void:
		order.append("fixture " + key))
	s.run.diff_log.record(W.FAR, DiffLog.Kind.FIXTURE, "phone:1", {"fitted": true})
	# MNR-10's chalk, the real owner.
	var store: ChalkStore = s.run.chalk.store
	store.put(s.run, Vector2i(50, 1), ChalkMarks.Surface.FLOOR, ChalkMarks.glyph(ChalkMarks.Kind.DIGIT_3), 1)
	store.put(s.run, Vector2i(51, 1), ChalkMarks.Surface.NORTH, ChalkMarks.glyph(ChalkMarks.Kind.CROSS), 1)
	W.put(s, ItemKinds.Kind.SPANNER, Vector2i(50, 1))
	s.run.vision.mark_trail(Vector2i(52, 1), 0)
	var kinds: Array[int] = []
	for r: Dictionary in s.run.diff_log.records(W.FAR):
		kinds.append(int(Variants.number(r["kind"])))
	assert_eq(kinds, [DiffLog.Kind.ITEM, DiffLog.Kind.CHALK, DiffLog.Kind.CHALK, DiffLog.Kind.BLOOD, DiffLog.Kind.FIXTURE] as Array[int],
		"replay order: items, chalk and blood, fixtures")
	W.evict(s, W.FAR)
	store.marks.clear()
	W.restore(s, W.FAR)
	assert_eq(ChalkMarks.kind_of(store.glyph_at(Vector2i(50, 1), ChalkMarks.Surface.FLOOR)), ChalkMarks.Kind.DIGIT_3, "chalk back")
	assert_eq(ChalkMarks.kind_of(store.glyph_at(Vector2i(51, 1), ChalkMarks.Surface.NORTH)), ChalkMarks.Kind.CROSS)
	assert_eq(order, ["fixture phone:1"] as Array[String], "fixtures last")
	store.erase_chalk(s.run, [Vector2i(51, 0)] as Array[Vector2i])
	assert_true(s.run.diff_log.payload_of(W.FAR, DiffLog.Kind.CHALK, "51,1:n").is_empty(), "a fall's erased chalk leaves the log")
	assert_false(s.run.diff_log.payload_of(W.FAR, DiffLog.Kind.CHALK, "50,1:f").is_empty())
