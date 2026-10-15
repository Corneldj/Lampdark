extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-12 (§8.2): "spring it" is offered only beside a known trap (identified at 0.30, or felt), never
## on its tile, with any tool on the belt; it takes 20 ticks of interact, calls the HAZ stub once and
## keeps the tool. A Hand is never offered it; an unseen, unfelt trap is not known.

const B = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _room(lit: bool) -> Array:
	var s: Scenario = make({"seed": 951, "fixture": B.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	if lit:
		B.light(s)
	s.step(1)
	var trap: int = s.run.registry.create(WorldIds.EntityKind.TRAP, Vector2(s.fixture.spot("a") + Vector2i(1, 0)) + Vector2(0.5, 0.5)).id
	s.step(2)
	return [s, ann, trap]


func _offered(s: Scenario, ann: MinerHandle) -> bool:
	var t: Dictionary = s.run.inventory.targets.pick(s.run, ann.entity_id, ann.slot, s.run.inventory.world)
	return not t.is_empty() and StringName(str(t["kind"])) == &"spring_trap"


func test_offered_beside_a_known_trap_with_any_tool() -> void:
	var got: Array = _room(true)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var trap: int = got[2]
	assert_false(_offered(s, ann), "no tool: not offered")
	for kind: ItemKinds.Kind in ToolsParts.TOOLS:
		var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
		for i: int in h.slots.size():
			h.slots[i] = null
		assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(kind)))
		s.step(1)
		assert_true(_offered(s, ann), "%s: offered" % ItemKinds.text_key(kind))
	# On its tile: never.
	var me: SimEntity = s.run.registry.get_entity(ann.entity_id)
	var saved: Vector2 = me.position
	s.run.registry.get_entity(trap).position = saved
	assert_false(s.run.tools_parts.can_spring(s.run, ann.entity_id, ann.slot, trap), "not on its tile")
	s.run.registry.get_entity(trap).position = saved + Vector2(1.0, 0.0)
	assert_true(s.run.tools_parts.can_spring(s.run, ann.entity_id, ann.slot, trap))
	s.run.tools_parts.trap_is_set = func(_r: RunState, _t: int) -> bool: return false
	assert_false(_offered(s, ann), "a sprung trap is no longer offered")


func test_twenty_ticks_one_call_tool_kept() -> void:
	var got: Array = _room(true)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var trap: int = got[2]
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.HAMMER)))
	s.step(1)
	var pressed: int = s.run.tick + 1
	ann.at(pressed).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(35)
	var tp: ToolsParts = s.run.tools_parts
	assert_eq(tp.stub_springs.size(), 1, "the HAZ stub called once")
	assert_eq(int(Variants.number(tp.stub_springs[0]["trap"])), trap)
	assert_eq(int(Variants.number(tp.stub_springs[0]["by"])), ann.entity_id)
	assert_eq(tp.spring_action(s.run, ann.entity_id, ann.slot, trap).ticks_needed, 20, "20 ticks of interact")
	# Started on the tick after the press (it runs after MNR-04's inventory, like the cupboard).
	assert_eq(int(Variants.number(tp.springs[0]["tick"])) - pressed, 21, "done 20 ticks after it started")
	assert_eq(s.run.inventory.hands_of(ann.entity_id).count_of(ItemKinds.Kind.HAMMER), 1, "the tool kept")


func test_not_known_in_the_dark_and_never_a_hand() -> void:
	var got: Array = _room(false)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.SPANNER)))
	s.step(2)
	assert_false(_offered(s, ann), "unseen and unfelt: not known")
	B.light(s)
	s.step(2)
	assert_true(_offered(s, ann), "seen at 0.30")
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == ann.entity_id
	assert_false(_offered(s, ann), "a Hand is never offered it")
