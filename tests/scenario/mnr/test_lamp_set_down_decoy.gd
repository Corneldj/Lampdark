extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-06: an open lamp set down at wick up keeps lighting after its miner walks off; a second
## miner shutters it in place and cannot reopen it there (only by picking it up).

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_decoy() -> void:
	var s: Scenario = make({"seed": 41, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	ann.at(0).lamp(false, 2)
	s.step(2)
	var l: GauzeLamp = L.lit_in_hand(s, ann, LampRules.WICK_UP)
	ann.at(s.run.tick).face(0.0).hold(InputRecord.HOLD_SET_DOWN, 25)
	s.step(30)
	assert_eq(l.state(), GauzeLamp.State.SET_DOWN_OPEN, "set down open")
	var lamp_tile: Vector2i = Vector2i(floori(l.at.x), floori(l.at.y))
	assert_eq(lamp_tile, a + Vector2i(1, 0), "on the faced tile")
	ann.at(s.run.tick).walk_to(a + Vector2i(-2, 2))
	s.step(40)
	assert_almost_eq(s.run.light.light_at(lamp_tile), 1.0, 1e-3, "it keeps lighting with nobody beside it")
	assert_gte(s.run.light.light_at(lamp_tile + Vector2i(3, 0)), 0.30, "a decoy at wick up")
	# Bob shutters it in place, then cannot open it there.
	var lamp_entity: int = 0
	for raw: Variant in s.run.inventory.world.items.keys():
		if s.run.inventory.world.items[raw] == l.item:
			lamp_entity = int(Variants.number(raw))
	bob.at(s.run.tick).walk_to(lamp_tile + Vector2i(1, 0))
	s.step(60)
	assert_true(s.run.inventory.start_action(s.run, s.run.lamps.shutter_in_place_action(s.run, bob.entity_id, lamp_entity)))
	s.run.inventory.holds_source = func(_run: RunState, slot: int) -> int: return InputRecord.HOLD_INTERACT if slot == bob.slot else 0
	s.step(22)
	s.run.inventory.holds_source = Callable()
	assert_eq(l.state(), GauzeLamp.State.SET_DOWN_SHUTTERED)
	assert_eq(s.run.light.light_at(lamp_tile), 0.0, "dark")
	bob.at(s.run.tick).lamp(true, 1)
	bob.at(s.run.tick + 3).lamp(false, 1)
	s.step(15)
	assert_eq(l.state(), GauzeLamp.State.SET_DOWN_SHUTTERED, "his shutter presses never open a lamp he does not hold")
	assert_false(s.run.lamps.shutter(s.run, l, true), "and no API opens it in place")
