extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-12 with HAZ-03 (Gameplay §6.6, §12.5): a roof brought down by a running step cuts the line
## whose road home crosses it, for the run: a call on it ends that tick, the board is told, its flap
## goes dark (no crank reaches the board again). A line whose road runs elsewhere stays live.

const W = preload("res://tests/unit/hazards/collapse_world.gd")
const P = preload("res://tests/unit/phones/phone_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_fall_cuts_the_line_across_it() -> void:
	var s: Scenario = make(W.cfg(4501))
	var point: CollapsePoints.Point = W.arm(s)
	P.power(s)
	# Line 1's road home crosses the collapse; line 2's runs another way.
	var across: PitPhone = P.phone(s, "across", Vector2i(30, 2), [[Vector2i.ZERO, 1]])
	var aside: PitPhone = P.phone(s, "aside", Vector2i(34, 2), [[Vector2i(1, 0), 4]])
	var ann: MinerHandle = P.miner(s, "ann", Vector2i(29, 2))
	var bob: MinerHandle = P.miner(s, "bob", Vector2i(36, 1))
	s.step(3)
	var cuts: Array[int] = []
	var ends: Array[String] = []
	s.run.phones.line_cut.connect(func(n: int) -> void: cuts.append(n))
	s.run.phones.ended.connect(func(_n: int, why: String) -> void: ends.append(why))
	P.press(s, ann, 50)
	assert_eq(across.state, PitPhone.State.CALLING, "Ann calls the board")
	assert_true(s.run.phones.answer(s.run, across.number, bob.slot))
	W.trigger(s, Vector2i(W.WEST - 3, 2))
	assert_gt(W.until_fallen(s, point.id), 0, "the roof falls")
	assert_eq(cuts, [across.number], "only the line across it is cut")
	assert_eq(ends, ["cut"], "and its call ends")
	assert_false(s.run.phones.live(s.run, across), "dead for the run")
	assert_true(s.run.phones.live(s.run, aside), "the other line lives")
	s.step(10)
	var calls: Array[int] = []
	s.run.phones.calling.connect(func(n: int, _m: int) -> void: calls.append(n))
	P.press(s, ann, 50)
	assert_eq(calls.size(), 0, "a crank on the cut line reaches nothing")
	assert_eq(across.caller, 0)
