extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-12 (§8.2, §5.5): in the dark a miner feels iron jaws beside her, then, the trap known by
## feel, springs it on purpose with a hammer: 20 ticks of interact, the HAZ stub called once, the
## hammer kept. Before the feel, the unseen trap is not offered.

const B = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_feel_the_jaws_then_spring_them() -> void:
	var s: Scenario = make({"seed": 982, "fixture": B.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	s.step(1)
	var trap: int = s.run.registry.create(WorldIds.EntityKind.TRAP, Vector2(s.fixture.spot("a") + Vector2i(1, 0)) + Vector2(0.5, 0.5)).id
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.HAMMER)))
	s.step(2)
	var tp: ToolsParts = s.run.tools_parts
	assert_false(tp.can_spring(s.run, ann.entity_id, ann.slot, trap), "unseen and unfelt: not known")
	# Feel: interact held, standing still.
	ann.at(s.run.tick + 1).hold(InputRecord.HOLD_INTERACT, 45)  # vision.feel_hold_s is 1.5 s
	s.step(50)
	var answer: Dictionary = s.run.feel.answers[s.run.feel.answers.size() - 1]
	assert_eq(str(answer["caption_key"]), "feel.iron_jaws", "she feels the jaws")
	assert_eq(tp.stub_springs.size(), 0, "feeling springs nothing")
	assert_true(tp.can_spring(s.run, ann.entity_id, ann.slot, trap), "known by feel")
	# Interact again: spring it.
	var pressed: int = s.run.tick + 1
	ann.at(pressed).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(35)
	assert_eq(tp.stub_springs.size(), 1, "sprung on purpose")
	assert_eq(int(Variants.number(tp.springs[0]["tool"])), ItemKinds.Kind.HAMMER)
	assert_eq(int(Variants.number(tp.springs[0]["tick"])) - pressed, 21, "20 ticks of interact")
	assert_eq(s.run.inventory.hands_of(ann.entity_id).count_of(ItemKinds.Kind.HAMMER), 1, "the hammer kept")
