extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-09: a lit candle set down in the grey box stays an unheld flame (owner none, FLAG_UNHELD, the
## Moth may smother it but never take it) and keeps burning, silent, after its miner walks away.

func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_candle_set_down_stays_an_unheld_flame() -> void:
	var s: Scenario = make({"seed": 933, "fixture": "test"})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(2, 1), {"facing_deg": 0.0})
	ann.brain = null
	s.step(2)
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	var candle: Item = s.run.inventory.world.make(ItemKinds.Kind.CANDLE, 1, {"lit": true, "burn_ticks": 6000})
	h.lamp_hand = candle
	s.step(2)
	assert_ne(s.run.candles.source_of(candle), 0, "burning in her hand")
	ann.at(s.run.tick + 1).hold(InputRecord.HOLD_SET_DOWN, 30)
	s.step(32)
	assert_null(h.lamp_hand, "set down")
	var events_before: int = s.run.noise.event_log.size()
	ann.at(s.run.tick + 1).move(0.0, InputRecord.Gait.WALK, 40)
	s.step(80)
	var source: int = s.run.candles.source_of(candle)
	assert_ne(source, 0, "still burning")
	var info: Dictionary = s.run.light.grid.source_info(source)
	assert_eq(int(Variants.number(info["owner"])), 0, "nobody's")
	var flags: int = int(Variants.number(info["flags"]))
	assert_eq(flags & LbLightGrid.FLAG_UNHELD, LbLightGrid.FLAG_UNHELD, "an unheld flame")
	assert_eq(flags & LbLightGrid.FLAG_CANNOT_TAKE, LbLightGrid.FLAG_CANNOT_TAKE, "never taken")
	var at: Vector2 = info["position"]
	assert_lt(at.distance_to(me), 2.0, "where she left it")
	assert_gt(s.run.registry.get_entity(ann.entity_id).position.distance_to(at), 2.0, "she walked away")
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		assert_ne(e.type, NoiseTypes.Type.FLARE_STRIKE)
		assert_ne(e.source_entity, 0, "nothing sounds from the candle")
