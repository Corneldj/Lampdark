extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-13 with NET-09's resume: one run's log, serialised and restored into a fresh run of the same
## seed, replays to the same items (uid, kind, state, place), the same door and the same blood;
## the restored log serialises back byte for byte. Under NET-08's audit, nothing of the log reaches
## a client: a replayed item no miner sees is never sent.

const W = preload("res://tests/scenario/world/diff_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	WorldCoords.ring_override = -1


## A run that changed the far cell: a lit lamp, a flask, a candle burning, the door open, a trail.
func _played(run_seed: int) -> Scenario:
	var s: Scenario = make({"seed": run_seed, "fixture": W.road()})
	var ann: MinerHandle = W.miner(s, "ann", W.DOOR - Vector2i(1, 0))
	s.step(2)
	W.work_door(s, ann)
	s.run.movement.place(s.run, ann.entity_id, Vector2(3.5, 1.5))
	s.run.lamps.create(s.run, 0.7, 2, true, LampRules.WICK_NORMAL, Vector2(50.5, 1.5))
	W.put(s, ItemKinds.Kind.OIL_FLASK, Vector2i(52, 1), {"fill": 0.25})
	W.put(s, ItemKinds.Kind.CANDLE, Vector2i(54, 1), {"lit": true, "burn_ticks": 3000})
	for x: int in range(47, 57):
		s.run.vision.mark_trail(Vector2i(x, 1), 4)
	s.step(30)
	return s


func test_a_restored_log_replays_the_same_mine() -> void:
	WorldCoords.ring_override = 1
	var a: Scenario = _played(1341)
	var t0: int = a.run.tick
	W.evict(a, W.FAR)
	var saved: PackedByteArray = a.run.diff_log.serialise(a.run)
	var copy: LbDiffStore = LbDiffStore.new()
	assert_true(copy.deserialise(saved))
	assert_eq(copy.serialise(), saved, "the saved log round-trips byte for byte")
	W.restore(a, W.FAR)
	var want: Dictionary = W.floor_items(a)
	var b: Scenario = make({"seed": 1341, "fixture": W.road()})
	W.miner(b, "ann", Vector2i(3, 1))
	b.step(2)
	while b.run.tick < t0:
		b.step(1)
	W.evict(b, W.FAR)
	assert_true(b.run.diff_log.deserialise(saved), "the save restores")
	W.restore(b, W.FAR)
	assert_eq(b.run.tick, a.run.tick, "both at the same tick")
	assert_eq(W.floor_items(b), want, "the same items, uid, state and place")
	assert_true(W.door(b).open, "the same door")
	assert_eq(b.run.vision.trails, a.run.vision.trails, "the same blood")


func test_a_replayed_item_nobody_sees_is_never_sent() -> void:
	var s: Scenario = make({"seed": 1342, "fixture": W.road()})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ann: MinerHandle = W.miner(s, "ann", Vector2i(3, 1))
	ann.at(s.run.tick).face(180.0)
	s.step(2)
	var flask: int = W.put(s, ItemKinds.Kind.OIL_FLASK, Vector2i(50, 1))
	var uid: int = s.run.inventory.world.items[flask].uid
	s.step(5)
	W.evict(s, W.FAR)
	W.restore(s, W.FAR)
	s.step(20)
	assert_ne(W.entity_of(s, uid), 0, "back in the world, behind her")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p(str(v))
	assert_eq(audit.violation_count, 0, "nothing of the log in any stream")
