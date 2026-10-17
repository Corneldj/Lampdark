extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-12 with SND-09 (Gameplay §6.4, §6.6): a live call makes caller and operator heard by each
## other for as long as it lasts; a call buzzing at an empty board never counts.

const P = preload("res://tests/unit/phones/phone_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _calls(s: Scenario, slot: int, from: int) -> int:
	var n: int = 0
	for r: Dictionary in s.run.heard.heard_log.slice(from):
		if r["cause"] == &"call" and int(Variants.number(r["slot"])) == slot:
			n += 1
	return n


func test_a_live_call_counts_and_a_buzzing_one_never() -> void:
	var s: Scenario = make({"seed": 4701, "fixture": P.road()})
	P.power(s)
	var p: PitPhone = P.phone(s, "p1", Vector2i(6, 2))
	var ann: MinerHandle = P.miner(s, "ann", Vector2i(5, 2))
	var bob: MinerHandle = P.miner(s, "bob", Vector2i(36, 2))
	s.step(3)
	var from: int = s.run.heard.heard_log.size()
	P.press(s, ann, 50)
	assert_eq(p.state, PitPhone.State.CALLING, "her flap is down")
	s.step(200)
	assert_eq(_calls(s, ann.slot, from), 0, "buzzing at an empty board: never heard")
	assert_true(s.run.phones.answer(s.run, p.number, bob.slot))
	s.step(100)
	assert_gte(_calls(s, ann.slot, from), 5, "on the line, she is heard, all the while")
	assert_gte(_calls(s, bob.slot, from), 5, "and so is the operator")
	s.run.phones.hang_up(s.run, p.number)
	var after: int = s.run.heard.heard_log.size()
	s.step(100)
	assert_eq(_calls(s, ann.slot, after), 0, "hung up, no more")
