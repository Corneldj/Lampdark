extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-15 with VIS-10, under NET-08's audit: a client receives a drag's trail tile only when that
## tile is in its seen set lit to 0.12 or more; dark, at 0.11 or behind it, never.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _decal(s: Scenario, slot: int, t: Vector2i) -> int:
	var f: Dictionary = s.run.vision.frame_for(slot)
	var tiles: Dictionary = f["tiles"]
	var xs: PackedInt32Array = tiles["x"]
	var ys: PackedInt32Array = tiles["y"]
	var decals: PackedByteArray = tiles["decals"]
	for i: int in xs.size():
		if xs[i] == t.x and ys[i] == t.y:
			return decals[i]
	return -1


func test_a_trail_is_seen_only_lit_to_0_12() -> void:
	var s: Scenario = make({"seed": 1571, "fixture": H.road(), "overrides": H.W.ON})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var h: H = H.new()
	h.build(s, 40, 37, 95)
	assert_true(h.until_state(&"keep", 1600))
	var bob: MinerHandle = H.W.miner(s, "bob", Vector2i(50, 2), 0.0)
	var lit: Vector2i = Vector2i(53, 2)
	var dim: Vector2i = Vector2i(55, 2)
	var dark: Vector2i = Vector2i(57, 2)
	var behind: Vector2i = Vector2i(46, 2)
	s.run.light.grid.add_area("t12", LbLightGrid.COLOUR_AMBER, 0, 0.12, [lit])
	s.run.light.grid.add_area("t11", LbLightGrid.COLOUR_AMBER, 0, 0.11, [dim])
	s.run.light.grid.add_area("tb", LbLightGrid.COLOUR_AMBER, 0, 0.5, [behind])
	s.step(3)
	for t: Vector2i in [lit, dim, dark, behind]:
		assert_eq(s.run.stythe_lair.trail.direction_at(t), 0, "%s is on the trail" % t)
	var bits: int = _decal(s, bob.slot, lit)
	assert_eq(bits & TileBits.DECAL_BLOOD, TileBits.DECAL_BLOOD, "seen at 0.12: its blood")
	assert_eq(TrailDecal.direction_of(bits), 0, "pointing to the lair")
	assert_eq(_decal(s, bob.slot, dim), -1, "at 0.11 nothing")
	assert_eq(_decal(s, bob.slot, dark), -1, "dark, nothing")
	assert_eq(_decal(s, bob.slot, behind), -1, "behind him, nothing")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p(str(v))
	assert_eq(audit.violation_count, 0, "no trail tile sent unseen or below 0.12")
