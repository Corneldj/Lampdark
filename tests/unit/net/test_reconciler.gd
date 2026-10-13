extends GutTest
## NET-05's reconciliation: a matching prediction stands; a 0.5-tile correction blends out over
## 100 ms; one over 2 tiles snaps; while the server drives the miner, input moves nothing.

var open: Callable = func(_t: Vector2i) -> bool: return false


func before_all() -> void:
	assert_true(Tuning.load_server())


func _own(at: Vector2, flags: int = 0) -> Dictionary:
	return {"position": at, "facing": 0, "gait": 1, "speed_q": 100, "flags": flags, "stamina_q": 120}


func _walk_east() -> InputRecord:
	var r: InputRecord = InputRecord.new()
	r.move_dir = 0
	r.gait = InputRecord.Gait.WALK
	return r


## A prediction placed at (5.5, 5.5) by a first frame, then n inputs of walking east.
func _predicted(n: int) -> Array:
	var p: Prediction = Prediction.new()
	var r: Reconciler = Reconciler.new(p)
	r.on_frame(_own(Vector2(5.5, 5.5)), 0xFFFF, open, 0)
	for seq: int in n:
		p.apply(seq, _walk_east(), open)
	return [p, r]


func test_a_matching_prediction_stands() -> void:
	var setup: Array = _predicted(10)
	var p: Prediction = setup[0]
	var r: Reconciler = setup[1]
	var at_4: MinerMotion.State = p.history[4]
	var err: float = r.on_frame(_own(Vector2(at_4.x, at_4.y)), 4, open, 1000)
	assert_lt(err, 0.01)
	assert_eq(r.corrections, 0)
	assert_almost_eq(p.state.x, 5.5 + 10 * 0.15, 1e-9, "ten ticks of walking predicted")


func test_a_half_tile_correction_blends_over_100_ms() -> void:
	var setup: Array = _predicted(10)
	var p: Prediction = setup[0]
	var r: Reconciler = setup[1]
	var before: Vector2 = r.draw_position(0)
	var at_4: MinerMotion.State = p.history[4]
	r.on_frame(_own(Vector2(at_4.x - 0.5, at_4.y)), 4, open, 1000000)
	assert_eq(r.corrections, 1)
	assert_eq(r.snaps, 0, "never snapping")
	assert_almost_eq(p.state.x, before.x - 0.5, 1e-6, "re-simulated from the server's state")
	assert_almost_eq(r.draw_position(1000000).x, before.x, 1e-6, "drawn where it was at first")
	assert_almost_eq(r.draw_position(1050000).x, before.x - 0.25, 1e-6, "halfway after 50 ms")
	assert_almost_eq(r.draw_position(1100000).x, before.x - 0.5, 1e-6, "blended out after 100 ms")


func test_over_two_tiles_snaps() -> void:
	var setup: Array = _predicted(10)
	var p: Prediction = setup[0]
	var r: Reconciler = setup[1]
	var at_4: MinerMotion.State = p.history[4]
	r.on_frame(_own(Vector2(at_4.x - 2.5, at_4.y)), 4, open, 1000000)
	assert_eq(r.snaps, 1)
	assert_almost_eq(r.draw_position(1000000).x, p.state.x, 1e-9, "drawn at once where the server put it")


func test_server_driven_input_moves_nothing() -> void:
	var setup: Array = _predicted(2)
	var p: Prediction = setup[0]
	var r: Reconciler = setup[1]
	r.on_frame(_own(Vector2(8.0, 5.5), 1 << 15), 1, open, 0)
	assert_true(p.server_driven)
	for seq: int in range(2, 30):
		p.apply(seq, _walk_east(), open)
	assert_eq(Vector2(p.state.x, p.state.y), Vector2(8.0, 5.5), "the server drives the miner")
	r.on_frame(_own(Vector2(8.5, 5.5), 1 << 15), 29, open, 0)
	assert_eq(p.state.x, 8.5, "following the server")


func test_facing_follows_live_input_unless_locked() -> void:
	var p: Prediction = Prediction.new()
	assert_eq(p.facing_for_render(12345), 12345, "every render frame, whatever the network does")
	p.state.facing = 500
	p.constraints.facing_lock = true
	assert_eq(p.facing_for_render(12345), 500, "a stretcher locks it")


func test_the_predicted_lamp() -> void:
	var setup: Array = _predicted(1)
	var p: Prediction = setup[0]
	var shut: InputRecord = _walk_east()
	shut.desired = 1 | (1 << 1)
	for seq: int in range(1, 4):
		p.apply(seq, shut, open)
	assert_false(Variants.flag(p.lamp()["shutter_closed"]), "the shutter takes 0.2 s")
	p.apply(4, shut, open)
	p.apply(5, shut, open)
	assert_true(Variants.flag(p.lamp()["shutter_closed"]))
	var at: Vector2 = p.lamp()["position"]
	assert_eq(at, Vector2(p.state.x, p.state.y), "the pool goes where the miner is predicted")
