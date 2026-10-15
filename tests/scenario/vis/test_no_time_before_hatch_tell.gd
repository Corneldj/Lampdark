extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-10 (§8.3): an infested miner's egg-glow reaches a teammate as a pale green-white light with
## nothing that carries time; only when CRT-06 raises the hatch tell does the hatch bit appear, and
## then the frames differ by that bit alone (no light value, seen set or token changes).

const B = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _records(s: Scenario, slot: int) -> Dictionary:
	var f: Dictionary = s.run.vision.frame_for(slot)
	var out: Dictionary = {}
	var xs: PackedInt32Array = f["tiles"]["x"]
	var ys: PackedInt32Array = f["tiles"]["y"]
	var lights: PackedByteArray = f["tiles"]["light"]
	var colours: PackedByteArray = f["tiles"]["colour"]
	for i: int in xs.size():
		out[Vector2i(xs[i], ys[i])] = Vector2i(lights[i], colours[i])
	return out


func test_only_the_hatch_bit_and_only_once_raised() -> void:
	var s: Scenario = make({"seed": 1012, "fixture": B.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	var host: MinerHandle = s.add_miner("host", s.fixture.spot("a") + Vector2i(3, 0))
	ann.brain = null
	host.brain = null
	s.step(1)
	var at: Vector2 = s.run.registry.get_entity(host.entity_id).position
	var glow: int = s.run.light.grid.add_point("egg_glow", LbLightGrid.COLOUR_EGG_GLOW, host.entity_id, 0,
		Tuning.f(&"moth.egg_glow_radius"), Tuning.f(&"moth.egg_glow_centre"), at, 0)
	s.step(2)
	var before: Dictionary = _records(s, ann.slot)
	var glowing: int = 0
	for raw: Variant in before.keys():
		var rec: Vector2i = before[raw]
		if rec.y & ~TileBits.COLOUR_HATCH_BIT == LbLightGrid.COLOUR_EGG_GLOW:
			glowing += 1
		assert_eq(rec.y & TileBits.COLOUR_HATCH_BIT, 0, "no hatch bit before the tell")
	assert_gt(glowing, 0, "the egg-glow reaches her")
	# The host in its own glow (0.2 at the centre): a pale token, never identified below 0.30.
	var f: Dictionary = s.run.vision.frame_for(ann.slot)
	var identified: PackedInt64Array = f["identified"]
	var sizes: PackedByteArray = f["tokens"]["size"]
	assert_false(identified.has(host.entity_id), "whose it is: not until lit to 0.30")
	assert_eq(sizes.size(), 1, "a miner-sized token in the dark")
	s.step(40)
	assert_eq(_records(s, ann.slot), before, "nothing changes with time before the tell")
	s.run.light.grid.set_flags(glow, LbLightGrid.FLAG_HATCH_TELL)
	s.step(2)
	var after: Dictionary = _records(s, ann.slot)
	assert_eq(after.keys(), before.keys(), "the same seen set")
	var hatched: int = 0
	for raw: Variant in after.keys():
		var a: Vector2i = after[raw]
		var b: Vector2i = before[raw]
		assert_eq(a.x, b.x, "the same light")
		assert_eq(a.y & ~TileBits.COLOUR_HATCH_BIT, b.y, "the same colour class")
		if (a.y & TileBits.COLOUR_HATCH_BIT) != 0:
			hatched += 1
			assert_eq(b.y, LbLightGrid.COLOUR_EGG_GLOW, "the bit only on egg-glow tiles")
	assert_eq(hatched, glowing, "every egg-glow tile carries it now")
