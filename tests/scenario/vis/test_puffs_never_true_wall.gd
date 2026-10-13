extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-09 with CRT-09: a hunting Tapper's taps puff only at its tapping points, never at its true
## wall. The puffs come from the Tapper's own `tapped` signal (its three false points).

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_puffs_at_the_points_only() -> void:
	var s: Scenario = make({"seed": 96, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 3), {"facing_deg": 90.0})
	ann.at(0).face(90.0)  # south, toward the bottom wall
	preload("res://tests/unit/mnr/lamp_world.gd").lit_in_hand(s, ann)
	s.step(4)
	s.place_creature(WorldIds.EntityKind.TAPPER, Vector2i(24, 1))
	var t: Tapper = s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER) as Tapper
	assert_not_null(t)
	s.step(3)
	var true_face: Vector2i = t.tile(s.run)
	var points: Array[Vector2i] = [Vector2i(9, 0), Vector2i(11, 0), Vector2i(10, 6)]
	t.tapped.emit(points, points)
	s.step(3)
	var puffs: Array[Vector2] = []
	for e: Dictionary in ann.connection.events:
		if int(Variants.number(e["type"])) == VisualEvents.Type.PUFF:
			var at: Vector2 = e["apparent"]
			puffs.append(at)
	assert_gt(puffs.size(), 0, "the tap puffed where Ann sees")
	for p: Vector2 in puffs:
		assert_true(points.has(Vector2i(floori(p.x), floori(p.y))), "only at a tapping point")
		assert_ne(Vector2i(floori(p.x), floori(p.y)), true_face, "never the true wall")
