extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-12 through LFT-05's Power job, under NET-08's audit: Bob clears the burnt links with the wire
## cutters on his belt, then Ann fits three fuses at the board, each spent only when its fit
## completes; the cutters are kept. A spare fuse lying in the dark never reaches a client.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_three_fuses_fitted_the_cutters_kept() -> void:
	var s: Scenario = make({"seed": 981, "fixture": "test"})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	# The board in the corridor between them; the trip and the switch down the side roads.
	s.run.power.set_anchors(Vector2i(3, 1), Vector2i(1, 4), Vector2i(18, 4))
	var ann: MinerHandle = s.add_miner("ann", Vector2i(2, 1), {"facing_deg": 0.0})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(4, 1), {"facing_deg": 180.0})
	ann.brain = null
	bob.brain = null
	ann.at(s.run.tick).face(0.0)
	bob.at(s.run.tick).face(180.0)
	s.step(2)
	var w: ItemWorld = s.run.inventory.world
	assert_true(s.run.inventory.give(s.run, bob.entity_id, w.make(ItemKinds.Kind.WIRE_CUTTERS)))
	assert_true(s.run.inventory.give(s.run, ann.entity_id, w.make(ItemKinds.Kind.FUSE, 3)))
	w.put(s.run, w.make(ItemKinds.Kind.FUSE, 2), Vector2(14.5, 1.5)) # a spare, lying in the dark
	var tp: ToolsParts = s.run.tools_parts
	var power: PowerJob = s.run.power
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 86)
	s.step(90)
	assert_true(power.links_cleared, "Bob's cutters cleared the links")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 20)
	s.step(24)
	assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE), 3, "nothing spent mid-fit")
	for i: int in 3:
		ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 46)
		s.step(50)
	assert_eq(power.fuses_fitted, 3, "three fuses in")
	assert_eq(tp.count_part(s.run, ann.entity_id, ItemKinds.Kind.FUSE), 0, "three fuses spent")
	assert_eq(s.run.inventory.hands_of(bob.entity_id).count_of(ItemKinds.Kind.WIRE_CUTTERS), 1, "the cutters kept")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "no audit violation: the dark fuse never sent")
