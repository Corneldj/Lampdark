extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-09: a public lone human among three Hands (stand-ins until MOD-08): crew count 1, the
## self-rescue offered, heard by a conscious Hand within 4 tiles (not 5). When a second human joins,
## every substitution switches off in the same tick, and a pending self-revive is cancelled unspent.

const LW = preload("res://tests/unit/rescue/lone_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_lone_human_among_hands() -> void:
	var w: Array = LW.crew(make, 941, ["ann", "h1", "h2", "h3"], ServerConfig.Mode.PUBLIC)
	var s: Scenario = w[0]
	var crew: Array[MinerHandle] = []
	var handles: Array = w[1]
	crew.assign(handles)
	var ann: MinerHandle = crew[0]
	var hands: Dictionary = {crew[1].entity_id: true, crew[2].entity_id: true, crew[3].entity_id: true}
	LW.hands(s, hands)
	s.step(2)
	assert_true(AloneRules.is_alone(s.run, ann.entity_id), "the only human: a lone human")
	assert_eq(s.run.crew.count, Tuning.i(&"director.lone_human_crew_count"), "crew count 1")
	assert_eq(Tuning.i(&"director.lone_human_crew_count"), 1)
	assert_eq(s.run.lone.active_substitutions(s.run, ann.entity_id), ["heard_by_companion", "self_rescue", "self_revive", "solo_jobs"] as Array[String])
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 0, 400)
	var g: GrabHold = s.run.holds.grabs[id]
	assert_true(SelfRescue.offered(s.run, g), "the self-rescue offered")
	s.run.holds.end_grab(s.run, id, GrabHold.Outcome.BROKEN)
	s.step(2)
	# Heard by a Hand within 4 tiles: h1 stands 2 tiles off; then every Hand 5 tiles or more off.
	assert_true(ServerSystems.lone_heard_by_hand(s.run, ann.slot), "a Hand 2 tiles off hears her")
	for h: MinerHandle in [crew[1], crew[2], crew[3]]:
		s.run.movement.place(s.run, h.entity_id, Vector2(12.5, 4.5))
	s.step(1)
	assert_false(ServerSystems.lone_heard_by_hand(s.run, ann.slot), "none within 4 tiles: unheard")


func test_a_second_human_ends_it_in_the_same_tick() -> void:
	var w: Array = LW.crew(make, 942, ["ann", "h1", "h2", "h3"], ServerConfig.Mode.PUBLIC)
	var s: Scenario = w[0]
	var crew: Array[MinerHandle] = []
	var handles: Array = w[1]
	crew.assign(handles)
	var ann: MinerHandle = crew[0]
	var hands: Dictionary = {crew[1].entity_id: true, crew[2].entity_id: true, crew[3].entity_id: true}
	LW.hands(s, hands)
	s.step(2)
	assert_eq(s.run.lone.active_substitutions(s.run, ann.entity_id).size(), 4, "alone: all on (LFT-04's solo jobs among them)")
	# A human takes over h1 (a rejoin): two conscious humans.
	hands.erase(crew[1].entity_id)
	assert_eq(s.run.lone.active_substitutions(s.run, ann.entity_id), [] as Array[String], "all off at once, for her")
	assert_eq(s.run.lone.active_substitutions(s.run, crew[1].entity_id), [] as Array[String], "and for him")
	s.step(1)
	assert_ne(s.run.crew.count, Tuning.i(&"director.lone_human_crew_count"), "the crew count is a crew's again")
	# Back to one human, who falls alone: armed; then a human again, conscious: cancelled, unspent.
	hands[crew[1].entity_id] = true
	s.step(1)
	LW.fall(s, ann)
	assert_true(s.run.self_revive.self_revive_pending(ann.entity_id), "she fell alone: armed")
	hands.erase(crew[1].entity_id)
	s.step(1)
	assert_false(s.run.self_revive.self_revive_pending(ann.entity_id), "a conscious human in the mine: cancelled")
	assert_true(s.run.self_revive.self_revive_available(ann.entity_id), "unspent")
