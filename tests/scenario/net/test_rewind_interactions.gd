extends "res://tests/scenario/kit/scenario_test.gd"
## NET-06's rewound range checks end to end: a douse on a teammate walking at 3.0 tiles/s
## succeeds whenever the presser's view (the frame at its stamp) had them in touch range while
## the lag is under 150 ms; lifting a body or freeing a Caught miner, targets that do not move,
## succeed at 200 ms; a shot stops at a wall. The interactions themselves are MNR-05's and later.

const L = preload("res://tests/scenario/net/lagcomp_world.gd")
## A stand-in reach (MNR-05 owns the real one); Bob passes 1.0 tile from Ann.
const TOUCH: float = 1.2


func before_all() -> void:
	assert_true(Tuning.load_server())


## Ann presses every tick while Bob walks past her; returns [lag ticks, seen in range, judged in range] per press.
func _douse(rtt_ms: int) -> Array:
	var s: Scenario = make({"seed": 950 + rtt_ms, "fixture": L.room()})
	# Ann faces Bob's path (south), so he walks through her cone.
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 90.0})
	ann.at(0).face(90.0)
	var bob: MinerHandle = s.add_miner("bob", Vector2i(3, 5))
	var lit: Array = []
	for y: int in 9:
		for x: int in 24:
			lit.append(Vector2i(x, y))
	s.run.light.grid.add_area("emergency", 3, 0, 0.6, lit)
	ann.link(rtt_ms, 0.0)
	ann.at(0).hold(InputRecord.HOLD_INTERACT, 200)
	bob.at(5).move(0.0, InputRecord.Gait.WALK, 70)
	# The client's views by frame tick (Capture.records_at keys them by the tick they arrived in).
	var frames: Dictionary = {}
	ann.capture.on_decoded = func(d: FrameDecoder.Decoded) -> void: frames[d.tick] = d.view
	var out: Array = []
	var judge: Callable = func(run: RunState) -> void:
		var c: InputBuffer.Consumed = run.inputs.input_for(ann.slot)
		if c == null or not c.real or (c.record.holds & InputRecord.HOLD_INTERACT) == 0:
			return
		var view: ReceivedView = frames.get(c.shown_tick, null)
		if view == null or view.entities.size() != 1:
			return
		var e: Dictionary = view.entities.values()[0]
		var bob_seen: Vector2 = e["position"]
		var me: Vector2 = run.registry.get_entity(ann.entity_id).position
		out.append([run.tick - c.shown_tick, me.distance_to(bob_seen), run.rewind.in_range_at(ann.entity_id, bob.entity_id, TOUCH, c.shown_tick),
			me.distance_to(run.registry.get_entity(bob.entity_id).position)])
	assert_true(s.run.add_system(L.Probe.new(judge)))
	s.step(90)
	return out


func test_douse_a_walking_teammate_under_150_ms() -> void:
	var presses: Array = _douse(0)
	var lags: Dictionary = {}
	var checked: int = 0
	var saved_by_rewind: int = 0
	for raw: Variant in presses:
		var p: Array = raw
		var lag: int = p[0]
		var seen: float = p[1]
		var judged: bool = p[2]
		var now_dist: float = p[3]
		lags[lag] = true
		# Seen in range, with the frame's 1/64-tile positions: the server agrees.
		if lag <= 3 and seen <= TOUCH - 0.02:
			assert_true(judged, "seen %.3f away at lag %d: the douse succeeds" % [seen, lag])
			checked += 1
			if now_dist > TOUCH:
				saved_by_rewind += 1
	gut.p("douse at 0 ms RTT: %d presses seen in touch range, %d of them out of range by now; lags %s ticks" % [checked, saved_by_rewind, lags.keys()])
	assert_gt(checked, 5, "presses with the target in view range")
	assert_gt(saved_by_rewind, 0, "some succeed only because the target is rewound")


func test_still_targets_at_200_ms() -> void:
	for kind: String in ["lift a body", "free a Caught miner"]:
		var s: Scenario = make({"seed": 960, "fixture": L.room()})
		var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
		var target: SimEntity = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(9.3, 4.5))
		ann.link(200, 2.0)
		ann.at(0).hold(InputRecord.HOLD_INTERACT, 200)
		var results: Array[bool] = []
		var lags: Array[int] = []
		var check: Callable = func(run: RunState) -> void:
			var c: InputBuffer.Consumed = run.inputs.input_for(ann.slot)
			if c != null and c.real and (c.record.holds & InputRecord.HOLD_INTERACT) != 0:
				results.append(run.rewind.in_range_at(ann.entity_id, target.id, TOUCH, c.shown_tick))
				lags.append(run.tick - c.shown_tick)
		assert_true(s.run.add_system(L.Probe.new(check)))
		s.step(60)
		lags.sort()
		gut.p("%s at 200 ms: %d checks, lag %d-%d ticks (capped at 3)" % [kind, results.size(), lags[0], lags[lags.size() - 1]])
		assert_gt(results.size(), 30)
		assert_false(results.has(false), "%s: every check succeeds" % kind)


func test_a_shot_stops_at_rock() -> void:
	var s: Scenario = make({"seed": 970, "fixture": L.room()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 2))
	var beyond: SimEntity = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(17.5, 2.5))
	s.step(3)
	var hit: Dictionary = s.run.rewind.trace_bodies(Vector2(10.5, 2.5), Vector2(1.0, 0.0), 20.0, float(s.run.tick), ann.entity_id)
	var wall: Vector2i = hit.get("wall", Vector2i(-1, -1))
	assert_eq(wall, Vector2i(14, 2), "the rock at x = 14 takes it")
	assert_false(hit.has("entity"))
	hit = s.run.rewind.trace_bodies(Vector2(10.5, 5.5), Vector2(1.0, 0.0), 20.0, float(s.run.tick), ann.entity_id)
	assert_true(hit.has("wall"), "with no body on the line it reaches the far wall")
	s.run.registry.move(beyond.id, Vector2(17.5, 5.5))
	s.step(1)
	hit = s.run.rewind.trace_bodies(Vector2(10.5, 5.5), Vector2(1.0, 0.0), 20.0, float(s.run.tick), ann.entity_id)
	assert_eq(int(Variants.number(hit.get("entity", 0))), beyond.id, "seen or not, the first body on the line")
