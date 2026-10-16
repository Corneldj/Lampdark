extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-14: a tub on its rails (Gameplay §4.3). Taken hold of in 20 ticks of held interact, it runs
## only along the rails: 1.5 tiles/s for one pusher, 3.0 for two pushing the same way, and opposed
## pushes stop it with no knock. A push across the rails moves nothing; at a junction it takes the
## branch nearest the push; it stops at the rails' end and at an old fall's rubble. It rumbles at
## 14 np as it starts and every 10 ticks while moving. It holds a body, the drum gear or up to 4
## cans and refuses a second cargo; a tap of interact takes a can back out.

## Rails along y 2 from x 3 to 23, and a branch south from (11, 2) to (11, 5); 'f' is an old fall
## across the road in the second map.
const RAILS: PackedStringArray = [
	"##############################",
	"#............................#",
	"#..=====================.....#",
	"#..........=.................#",
	"#..........=.................#",
	"#..........=.................#",
	"#............................#",
	"##############################",
]
const FALLEN: PackedStringArray = [
	"##############################",
	"#..............#.............#",
	"#..============#=======......#",
	"#..............#.............#",
	"##############################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


## A tub at (tub_x, 2) and two miners west of it: [s, ann, bob, tub].
func _world(run_seed: int, picture: PackedStringArray = RAILS, tub_x: int = 5) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": FixtureMap.from_ascii(picture, {"=": "="})})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(tub_x - 1, 2))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(tub_x, 1))
	ann.at(s.run.tick).face(0.0)
	bob.at(s.run.tick).face(90.0)
	s.step(2)
	var tub: int = s.run.tubs.place(s.run, Vector2i(tub_x, 2))
	assert_ne(tub, 0)
	return [s, ann, bob, tub]


func _hold(s: Scenario, hands: Array[MinerHandle]) -> void:
	for h: MinerHandle in hands:
		h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 26)
	s.step(29)
	for h: MinerHandle in hands:
		assert_true(s.run.tubs.holding(h.entity_id), "%s holds the tub" % h.name)


func _x(s: Scenario, tub: int) -> float:
	return s.run.registry.get_entity(tub).position.x


## Ticks pushing `dir_deg`, then the tub's travel over the 40 ticks after it started moving.
func _speed(s: Scenario, tub: int, hands: Array[MinerHandle], dir_deg: float) -> float:
	var from: Vector2 = s.run.registry.get_entity(tub).position
	var started: Array[int] = [-1]
	var at_40: Array[float] = [-1.0]
	s.on_tick = func(sc: Scenario) -> void:
		var p: Vector2 = sc.run.registry.get_entity(tub).position
		if started[0] < 0 and p.distance_to(from) > 1e-6:
			started[0] = sc.run.tick
		if started[0] >= 0 and sc.run.tick - started[0] == 39:
			at_40[0] = p.distance_to(from)
	for h: MinerHandle in hands:
		h.at(s.run.tick).move(dir_deg, InputRecord.Gait.WALK, 50)
	s.step(54)
	s.on_tick = Callable()
	return at_40[0] / 2.0


func test_one_pusher_1_5_and_two_3_0_tiles_a_second() -> void:
	var w: Array = _world(1491)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var tub: int = w[3]
	_hold(s, [ann] as Array[MinerHandle])
	assert_eq(s.run.inventory.held_bits(ann.entity_id) >> 8, ItemKinds.LOAD_TUB, "both hands on the tub")
	assert_almost_eq(_speed(s, tub, [ann] as Array[MinerHandle], 0.0), 1.5, 1e-3, "one pusher")
	assert_lt(s.run.registry.get_entity(ann.entity_id).position.x, _x(s, tub), "the pusher behind it")
	var t: Array = _world(1492)
	var s2: Scenario = t[0]
	var both: Array[MinerHandle] = [t[1], t[2]]
	var tub2: int = t[3]
	_hold(s2, both)
	assert_almost_eq(_speed(s2, tub2, both, 0.0), 3.0, 1e-3, "two pushers")


func test_opposed_pushes_stop_it_without_a_knock() -> void:
	var w: Array = _world(1493)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var tub: int = w[3]
	_hold(s, [ann, bob] as Array[MinerHandle])
	var at: float = _x(s, tub)
	var from: int = s.run.noise.event_log.size()
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 30)
	bob.at(s.run.tick).move(180.0, InputRecord.Gait.WALK, 30)
	s.step(34)
	assert_eq(_x(s, tub), at, "opposed: it stays")
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from):
		assert_ne(e.type, NoiseTypes.Type.CARRY_KNOCK, "no knock")
		assert_ne(e.type, NoiseTypes.Type.TUB_RUMBLE, "no rumble")


func test_it_runs_only_along_the_rails_to_their_end() -> void:
	var w: Array = _world(1494)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var tub: int = w[3]
	_hold(s, [ann] as Array[MinerHandle])
	var at: Vector2 = s.run.registry.get_entity(tub).position
	ann.at(s.run.tick).move(270.0, InputRecord.Gait.WALK, 30)
	s.step(34)
	assert_eq(s.run.registry.get_entity(tub).position, at, "pushed across the rails: nothing")
	ann.at(s.run.tick).move(-30.0, InputRecord.Gait.WALK, 400)
	s.step(404)
	assert_eq(s.run.registry.get_entity(tub).position, Vector2(23.5, 2.5), "along them to their end, and no further")
	var e: SimEntity = s.run.registry.get_entity(ann.entity_id)
	assert_lte(e.position.distance_to(Vector2(23.5, 2.5)), Tuning.f(&"vision.touch_range_tiles"), "its pusher with it")


