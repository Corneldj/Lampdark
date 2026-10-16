extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-09: a miner alone gets one self-revive a run: 30 s after falling they come round where they lie,
## Upright and Hurt. Never a second; never while a conscious human teammate is in the mine (who fell
## among others never arms one later); a kit's revive cancels it unspent; the own status carries its
## count for the status line's ring.

const LW = preload("res://tests/unit/rescue/lone_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_alone_they_come_round_after_the_count() -> void:
	var w: Array = LW.crew(make, 901, ["ann"])
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1][0]
	var count: int = roundi(Tuning.f(&"rescue.self_revive_delay_s") * Tuning.f(&"net.tick_hz"))
	assert_eq(count, 600)
	var fell: int = LW.fall(s, ann)
	assert_true(s.run.self_revive.self_revive_pending(ann.entity_id), "armed: a friends lobby of one")
	var at: Vector2i = s.run.registry.get_entity(ann.entity_id).tile()
	var st: Dictionary = OwnStatus.of(s.run, ann.entity_id)
	assert_ne(int(Variants.number(st["flags"])) & StatusWire.REVIVE_COUNTING, 0, "the status carries the count")
	assert_eq(int(Variants.number(st["revive_ticks"])), count)
	s.step(fell + count - 1 - s.run.tick)
	assert_eq(LW.life(s, ann), MinerTransitions.Life.UNCONSCIOUS, "still down a tick before")
	s.step(1)
	assert_eq(s.run.tick - fell, count)
	assert_eq(LW.life(s, ann), MinerTransitions.Life.UPRIGHT, "up at the count")
	assert_true(LW.hurt(s, ann), "Hurt")
	assert_eq(s.run.registry.get_entity(ann.entity_id).tile(), at, "where she lay")
	assert_false(s.run.self_revive.self_revive_available(ann.entity_id), "spent")
	var what: String = s.run.self_revive.events[0]["what"]
	assert_eq(what, "self_revived")
	s.step(3)
	assert_false(s.run.dark.fallen.has(ann.entity_id), "the Dark is over")


func test_never_a_second_self_revive() -> void:
	var w: Array = LW.crew(make, 902, ["ann"])
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1][0]
	LW.fall(s, ann)
	s.step(610)
	assert_eq(LW.life(s, ann), MinerTransitions.Life.UPRIGHT)
	var wipes: Array[int] = []
	s.run.self_revive.wiped.connect(func(_m: int, t: int) -> void: wipes.append(t))
	var fell: int = LW.fall(s, ann)
	assert_false(s.run.self_revive.self_revive_pending(ann.entity_id))
	assert_eq(wipes.size(), 1, "the second fall alone is the solo wipe")
	assert_eq(wipes[0], fell - 1, "on that tick")
	s.step(1500)
	assert_eq(LW.life(s, ann), MinerTransitions.Life.UNCONSCIOUS, "and nobody comes round")


func test_a_kits_revive_cancels_it_unspent() -> void:
	var w: Array = LW.crew(make, 903, ["ann"])
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1][0]
	LW.fall(s, ann)
	s.step(100)
	s.run.miner_state.revive(ann.entity_id, &"kit")
	s.step(1)
	assert_false(s.run.self_revive.self_revive_pending(ann.entity_id), "cancelled")
	assert_true(s.run.self_revive.self_revive_available(ann.entity_id), "unspent")
	LW.fall(s, ann)
	assert_true(s.run.self_revive.self_revive_pending(ann.entity_id), "the next fall arms it again")


func test_never_while_a_conscious_human_teammate_is_in_the_mine() -> void:
	var w: Array = LW.crew(make, 904, ["ann", "bob", "cat"])
	var s: Scenario = w[0]
	var crew: Array[MinerHandle] = []
	var handles: Array = w[1]
	crew.assign(handles)
	LW.fall(s, crew[0])
	assert_false(s.run.self_revive.self_revive_pending(crew[0].entity_id), "Ann fell among others")
	LW.fall(s, crew[1])
	LW.fall(s, crew[2])
	s.step(700)
	for h: MinerHandle in crew:
		assert_eq(LW.life(s, h), MinerTransitions.Life.UNCONSCIOUS, "%s stays down (a crew of three never plays the solo rules)" % h.name)
	assert_eq(s.run.self_revive.events.size(), 0)
