extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-09 (Gameplay §5.8): a body in a viewer's blind area, lit by the viewer's own lamp set down
## behind it, shades tiles inside the viewer's cone, while the body itself is never sent.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_shadow_falls_into_the_cone_from_behind() -> void:
	var s: Scenario = make({"seed": 94, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(12, 3), {"facing_deg": 0.0})
	var body: MinerHandle = s.add_miner("body", Vector2i(10, 3), {"facing_deg": 0.0})
	# Ann's lamp, set down west of the body: the body is lit from behind, Ann faces east.
	var lamp: GauzeLamp = s.run.lamps.create(s.run, 1.0, 3, true, LampRules.WICK_UP, Vector2(8.5, 3.5))
	assert_not_null(lamp)
	s.step(6)
	assert_gt(s.run.light.light_at(Vector2i(10, 3)), 0.3, "the body is lit to 0.30")
	var shaded: Array[Vector2i] = []
	for raw: Variant in ann.connection.view.tiles.keys():
		var t: Vector2i = raw
		var rec: PackedByteArray = ann.connection.view.tiles[t]
		if ShadowLayer.level_of(rec[2]) > 0:
			shaded.append(t)
	assert_true(shaded.has(Vector2i(13, 3)) or shaded.has(Vector2i(14, 3)), "shading east of Ann, in her cone: %s" % [shaded])
	for t: Vector2i in shaded:
		assert_gte(t.x, 12, "only inside the cone: east of Ann, or her own tile (the apex)")
	var token: int = s.run.replication.native.token_of(ann.slot, body.entity_id)
	assert_false(ann.connection.view.entities.has(token) and token != 0, "the body behind her is never sent")
	assert_eq(ann.connection.view.entities.size(), 0, "nothing of it reaches her")