func test_a_junction_takes_the_branch_nearest_the_push() -> void:
	for case: Array in [[60.0, Vector2(11.5, 5.5)], [20.0, Vector2(23.5, 2.5)]]:
		var w: Array = _world(1495 + roundi(float(Variants.number(case[0]))), RAILS, 8)
		var s: Scenario = w[0]
		var ann: MinerHandle = w[1]
		var tub: int = w[3]
		_hold(s, [ann] as Array[MinerHandle])
		ann.at(s.run.tick).move(float(Variants.number(case[0])), InputRecord.Gait.WALK, 400)
		s.step(404)
		var want: Vector2 = case[1]
		assert_eq(s.run.registry.get_entity(tub).position, want, "pushed at %.0f°" % float(Variants.number(case[0])))


func test_it_rumbles_while_it_moves() -> void:
	var w: Array = _world(1497)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var tub: int = w[3]
	_hold(s, [ann] as Array[MinerHandle])
	var from: int = s.run.noise.event_log.size()
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 30)
	s.step(50)
	var rumbles: Array[int] = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from):
		if e.type == NoiseTypes.Type.TUB_RUMBLE:
			assert_eq(e.level_np, 14.0)
			assert_eq(e.source_entity, tub)
			rumbles.append(e.tick)
	assert_eq(rumbles.size(), 3, "as it starts, then every 10 ticks over 30 ticks of pushing")
	assert_eq([rumbles[1] - rumbles[0], rumbles[2] - rumbles[1]], [10, 10])


func test_it_stops_at_an_old_fall() -> void:
	var w: Array = _world(1498, FALLEN, 5)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var tub: int = w[3]
	_hold(s, [ann] as Array[MinerHandle])
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 300)
	s.step(304)
	assert_eq(s.run.registry.get_entity(tub).position, Vector2(14.5, 2.5), "the last rail tile before the rubble")


func test_one_cargo_at_a_time() -> void:
	var w: Array = _world(1499)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var tub: int = w[3]
	var tubs: TubRails = s.run.tubs
	# A body set down from a carry beside it goes in.
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(45)
	assert_true(s.run.carry.is_carrying(ann.entity_id))
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
	s.step(4)
	assert_eq(tubs.cargo(s.run, tub), "body", "the body went into the tub")
	assert_eq(s.run.registry.get_entity(bob.entity_id).position, s.run.registry.get_entity(tub).position)
	# A second cargo is refused: the drum gear, a can.
	var gear: int = s.run.loads.place(s.run, ItemKinds.Kind.DRUM_GEAR, Vector2(5.5, 4.0), 0)
	assert_false(tubs.take_gear(s.run, gear), "no gear on a body")
	var can: Item = s.run.inventory.world.make(ItemKinds.Kind.PARAFFIN_CAN, 1, {"fills": 4})
	assert_true(s.run.inventory.give(s.run, ann.entity_id, can))
	assert_false(tubs.put_can(s.run, ann.entity_id, tub), "no can on a body")
	# Pushed, the body rides in it.
	s.run.inventory.hands_of(ann.entity_id).free_hand = null
	_hold(s, [ann] as Array[MinerHandle])
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 20)
	s.step(24)
	assert_eq(s.run.registry.get_entity(bob.entity_id).position, s.run.registry.get_entity(tub).position, "the body rides")
	assert_gt(_x(s, tub), 6.0)


func test_cans_go_in_one_at_a_time_up_to_four() -> void:
	var w: Array = _world(1500)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var tub: int = w[3]
	var cans: Array[Item] = []
	for i: int in 5:
		var can: Item = s.run.inventory.world.make(ItemKinds.Kind.PARAFFIN_CAN, 1, {"fills": 4 - i % 2})
		cans.append(can)
		assert_true(s.run.inventory.give(s.run, ann.entity_id, can))
		ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
		s.step(4)
		if i < 4:
			assert_eq(s.run.tubs.cans_in(s.run, tub), i + 1, "can %d in" % (i + 1))
			assert_null(s.run.inventory.hands_of(ann.entity_id).free_hand)
	assert_eq(s.run.tubs.cans_in(s.run, tub), 4, "four at most")
	assert_eq(s.run.inventory.hands_of(ann.entity_id).free_hand, cans[4], "the fifth stays in hand")
	assert_eq(s.run.inventory.held_bits(tub) >> 8, 0, "a tub is not a miner")
	var gear: int = s.run.loads.place(s.run, ItemKinds.Kind.DRUM_GEAR, Vector2(5.5, 4.0), 0)
	assert_false(s.run.tubs.take_gear(s.run, gear), "no gear on cans")
	# A tap takes the last one back out, with its oil.
	s.run.inventory.hands_of(ann.entity_id).free_hand = null
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 3)
	s.step(6)
	var out: Item = s.run.inventory.hands_of(ann.entity_id).free_hand
	assert_not_null(out, "a can in hand")
	assert_eq(out.uid, cans[3].uid, "the last put in")
	assert_eq(int(Variants.number(out.state["fills"])), int(Variants.number(cans[3].state["fills"])))
	assert_eq(s.run.tubs.cans_in(s.run, tub), 3)
	assert_false(s.run.tubs.holding(ann.entity_id), "a tap takes no hold")
