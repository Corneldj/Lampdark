extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-05: Bob, unlit, walks out of Ann's lamplight and so out of her sight. The client frame after the server stops sending him draws
## nothing of him: no ghost, no fade, no last-known marker. Every frame, what is drawn is exactly what
## the latest view holds.

const FW = preload("res://tests/scenario/vis/flame_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_gone_on_the_next_frame() -> void:
	var s: Scenario = make({"seed": 82, "fixture": FW.hall(40)})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(5, 3), {"facing_deg": 0.0})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(8, 3))
	ann.at(0).face(0.0)
	s.step(1)
	L.lit_in_hand(s, ann)
	s.step(4)
	bob.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 120)
	var drawn: DrawnSet = DrawnSet.new()
	var had: bool = false
	var lost_at: int = -1
	var mismatches: Array[String] = []
	for _i: int in 130:
		s.step(1)
		var view: ReceivedView = ann.connection.view
		var at: Vector2 = s.run.registry.get_entity(ann.entity_id).position
		drawn.build(view, {"position": at, "facing": 0, "lamp": {}}, ann.connection.last_input_ack, -1)
		var expected: Array[int] = []
		for raw: Variant in view.entities.keys():
			var level: int = int(Variants.number(Variants.dict(view.entities[raw])["level"]))
			if level == 1 or level == 2:
				expected.append(int(Variants.number(raw)))
		expected.sort()
		if drawn.entities != expected:
			mismatches.append("tick %d" % s.run.tick)
		if not drawn.entities.is_empty():
			had = true
		elif had and lost_at < 0:
			lost_at = s.run.tick
	assert_true(had, "Bob was drawn")
	assert_gt(lost_at, 0, "and then not: he left her sight")
	assert_eq(mismatches, [] as Array[String], "every frame draws exactly what the view holds")
