extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-04 (Gameplay §3.3, §11.11, §13.10): the main switch for a lone human. In a public lobby with
## only Hired Hands besides, Ann holds the trip, lets go, turns and throws the switch inside the
## 3 s hold-over. When a second human is conscious the alone rules end: the same press, after Ann has
## let go, misses.

const J = preload("res://tests/unit/lift/job_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _switch(s: Scenario, ann: MinerHandle, events: Array) -> void:
	J.hold(s, ann, 20)
	var let_go: int = s.run.tick + 20
	ann.at(let_go + 4).face(0.0)
	ann.at(let_go + 40).hold(InputRecord.HOLD_INTERACT, 2)
	s.step(let_go + 80 - s.run.tick)


func test_a_lone_human_throws_the_switch_alone() -> void:
	var s: Scenario = make({"seed": 2401, "fixture": J.room(), "mode": ServerConfig.Mode.PUBLIC})
	var events: Array = []
	J.cue_press(s, events, 0.0, J.LONE_H, J.LONE_P)
	var ann: MinerHandle = J.lone(s, "ann")
	var hand: MinerHandle = s.add_miner("hand", Vector2i(12, 2))
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id
	s.step(10)
	assert_true(AloneRules.is_alone(s.run, ann.entity_id), "the only human: a lone human")
	_switch(s, ann, events)
	assert_eq(J.whats(events), ["cue", "success"] as Array[String], "held, let go, thrown within 3 s")


func test_a_second_human_ends_the_alone_rules() -> void:
	var s: Scenario = make({"seed": 2402, "fixture": J.room(), "mode": ServerConfig.Mode.PUBLIC})
	var events: Array = []
	J.cue_press(s, events, 0.0, J.LONE_H, J.LONE_P)
	var ann: MinerHandle = J.lone(s, "ann")
	s.add_miner("bob", Vector2i(12, 2))
	s.step(10)
	assert_false(AloneRules.is_alone(s.run, ann.entity_id), "two humans in a public lobby: not alone")
	_switch(s, ann, events)
	assert_eq(J.whats(events), ["cue", "miss:let go"] as Array[String], "in a crew the trip goes when let go")
