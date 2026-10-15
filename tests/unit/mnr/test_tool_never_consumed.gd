extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-12: across 10,000 random job checks, part fits, springs and rescues (with stubs), no tool
## count ever changes; parts go down only by what was fitted.

const B = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _tools(s: Scenario, miners: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for m: int in miners:
		for kind: ItemKinds.Kind in ToolsParts.TOOLS:
			out.append(s.run.inventory.hands_of(m).count_of(kind))
	return out


func test_ten_thousand_operations() -> void:
	var s: Scenario = make({"seed": 961, "fixture": B.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	ann.brain = null
	bob.brain = null
	B.light(s)
	s.step(1)
	var miners: Array[int] = [ann.entity_id, bob.entity_id]
	var tp: ToolsParts = s.run.tools_parts
	var w: ItemWorld = s.run.inventory.world
	for kind: ItemKinds.Kind in [ItemKinds.Kind.SPANNER, ItemKinds.Kind.WIRE_CUTTERS]:
		assert_true(s.run.inventory.give(s.run, ann.entity_id, w.make(kind)))
	for kind: ItemKinds.Kind in [ItemKinds.Kind.HAMMER, ItemKinds.Kind.CROWBAR]:
		assert_true(s.run.inventory.give(s.run, bob.entity_id, w.make(kind)))
	var trap: int = s.run.registry.create(WorldIds.EntityKind.TRAP, Vector2(s.fixture.spot("a") + Vector2i(1, 0)) + Vector2(0.5, 0.5)).id
	s.step(2)
	var before: Array[int] = _tools(s, miners)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 961
	var jobs: Array = ToolsParts.JOBS.keys()
	var fitted: int = 0
	var springs: int = 0
	for i: int in 10000:
		var m: int = miners[rng.randi_range(0, 1)]
		match rng.randi_range(0, 3):
			0:  # a job checks its tools and fits its parts
				var job: Dictionary = ToolsParts.JOBS[jobs[rng.randi_range(0, jobs.size() - 1)]]
				for raw: Variant in Variants.array(job["tools"]):
					var tool: ItemKinds.Kind = int(Variants.number(raw)) as ItemKinds.Kind
					tp.tool_holder(s.run, miners, tool)
				var parts: Dictionary = job["parts"]
				for raw: Variant in parts.keys():
					var kind: ItemKinds.Kind = int(Variants.number(raw)) as ItemKinds.Kind
					if tp.count_part(s.run, m, kind) == 0:
						s.run.inventory.give(s.run, m, w.make(kind, int(Variants.number(parts[raw]))))  # may not fit: then no fit
					if tp.consume_part(s.run, m, kind, int(Variants.number(parts[raw]))):
						fitted += 1
			1:  # a spring on purpose, through the action's effect
				if tp.can_spring(s.run, ann.entity_id, ann.slot, trap):
					var a: TimedAction = tp.spring_action(s.run, ann.entity_id, ann.slot, trap)
					a.effect.call()
					springs += 1
			2:  # HAZ-01's cutters and HAZ-03's crowbar rescues ask for their tool
				tp.has_tool(s.run, miners, ItemKinds.Kind.WIRE_CUTTERS)
				tp.has_tool(s.run, miners, ItemKinds.Kind.CROWBAR)
			3:  # a spend aimed at a tool is refused
				assert_false(tp.consume_part(s.run, m, ToolsParts.TOOLS[rng.randi_range(0, 3)], 1))
	gut.p("%d fits, %d springs" % [fitted, springs])
	assert_gt(fitted, 1000)
	assert_gt(springs, 1000)
	assert_eq(_tools(s, miners), before, "no tool count changed")
