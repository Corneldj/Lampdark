extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-12: consume_part removes exactly n or none, across stacks; never a tool; a Hand is refused;
## a fit spends its parts only when it completes, and a cancelled fit leaves the belt unchanged.

const B = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _crew() -> Array:
	var s: Scenario = make({"seed": 941, "fixture": B.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	ann.brain = null
	bob.brain = null
	s.step(1)
	return [s, ann, bob]


func _give(s: Scenario, m: int, kind: ItemKinds.Kind, n: int) -> void:
	assert_true(s.run.inventory.give(s.run, m, s.run.inventory.world.make(kind, n)))


func test_exactly_n_or_none() -> void:
	var got: Array = _crew()
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var tp: ToolsParts = s.run.tools_parts
	_give(s, ann.entity_id, ItemKinds.Kind.FUSE, 3)
	_give(s, ann.entity_id, ItemKinds.Kind.FUSE, 2)
	_give(s, ann.entity_id, ItemKinds.Kind.WIRE_CUTTERS, 1)
	assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE), 5, "five fuses over two slots")
	assert_false(tp.consume_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE, 6), "six: refused")
	assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE), 5, "and nothing taken")
	assert_true(tp.consume_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE, 4))
	assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE), 1, "exactly four taken")
	assert_false(tp.consume_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE, 0), "none is no spend")
	assert_false(tp.consume_part(s.run, ann.entity_id, ItemKinds.Kind.WIRE_CUTTERS, 1), "a tool is never a part")
	assert_eq(s.run.inventory.hands_of(ann.entity_id).count_of(ItemKinds.Kind.WIRE_CUTTERS), 1)


func test_a_hand_is_refused() -> void:
	var got: Array = _crew()
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var bob: MinerHandle = got[2]
	var tp: ToolsParts = s.run.tools_parts
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == bob.entity_id
	for m: int in [ann.entity_id, bob.entity_id]:
		_give(s, m, ItemKinds.Kind.SPANNER, 1)
		_give(s, m, ItemKinds.Kind.MAGNETO, 1)
	for kind: ItemKinds.Kind in ToolsParts.TOOLS:
		if kind == ItemKinds.Kind.SPANNER:
			assert_eq(tp.tool_holder(s.run, [bob.entity_id, ann.entity_id], kind), ann.entity_id, "the Hand's spanner is passed over")
		assert_false(tp.has_tool(s.run, [bob.entity_id], kind), "a Hand never uses a tool")
	assert_false(tp.consume_part(s.run, bob.entity_id, ItemKinds.Kind.MAGNETO, 1), "nor fits a part")
	assert_null(tp.fit_action(s.run, bob.entity_id, ItemKinds.Kind.MAGNETO, 1, 2.0, InputRecord.HOLD_INTERACT))
	assert_eq(tp.any_tool(s.run, bob.entity_id), ItemKinds.Kind.NONE)
	assert_true(tp.consume_part(s.run, ann.entity_id, ItemKinds.Kind.MAGNETO, 1), "the miner may")


func test_spent_on_completion_never_on_a_cancel() -> void:
	var got: Array = _crew()
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var tp: ToolsParts = s.run.tools_parts
	_give(s, ann.entity_id, ItemKinds.Kind.ROPE_CLAMP, 4)
	var fitted: Array[int] = []
	var act: TimedAction = tp.fit_action(s.run, ann.entity_id, ItemKinds.Kind.ROPE_CLAMP, 4, 2.0, InputRecord.HOLD_INTERACT,
		func() -> void: fitted.append(s.run.tick))
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 20)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, act))
	s.step(30)
	assert_eq(fitted.size(), 0, "let go at 1 s of 2")
	assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.ROPE_CLAMP), 4, "a cancelled fit spends nothing")
	act = tp.fit_action(s.run, ann.entity_id, ItemKinds.Kind.ROPE_CLAMP, 4, 2.0, InputRecord.HOLD_INTERACT,
		func() -> void: fitted.append(s.run.tick))
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 50)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, act))
	s.step(45)
	assert_eq(fitted.size(), 1, "fitted")
	assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.ROPE_CLAMP), 0, "all four spent on completion")
