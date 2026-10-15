extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-12: an LFT-05 stub works the Power job through the tools-and-parts API, under NET-08's audit:
## the wire cutters on a participant's belt, three fuses spent only when the fit completes, the
## cutters kept. Fuses lying in the dark never reach a client.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_three_fuses_fitted_the_cutters_kept() -> void:
	var s: Scenario = make({"seed": 981, "fixture": "test"})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ann: MinerHandle = s.add_miner("ann", Vector2i(2, 1), {"facing_deg": 0.0})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(4, 1))
	ann.brain = null
	bob.brain = null
	s.step(2)
	var w: ItemWorld = s.run.inventory.world
	assert_true(s.run.inventory.give(s.run, bob.entity_id, w.make(ItemKinds.Kind.WIRE_CUTTERS)))
	assert_true(s.run.inventory.give(s.run, ann.entity_id, w.make(ItemKinds.Kind.FUSE, 3)))
	w.put(s.run, w.make(ItemKinds.Kind.FUSE, 2), Vector2(14.5, 1.5))  # a spare, lying in the dark
	var tp: ToolsParts = s.run.tools_parts
	# The stub: the Power job needs the cutters among its crew and three fuses from the fitter.
	var crew: Array = [ann.entity_id, bob.entity_id]
	var job: Dictionary = ToolsParts.JOBS[&"power"]
	var tool: ItemKinds.Kind = int(Variants.number(Variants.array(job["tools"])[0])) as ItemKinds.Kind
	assert_eq(tp.tool_holder(s.run, crew, tool), bob.entity_id, "Bob has the cutters")
	var powered: Array[int] = []
	var fit: TimedAction = tp.fit_action(s.run, ann.entity_id, ItemKinds.Kind.FUSE, 3, 3.0, InputRecord.HOLD_INTERACT,
		func() -> void: powered.append(s.run.tick))
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 70)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, fit))
	s.step(30)
	assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE), 3, "nothing spent mid-fit")
	s.step(40)
	assert_eq(powered.size(), 1, "the job's fit completed")
	assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE), 0, "three fuses spent")
	assert_eq(s.run.inventory.hands_of(bob.entity_id).count_of(ItemKinds.Kind.WIRE_CUTTERS), 1, "the cutters kept")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "no audit violation: the dark fuse never sent")
