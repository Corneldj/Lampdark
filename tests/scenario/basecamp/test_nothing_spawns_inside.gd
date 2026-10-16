extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-01's run-start check: inside base camp lie only miners, the first lamp and Bess. It passes
## on a fresh base camp for every rotation over many seeds (GEN-14 runs it over full generation),
## and catches anything else inside.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_check() -> void:
	for side: int in 4:
		var s: Scenario = make({"seed": 10 + side, "fixture": C.scenario_fixture()})
		var camp: BaseCampState = C.load_camp(s, side)
		var deck: Rect2i = Basecamp.deck_rect(C.SEED, side)
		s.add_miner("ann", deck.position)
		s.run.registry.create(WorldIds.EntityKind.BESS, Vector2(deck.position) + Vector2(1.5, 1.5))
		s.step(1)
		assert_eq(camp.run_start_check(s.run), [] as Array[String], "rotation %d: only miners, the lamp, Bess and the levers" % side)
		s.run.registry.create(WorldIds.EntityKind.ITEM, Vector2(deck.position) + Vector2(2.5, 2.5))
		assert_eq(camp.run_start_check(s.run).size(), 1, "an item placed inside is caught")


func test_many_seeds() -> void:
	var sides: Dictionary = {}
	for seed_value: int in range(1, 401):
		var side: int = Basecamp.blind_side(seed_value)
		sides[side] = true
		var inside: Dictionary = Basecamp.inside_tiles(seed_value)
		assert_eq(inside.size(), 192)
	assert_eq(sides.size(), 4)
