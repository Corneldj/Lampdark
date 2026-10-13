extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-07: Check Lamp's record (the lamp's oil in 48ths of a fill and its notches) reaches only the
## holder's client and only while the control is held; nothing else rides with it.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_record_only_to_the_holder_while_held() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(2, 0))
	s.step(1)
	var l: GauzeLamp = L.lit_in_hand(s, ann)
	l.oil = 0.5
	l.notches = 2
	s.step(4)
	assert_false(ann.connection.inventory.has("check"), "nothing while not held")
	var bob_ever: Array[bool] = [false]
	s.on_tick = func(_sc: Scenario) -> void:
		if bob.connection.inventory.has("check"):
			bob_ever[0] = true
	ann.at(s.run.tick).hold(InputRecord.HOLD_CHECK_LAMP, 20)
	s.step(10)
	var check: Dictionary = Variants.dict(ann.connection.inventory.get("check", {}))
	assert_eq(check.keys().size(), 2, "only oil and notches")
	assert_between(int(Variants.number(check["oil48"])), 23, 24, "oil in 48ths: about half")
	assert_eq(int(Variants.number(check["notches"])), 2)
	s.step(20)
	assert_false(ann.connection.inventory.has("check"), "released: gone")
	assert_false(bob_ever[0], "never to anyone else")
	assert_eq(s.run.lamps.check_record(bob.entity_id), {}, "no lamp: an empty record")
