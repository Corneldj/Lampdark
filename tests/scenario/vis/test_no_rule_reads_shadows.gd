extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-09: no rule reads the shadows. The same run with shadows on and off has identical light
## values, seen sets and state hashes; only the frames' shading bits differ.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _run(shadows: bool) -> Array:
	var s: Scenario = make({"seed": 95, "fixture": A.hall()})
	s.run.vision.native.set_shadow_params({"enabled": shadows})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(5, 3), {"facing_deg": 0.0})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(8, 3), {"facing_deg": 180.0})
	preload("res://tests/unit/mnr/lamp_world.gd").lit_in_hand(s, ann)
	preload("res://tests/unit/mnr/lamp_world.gd").lit_in_hand(s, bob)
	ann.walk_to(Vector2i(14, 2))
	var hashes: Array[String] = []
	var seen: Array = []
	var shaded: int = 0
	for _i: int in 40:
		s.step(1)
		hashes.append(s.run.state_hash())
		var f: Dictionary = s.run.vision.frame_for(ann.slot)
		var tiles: Dictionary = Variants.dict(f.get("tiles", {}))
		seen.append([tiles.get("x"), tiles.get("y"), tiles.get("light"), f.get("tokens"), f.get("identified")])
		var decals: PackedByteArray = tiles.get("decals", PackedByteArray())
		for d: int in decals:
			if d >> 6 > 0:
				shaded += 1
	return [hashes, seen, shaded]


func test_identical_with_shadows_on_and_off() -> void:
	var on: Array = _run(true)
	var off: Array = _run(false)
	assert_gt(int(Variants.number(on[2])), 0, "shadows were drawn")
	assert_eq(int(Variants.number(off[2])), 0, "and none when off")
	var on_hashes: Array = on[0]
	var off_hashes: Array = off[0]
	var on_seen: Array = on[1]
	var off_seen: Array = off[1]
	assert_eq(on_hashes, off_hashes, "state hashes identical tick for tick")
	assert_eq(on_seen, off_seen, "light values and seen sets identical")
