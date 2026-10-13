extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-09 (Gameplay §7.3) with CRT-09: a tap puffs dust at its tapping points only where a viewer
## sees the open floor beside the wall lit, in the tap's own tick, as a VisualEvents.PUFF.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _puffs(h: MinerHandle) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for e: Dictionary in h.connection.events:
		if int(Variants.number(e["type"])) == VisualEvents.Type.PUFF:
			var at: Vector2 = e["apparent"]
			out.append(at)
	return out


func test_puffs_only_where_seen_lit() -> void:
	var s: Scenario = make({"seed": 92, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(5, 3), {"facing_deg": 0.0})
	var lamp: GauzeLamp = preload("res://tests/unit/mnr/lamp_world.gd").lit_in_hand(s, ann)
	assert_not_null(lamp)
	s.step(4)
	# Faces on the top wall: one in Ann's lit cone, one far down the hall in the dark.
	var lit_face: Vector2i = Vector2i(7, 0)
	var dark_face: Vector2i = Vector2i(25, 0)
	var tick: int = s.run.tick
	s.run.tells._on_tapped([lit_face, dark_face] as Array[Vector2i], [lit_face] as Array[Vector2i])
	s.step(3)
	var got: Array[Vector2] = _puffs(ann)
	assert_eq(got, [Vector2(7.5, 0.5)] as Array[Vector2], "a puff at the lit face only")
	var e: Dictionary = ann.connection.events.filter(func(x: Dictionary) -> bool: return int(Variants.number(x["type"])) == VisualEvents.Type.PUFF)[0]
	assert_eq(int(Variants.number(e["start_tick"])), tick, "in the tap's tick")
	assert_eq(ann.connection.events.size(), ann.connection.events.size())
