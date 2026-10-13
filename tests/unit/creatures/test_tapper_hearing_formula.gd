extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-08's hearing: within (np - door losses - 4) x the ring multiplier tiles of path. Ring 1: a
## whisper at 2.0 tiles heard, talk at 8.0 heard, a shout at 16 heard; ring 4: talk at 12.8. The
## +0.1 cases are checked as the same 0.1 of budget short (the fixture's distances are whole
## tiles). A shut gate costs 12 np before the multiplier.

const T = preload("res://tests/scenario/creatures/tapper_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func _ring(ring: int) -> void:
	# Every fixture tile is in `ring`: rings start this close to the shaft centre.
	var bounds: Array = [1000000, 1000001, 1000002, 1000003]
	for i: int in ring:
		bounds[i] = 1 + i
	Tuning.set_dev_override("depth.ring_start_tiles", bounds)


func test_ring_1() -> void:
	_ring(1)
	var s: Scenario = make({"seed": 1, "fixture": T.road()})
	assert_eq(WorldCoords.ring_of_point(Vector2(1.5, 1.5)), 1)
	var h: TapperHearing = T.ears(s)
	var whisper: float = Tuning.f(&"voice.whisper_np")
	var talk: float = Tuning.f(&"voice.talk_np")
	var shout: float = Tuning.f(&"voice.shout_np")
	T.voice(s, 2, whisper)
	assert_eq(T.heard_now(s, h), 1, "a whisper at 2.0 tiles")
	T.voice(s, 2, whisper - 0.1)
	assert_eq(T.heard_now(s, h), 0, "a whisper 0.1 tile of budget short (2.1 tiles)")
	T.voice(s, 3, whisper)
	assert_eq(T.heard_now(s, h), 0, "a whisper at 3 tiles")
	T.voice(s, 8, talk)
	assert_eq(T.heard_now(s, h), 1, "talk at 8.0 tiles")
	T.voice(s, 8, talk - 0.1)
	assert_eq(T.heard_now(s, h), 0, "talk 0.1 tile short (8.1 tiles)")
	T.voice(s, 16, shout)
	assert_eq(T.heard_now(s, h), 1, "a shout at 16 tiles")
	T.voice(s, 17, shout)
	assert_eq(T.heard_now(s, h), 0)


func test_ring_4() -> void:
	_ring(4)
	var s: Scenario = make({"seed": 2, "fixture": T.road()})
	assert_eq(WorldCoords.ring_of_point(Vector2(1.5, 1.5)), 4)
	var h: TapperHearing = T.ears(s)
	var talk: float = Tuning.f(&"voice.talk_np")
	T.voice(s, 12, talk)
	assert_eq(T.heard_now(s, h), 1, "talk at 12 tiles in ring 4")
	T.voice(s, 13, talk)
	assert_eq(T.heard_now(s, h), 0, "13 tiles is past 12.8")
	# 12.8 is the budget: (12 - 4) x 1.6. An eighth of a np more makes it 13.0, which reaches 13.
	T.voice(s, 13, talk + 0.125)
	assert_eq(T.heard_now(s, h), 1, "a budget of 13.0 reaches 13 tiles")


func test_a_shut_gate_costs_12_np() -> void:
	_ring(1)
	var rows: PackedStringArray = T.road().rows
	var r: String = rows[2]
	rows[2] = r.substr(0, 3) + "G" + r.substr(4)
	var s: Scenario = make({"seed": 3, "fixture": FixtureMap.from_ascii(rows)})
	var h: TapperHearing = T.ears(s)
	# A struck sound through the air (voice never crosses a shut gate at all, SND-01).
	var bang: Callable = func(tiles: int) -> void:
		s.run.noise.emit(NoiseTypes.Type.RAIL_BANG, Vector2i(1 + tiles, 2), {"level_np": 20.0})
	bang.call(3)
	s.step(1)
	var shut: Array[TapperHearing.HeardEvent] = h.take()
	assert_eq(shut.size(), 1, "20 np behind the shut gate: (20 - 12 - 4) x 1.0 covers the path")
	assert_true(s.set_gate(1, true))
	s.step(1)
	bang.call(3)
	s.step(1)
	var open: Array[TapperHearing.HeardEvent] = h.take()
	assert_eq(open.size(), 1)
	if not shut.is_empty() and not open.is_empty():
		assert_almost_eq(open[0].energy_np - shut[0].energy_np, 12.0, 0.001, "the shut gate took 12 np before the check")
	assert_true(s.set_gate(1, false))
	s.step(1)
	s.run.noise.emit(NoiseTypes.Type.RAIL_BANG, Vector2i(4, 2), {"level_np": 15.0})
	assert_eq(T.heard_now(s, h), 0, "15 np behind it: 15 - 12 is under the 4 np threshold")
