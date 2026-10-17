extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-10 (Gameplay §3.9, 1:40:20 to 1:42:20): the last ride end to end. The engine catches (a real
## start, 1:40:20); at its run-up's end, 60 s on (1:41:20), four aboard pull the cord and the hold
## bell rings 20 s for nobody; the cage leaves at 1:41:40 and surfaces at 1:42:20. Its leaving ends
## the apex, puts the engine to Departed and freezes the map table. Ada, outside, is Left Below: her
## client stops seeing the riders, and nothing of the vote, the bell's time or the ride's progress
## reaches any client (NET-08's audit).

const K = preload("res://tests/unit/lift/cage_world.gd")
const A = preload("res://tests/scenario/apex/apex_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_last_ride() -> void:
	var s: Scenario = make({"seed": 10501, "fixture": K.E.T.C.scenario_fixture(), "overrides": A.ON})
	var gate: Gate = A.world(s, 60)
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ada: MinerHandle = s.add_miner("ada", A.on_road(gate, 30))
	var caught: int = A.start_engine(s)
	var hz: float = Tuning.f(&"net.tick_hz")
	var cage: Cage = s.run.cage
	# Wilf and Harry (who started it) and Ellis and Nell board; each has a deck tile of their own.
	var crew: Array[MinerHandle] = [s.miners[1], s.miners[2], K.aboard(s, "ellis", 1), K.aboard(s, "nell", 2)]
	var spots: Array[Vector2i] = []
	for y: int in range(cage.deck.position.y, cage.deck.end.y):
		for x: int in range(cage.deck.position.x, cage.deck.end.x):
			if not K.cord_tiles(s).has(Vector2i(x, y)):
				spots.append(Vector2i(x, y))
	for i: int in crew.size():
		K.move_to(s, crew[i], spots[i])
	var surfaced: Array[int] = [-1]
	cage.cage_surfaced.connect(func(top: Dictionary) -> void: surfaced[0] = int(Variants.number(top["tick"])))
	# 1:41:20: the run-up ends and the four pull in turn at the cord, each stepping back after.
	var run_up: int = caught + roundi(Tuning.f(&"lift.clutch_run_up_s") * hz)
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.tick >= run_up, roundi(80.0 * hz)))
	var by_cord: Vector2i = K.cord_tiles(s)[0]
	for i: int in crew.size():
		K.move_to(s, crew[i], by_cord)
		K.face(s, crew[i], by_cord)
		K.pull(s, crew[i])
		K.move_to(s, crew[i], spots[i])
	assert_eq(cage.state, Cage.State.BELL, "four of five pull: the bell")
	var rang: int = K.bells(s).back().tick
	assert_lte(rang - run_up, 40, "at the run-up's end")
	# 1:41:40: it leaves; 1:42:20: the surface.
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.is_departed(), K.bell_ticks() + 10))
	assert_eq(cage.ride.departed_at - rang, K.bell_ticks(), "20 s of bell for nobody")
	assert_eq(cage.riders().filter(func(e: int) -> bool: return s.run.registry.get_entity(e).kind == WorldIds.EntityKind.MINER).size(), 4)
	assert_false(cage.riders().has(ada.entity_id), "Ada is Left Below")
	assert_eq(s.run.engine.state, WinderEngine.State.DEPARTED, "the engine's work is done")
	assert_false(s.run.apex.active, "the apex ends with the cage")
	if s.run.sheets != null and s.run.sheets.table != null:
		assert_true(s.run.sheets.table.frozen, "the map table frozen for the card")
	s.step(10)
	for raw: Variant in ada.connection.view.entities.values():
		var e: Dictionary = raw
		var at: Vector2 = e.get("position", Vector2.ZERO)
		assert_false(WorldCoords.cell_of(WorldCoords.tile_at(at)) == ShaftRide.RIDE_CELL, "Ada never sees the riders")
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return surfaced[0] >= 0, roundi(41.0 * hz)))
	assert_eq(surfaced[0] - cage.ride.departed_at, ShaftRide.ride_ticks(), "the surface 40 s on")
	assert_almost_eq(surfaced[0] - caught, roundi(120.0 * hz), 40, "1:40:20 to 1:42:20")
	assert_eq(audit.violation_count, 0, "nothing of the vote, the bell or the ride in any stream")
