extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §13.9, §10.5, §10.8, §6.4, §11.11): Hands are never company. A human with only
## Hands within 6 tiles is alone for the Pull; a human who is not a lone human, calling out beside a
## Hand, stays unheard, while a lone human calling within 4 tiles of one is heard. Each Hand is half
## a miner for crew count, rounded down (two humans and two Hands: 3), a lone human plays at 1 (one
## human and three Hands: 1), and Hands never prevent a wipe.

const HW = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_hands_are_no_company_for_the_pull() -> void:
	var s: Scenario = make({"seed": 4871, "fixture": HW.road(50)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a, 0.0)
	HW.human(s, "bob", a + Vector2i(40, 0), 180.0)
	HW.hand(s, a + Vector2i(2, 0), 4)
	HW.hand(s, a + Vector2i(3, 1), 3)
	s.step(10)
	var sizes: Dictionary = PullGroups.sizes(s.run, Draught.conscious_humans(s.run))
	assert_eq(int(Variants.number(sizes[ann.entity_id])), 1, "two Hands beside her: alone for the Pull")


func test_a_hand_hears_only_a_lone_human() -> void:
	# Friends: Bob conscious far off, so Ann is no lone human; her callout beside a Hand goes unheard.
	var s: Scenario = make({"seed": 4872, "fixture": HW.road(60)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a, 0.0)
	HW.human(s, "bob", a + Vector2i(55, 0), 180.0)
	HW.hand(s, a + Vector2i(2, 0), 4)
	s.step(100)
	var unheard: float = s.run.heard.unheard_seconds(ann.slot)
	ann.at(s.run.tick).callout("here", CalloutLines.TALK)
	s.step(40)
	assert_gt(s.run.heard.unheard_seconds(ann.slot), unheard, "a Hand is no teammate who hears")
	# Public: Ann is the only conscious human, a lone human, and a Hand within 4 tiles hears her.
	var p: Scenario = make({"seed": 4873, "fixture": HW.road(60), "mode": ServerConfig.Mode.PUBLIC})
	var pa: Vector2i = p.fixture.spot("a")
	var lone: MinerHandle = HW.human(p, "ann", pa, 0.0)
	HW.hand(p, pa + Vector2i(2, 0), 4)
	p.step(100)
	assert_gt(p.run.heard.unheard_seconds(lone.slot), 3.0)
	lone.at(p.run.tick).callout("here", CalloutLines.TALK)
	p.step(40)
	assert_lt(p.run.heard.unheard_seconds(lone.slot), 2.5, "a lone human is heard by a Hand within 4 tiles")


func test_crew_count_with_hands() -> void:
	var s: Scenario = make({"seed": 4874, "fixture": HW.road(60)})
	var a: Vector2i = s.fixture.spot("a")
	HW.human(s, "ann", a, 0.0)
	HW.human(s, "bob", a + Vector2i(1, 2), 0.0)
	HW.hand(s, a + Vector2i(4, 0), 4)
	HW.hand(s, a + Vector2i(4, 2), 3)
	s.step(3)
	assert_eq(s.run.crew.compute(s.run), 3, "two humans and two Hands: 2 + floor(2 x 0.5)")
	var p: Scenario = make({"seed": 4875, "fixture": HW.road(60), "mode": ServerConfig.Mode.PUBLIC})
	var pa: Vector2i = p.fixture.spot("a")
	HW.human(p, "ann", pa, 0.0)
	for i: int in 3:
		HW.hand(p, pa + Vector2i(3 + i, 1), 4 - i)
	p.step(3)
	assert_eq(p.run.crew.compute(p.run), 1, "a lone human and three Hands: 1")


func test_hands_never_prevent_a_wipe() -> void:
	var s: Scenario = make({"seed": 4876, "fixture": HW.road(60)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a, 0.0)
	var bob: MinerHandle = HW.human(s, "bob", a + Vector2i(1, 2), 0.0)
	# Three humans began, so no lone human's self-revive defers the wipe (RSC-09).
	var cid: MinerHandle = HW.human(s, "cid", a + Vector2i(1, 0), 0.0)
	HW.hand(s, a + Vector2i(4, 0), 4)
	HW.hand(s, a + Vector2i(4, 2), 3)
	s.step(3)
	assert_eq(RunOutcomes.counted(s.run), [ann.entity_id, bob.entity_id, cid.entity_id] as Array[int], "only the players count")
	for m: MinerHandle in [ann, bob, cid]:
		assert_true(s.run.falls.fall_unconscious(s.run, m.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(5)
	assert_true(s.run.outcomes.wiped, "two standing Hands do not prevent the wipe")
