extends "res://tests/scenario/kit/scenario_test.gd"
## SND-12 (§13.9): a Hand stub facing Ann receives her STOP, COME, OK and POINT (POINT with its tile)
## through signal_seen; a Hand facing away receives none. MOD-08 will act on them.

const W = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_hand_in_the_cone_takes_orders() -> void:
	var s: Scenario = make({"seed": 1162, "fixture": W.road(40)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = W.miner(s, "ann", a, 0.0)
	var hand: MinerHandle = W.miner(s, "hand", a + Vector2i(9, 0), 180.0, false)
	var away: MinerHandle = W.miner(s, "away", a + Vector2i(9, 1), 0.0, false)
	var hands: Array[int] = [hand.entity_id, away.entity_id]
	s.run.crew.is_hand_driven = func(e: int) -> bool: return hands.has(e)
	var orders: Array[Array] = []
	s.run.lamp_signals.signal_seen.connect(func(h: int, kind: LampSignalKind.Kind, tile: Vector2i) -> void:
		orders.append([h, kind, tile]))
	s.step(3)
	for kind: LampSignalKind.Kind in [LampSignalKind.Kind.STOP, LampSignalKind.Kind.COME, LampSignalKind.Kind.OK, LampSignalKind.Kind.POINT]:
		W.signal_press(s, ann, kind)
		s.step(50)
	assert_eq(orders.size(), 4, "four orders, all to the Hand facing her")
	for o: Array in orders:
		var who: int = o[0]
		assert_eq(who, hand.entity_id)
	var last: Array = orders[3]
	var kind: int = last[1]
	var tile: Vector2i = last[2]
	assert_eq(kind, LampSignalKind.Kind.POINT)
	assert_eq(tile, a + Vector2i(6, 0), "POINT with its tile")
