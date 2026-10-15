extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-04, the client's DarkView: at the fall the victim's own view of the moments before plays, frame
## by frame, decoding as their own client decoded it; skipping it, or its end, leaves the screen black.
## The interact press asks to watch, Use to stop; a coming-round window shows the own cone.

const D = preload("res://tests/scenario/rescue/dark_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _press(router: InputRouter, holds: int) -> void:
	router.record.holds = holds


## The replay comes about 7 s after the fall: the spell here outlasts it (the real one is 60-120 s).
func _fallen_with_replay(seed_value: int) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": "test", "overrides": {"rescue.coming_round_interval_s": [10.0, 12.0]}})
	var miners: Array[MinerHandle] = D.W.crew(s, 2, seed_value)
	var ann: MinerHandle = miners[0]
	ann.brain = null
	s.step(60)
	D.fall(s, ann)
	var f: DarkSystem.Fallen = D.fallen(s, ann)
	assert_true(s.run_until(func(_sv: Variant) -> bool: return f.replay_sent, 400))
	s.step(2)
	return [s, ann]


func test_the_replay_plays_then_goes_black() -> void:
	var got: Array = _fallen_with_replay(571)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var own: ReceivedView = s.client(ann).records_at(s.run.tick - 1)
	assert_true(DarkView.fallen(own), "her own block says unconscious")
	var view: DarkView = DarkView.new()
	view.tick(ann.connection, 0.0)
	assert_not_null(view.override_view(), "the replay is drawn")
	assert_eq(view.mode(own), WorldView.Mode.NORMAL, "drawn as a world view while it plays")
	var at_start: int = view.replay_frames[0][0]
	view.tick(null, 0.05 * 10)
	var played: ReceivedView = view.override_view()
	var hers: ReceivedView = s.client(ann).records_at(at_start + 9)
	assert_not_null(played)
	assert_eq(str(played.own), str(hers.own), "decoded as her client decoded it then")
	view.tick(null, 0.05 * (view.replay_frames.size() + 2))
	assert_true(view.replay_done, "its end")
	assert_null(view.override_view())
	assert_eq(view.mode(own), WorldView.Mode.BLACK, "then black")


func test_skipping_the_replay_and_the_watch_asks() -> void:
	var got: Array = _fallen_with_replay(572)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var own: ReceivedView = s.client(ann).records_at(s.run.tick - 1)
	var view: DarkView = DarkView.new()
	var router: InputRouter = InputRouter.new()
	view.tick(ann.connection, 0.0)
	assert_not_null(view.override_view())
	_press(router, InputRecord.HOLD_INTERACT)
	assert_eq(view.asks(router, own), [] as Array[int], "the first press skips the replay")
	assert_null(view.override_view(), "skipped")
	assert_eq(view.mode(own), WorldView.Mode.BLACK, "black")
	assert_eq(view.asks(router, own), [] as Array[int], "a held press asks nothing more")
	_press(router, 0)
	view.asks(router, own)
	_press(router, InputRecord.HOLD_INTERACT)
	assert_eq(view.asks(router, own), [1] as Array[int], "the next press: watch the next teammate")
	_press(router, InputRecord.HOLD_USE)
	assert_eq(view.asks(router, own), [] as Array[int], "Use stops only a watch under way")
	view.watching = true
	_press(router, 0)
	view.asks(router, own)
	_press(router, InputRecord.HOLD_USE)
	assert_eq(view.asks(router, own), [0] as Array[int], "Use: stop watching")
	# Coming round: the own cone, and no watch asks.
	assert_true(D.until_window(s, ann))
	s.step(3)
	var waking: ReceivedView = s.client(ann).records_at(s.run.tick - 1)
	assert_true(DarkView.in_window(waking), "her block says she may move")
	view.watching = false
	assert_eq(view.mode(waking), WorldView.Mode.COMING_ROUND)
	_press(router, 0)
	view.asks(router, waking)
	_press(router, InputRecord.HOLD_INTERACT)
	assert_eq(view.asks(router, waking), [] as Array[int], "the press is the game's in a window")
	view.watching = true
	view.watch_view = ReceivedView.new()
	assert_null(view.override_view(waking), "a watch under way gives way to the own cone")
	assert_eq(view.mode(waking), WorldView.Mode.COMING_ROUND)
