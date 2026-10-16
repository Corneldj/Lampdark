extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-09 with CRT-14 and CRT-15: a solo miner dragged past their 20 s falls on the way, and their
## self-revive's count waits while the drag holds the body; it starts in full when the Stythe lays
## them in the lair, and they come round there, Hurt and unlit (the drag dropped the lamp).

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_count_waits_for_the_drag_and_they_come_round_in_the_lair() -> void:
	var s: Scenario = make({"seed": 961, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 40, 37, 95)
	var ann: int = h.ann.entity_id
	assert_true(h.until_state(&"drag", 300))
	assert_true(s.run_until(func(_sv: Variant) -> bool: return s.run.miner_state.life(ann) == MinerTransitions.Life.UNCONSCIOUS, 600),
		"she falls on the way")
	assert_true(s.run.self_revive.self_revive_pending(ann), "armed: solo")
	s.step(5)
	assert_true(Variants.flag(s.run.self_revive.status_of(s.run, ann).get("waiting", false)), "waiting while the drag holds her")
	assert_true(h.until_state(&"keep", 1600), "laid in the lair")
	var laid: int = s.run.tick
	var lair_tile: Vector2i = s.run.registry.get_entity(ann).tile()
	assert_true(s.run_until(func(_sv: Variant) -> bool: return s.run.miner_state.life(ann) == MinerTransitions.Life.UPRIGHT, 700),
		"she comes round")
	var after: int = s.run.tick - laid
	gut.p("laid at %d, up %d ticks later" % [laid, after])
	assert_gte(after, 598, "the full count after the drag ended")
	assert_eq(s.run.registry.get_entity(ann).tile(), lair_tile, "in the lair")
	assert_true(s.run.miner_state.miner(ann).overlays.hurt(s.run.tick), "Hurt")
	var hb: HandsAndBelt = s.run.inventory.hands_of(ann)
	assert_null(hb.lamp_hand, "unlit: the drag dropped her lamp at the grab point")
