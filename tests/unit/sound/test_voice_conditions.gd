extends "res://tests/scenario/kit/scenario_test.gd"
## SND-08's conditions feed: running or panting from MNR-02's voice-loss flag, a Stythe whose tell
## plays within voice.stythe_radius_tiles (straight line) of a point, deafness from SND-04, and the
## Fan's stub flag. A Stythe in Lurk or Shadow plays no tell, so CRT-13 feeds it nowhere.

const Sweep = preload("res://tools/bots/voice_loss_sweep.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _corridor() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(32), "#a" + ".".repeat(29) + "#", "#".repeat(32)]))


func test_running_follows_the_voice_loss_flag() -> void:
	var s: Scenario = make({"seed": 61, "fixture": _corridor()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(3)
	var c: VoiceConditions = s.run.voice.conditions
	assert_false(c.running(ann.slot), "standing: no loss")
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 6)
	s.step(4)
	assert_eq(c.running(ann.slot), s.run.movement.voice_loss_flag(ann.slot))
	assert_true(c.running(ann.slot), "running: the flag is set")
	assert_false(c.running(99), "no such miner: nothing")


func test_the_stythe_counts_only_while_its_tell_plays_and_within_the_radius() -> void:
	var c: VoiceConditions = VoiceConditions.new()
	var radius: float = Tuning.f(&"voice.stythe_radius_tiles")
	assert_false(c.near_stythe(Vector2(5.0, 5.0)), "the stub: no tell plays (a Lurk or Shadow Stythe feeds none)")
	c.stythe_tells = func() -> Array[Vector2]: return [Vector2(0.0, 0.0)] as Array[Vector2]
	assert_true(c.near_stythe(Vector2(radius, 0.0)), "on the radius")
	assert_true(c.near_stythe(Vector2(6.0, 8.0)), "a straight line, not a path: 10 tiles")
	assert_false(c.near_stythe(Vector2(radius + 0.1, 0.0)), "beyond it")


func test_deafness_and_the_fan() -> void:
	var s: Scenario = make({"seed": 62, "fixture": _corridor()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(2)
	var c: VoiceConditions = s.run.voice.conditions
	assert_false(c.deafened(ann.slot))
	s.run.deafen.deafen(s.run, ann.slot, 5.0)
	assert_true(c.deafened(ann.slot), "SND-04's deafness")
	s.step(roundi(5.0 * Tuning.f(&"net.tick_hz")) + 1)
	assert_false(c.deafened(ann.slot), "over after 5 s")
	assert_false(c.fan_surge_active, "the Fan's stub never surges by itself (SND-16)")


func test_the_sweep_reports_failed_utterances() -> void:
	var args: Dictionary = {"utterances": 100, "seed": 3}
	for key: StringName in [&"voice.clean_range_fraction", &"voice.edge_loss", &"voice.stythe_loss", &"voice.running_loss",
			&"voice.loss_run_min_frames", &"voice.loss_run_max_frames"]:
		args[String(key).trim_prefix("voice.")] = Tuning.f(key)
	var r: Dictionary = Sweep.sweep(args)
	var rows: Array = r["rows"]
	assert_eq(rows.size(), Sweep.DISTANCES.size() * Sweep.MIXES.size())
	var first: Dictionary = rows[0]
	assert_eq(str(first["mix"]), "clean")
	assert_almost_eq(float(Variants.number(first["kept"])), 1.0, 1e-9, "half range, no condition: every frame")
	assert_eq(float(Variants.number(first["failed"])), 0.0)
	var worst: Dictionary = rows.back()
	assert_almost_eq(float(Variants.number(worst["p"])), 0.64, 1e-9, "the edge, the Stythe and a run")
	assert_almost_eq(float(Variants.number(worst["kept"])), 0.36, 0.03, "about a third kept")
	assert_gt(float(Variants.number(worst["failed"])), 0.5, "most such utterances keep under half")
	assert_string_contains(Sweep.markdown(r), "| 1.0 |")
