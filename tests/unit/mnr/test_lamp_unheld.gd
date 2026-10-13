extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-06: unheld lamps belong to nobody. Any miner shutters one in place in 1 s, and no API
## opens one in place; a dropped lamp keeps its shutter and flame; a snuffed lamp stays Out where
## it is; the Moth takes a lamp Out to its hoard, and a pick-up there leaves it Out.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(0, 1))
	s.step(1)
	var l: GauzeLamp = L.lit_in_hand(s, ann, LampRules.WICK_UP)
	s.step(1)
	return [s, ann, bob, l, a]


func test_shutter_in_place_never_open() -> void:
	var parts: Array = _setup(1)
	var s: Scenario = parts[0]
	var bob: MinerHandle = parts[2]
	var l: GauzeLamp = parts[3]
	var a: Vector2i = parts[4]
	assert_true(s.run.lamps.set_down(s.run, l, a + Vector2i(1, 0)))
	s.step(2)
	var lamp_entity: int = 0
	for raw: Variant in s.run.inventory.world.items.keys():
		if s.run.inventory.world.items[raw] == l.item:
			lamp_entity = int(Variants.number(raw))
	var act: TimedAction = s.run.lamps.shutter_in_place_action(s.run, bob.entity_id, lamp_entity)
	assert_eq(act.ticks_needed, 20, "1 s")
	# Interact on an unheld lamp otherwise picks it up: MNR-15 binds shutter-in-place to its own
	# control. Here bob's hold is fed straight to the runner, with the action already started.
	assert_true(s.run.inventory.start_action(s.run, act))
	s.run.inventory.holds_source = func(_run: RunState, slot: int) -> int: return InputRecord.HOLD_INTERACT if slot == bob.slot else 0
	s.step(25)
	s.run.inventory.holds_source = Callable()
	assert_eq(l.state(), GauzeLamp.State.SET_DOWN_SHUTTERED, "shuttered where it lies by a teammate")
	assert_false(s.run.lamps.shutter(s.run, l, true), "nothing opens a lamp in place")
	assert_false(s.run.lamps.shutter_in_place(s.run, l, bob.entity_id), "already shuttered")
	assert_eq(l.state(), GauzeLamp.State.SET_DOWN_SHUTTERED)
	assert_true(s.run.lamps.pick_up(s.run, l, bob.entity_id), "to open it, pick it up")
	assert_eq(l.state(), GauzeLamp.State.SHUTTERED)
	assert_eq(l.holder, bob.entity_id, "anyone can take an unheld lamp")


func test_dropped_keeps_shutter_and_flame() -> void:
	for shut: bool in [false, true]:
		var parts: Array = _setup(10 if shut else 11)
		var s: Scenario = parts[0]
		var ann: MinerHandle = parts[1]
		var l: GauzeLamp = parts[3]
		var a: Vector2i = parts[4]
		if shut:
			s.run.lamps.douse(s.run, l, 0)
		s.run.lamps.drop_at_wall(ann.entity_id, a + Vector2i(0, -2))
		s.step(2)
		assert_eq(l.state(), GauzeLamp.State.SET_DOWN_SHUTTERED if shut else GauzeLamp.State.SET_DOWN_OPEN, "keeps its shutter")
		assert_true(l.burning(), "and its flame")
		assert_eq(Vector2i(floori(l.at.x), floori(l.at.y)), a, "where its holder was")
		assert_true(s.run.light.grid.flame_sources(Rect2(0, 0, 40, 40)).has(l.source))
		assert_null(W.belt(s, ann.entity_id).lamp_hand)


func test_snuffed_stays_out_where_it_is() -> void:
	var parts: Array = _setup(20)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[3]
	var a: Vector2i = parts[4]
	s.run.lamps.set_down(s.run, l, a + Vector2i(2, 0))
	s.step(1)
	s.run.lamps.snuff(s.run, l, "stythe")
	ann.at(s.run.tick).lamp(true, 0)
	ann.at(s.run.tick + 3).lamp(false, 2)
	s.step(60)
	assert_eq(l.state(), GauzeLamp.State.OUT)
	assert_eq(Vector2i(floori(l.at.x), floori(l.at.y)), a + Vector2i(2, 0), "Out where it lies")
	assert_eq(l.source, 0, "no light and no flame")
	assert_eq(s.run.lamps.openings.size(), 0, "nothing relit it")


func test_moth_takes_it_home() -> void:
	var parts: Array = _setup(30)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[3]
	var a: Vector2i = parts[4]
	W.light(s)
	assert_true(s.run.lamps.take_by_moth(s.run, l, 999))
	s.step(2)
	assert_eq(l.state(), GauzeLamp.State.CARRIED_OFF)
	assert_null(W.belt(s, ann.entity_id).lamp_hand, "gone with the Moth")
	assert_true(s.run.lamps.hoard(s.run, l, a + Vector2i(1, 0)))
	s.step(2)
	assert_eq(l.state(), GauzeLamp.State.HOARDED)
	ann.at(s.run.tick).face(0.0).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(40)
	assert_eq(W.belt(s, ann.entity_id).lamp_hand, l.item, "an ordinary 1 s pick-up")
	assert_eq(l.state(), GauzeLamp.State.OUT, "taken back from the hoard, it is Out")


func test_never_sent_never_opened_by_another() -> void:
	var parts: Array = _setup(40)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var l: GauzeLamp = parts[3]
	W.light(s)
	s.step(6)
	for c: Dictionary in [ann.connection.inventory, bob.connection.inventory]:
		for key: Variant in c.keys():
			assert_false(str(key) in ["oil", "notches", "fills"], "oil and notches never ride the belt message")
	for raw: Variant in bob.connection.view.entities.values():
		for key: Variant in Variants.dict(raw).keys():
			assert_false(str(key) in ["oil", "notches", "fills"], "nor any frame")
	# Bob's actions only ever close her lamp; her own press opens it.
	s.run.lamps.douse(s.run, l, bob.entity_id)
	s.step(2)
	assert_false(s.run.lamps.douse(s.run, l, bob.entity_id), "a douse never toggles it back open")
	bob.at(s.run.tick).lamp(true, 1)
	bob.at(s.run.tick + 3).lamp(false, 1)
	s.step(12)
	assert_true(l.shutter_closed, "bob's own presses touch only his own lamp hand")
	for o: Dictionary in s.run.lamps.openings:
		assert_eq(int(Variants.number(o.get("holder", ann.entity_id))), ann.entity_id)
