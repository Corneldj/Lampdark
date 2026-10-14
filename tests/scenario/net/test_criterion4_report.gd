extends "res://tests/scenario/kit/scenario_test.gd"
## NET-12: a short criterion-4 run at 120 ms and 2% loss produces light-to-contents and about-turn
## samples, held geometry on the next frame, the tick cost (whole tick, visibility, Road Graph) at
## p99, bandwidth per bot with voice apart, and probes under 0.1 ms a frame. A planted 100 ms delay
## on margin records shows in the light probe. (Nightly: 30 minutes at 40, 120, 200 and 250 ms.)

const R = preload("res://tools/bots/probe_run.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_short_run_at_120() -> void:
	var r: Dictionary = R.run({"rtt_ms": 120, "loss": 0.02, "seconds": 20.0})
	var light: Dictionary = r["light_to_contents"]
	var turn: Dictionary = r["about_turn"]
	assert_gt(int(Variants.number(light["n"])), 10, "light-to-contents samples")
	assert_gt(int(Variants.number(turn["n"])), 10, "about-turn samples")
	assert_true(Variants.flag(r["light_pass"]), "light-to-contents p95 %s ms under 150" % light["p95"])
	assert_true(Variants.flag(r["held_pass"]), "held geometry on the next frame")
	var tc: Dictionary = r["tick_cost"]
	for key: String in ["tick", "visibility", "road_graph"]:
		assert_gt(int(Variants.number(Variants.dict(tc[key])["p99_us"])), 0, "%s p99 reported" % key)
	assert_lt(float(Variants.number(r["probe_cost_usec_per_frame_max"])), 100.0, "probes under 0.1 ms a frame")
	var bot: Dictionary = Variants.array(r["bots"])[0]
	assert_gt(float(Variants.number(Variants.dict(bot["down"])["game_kbps"])), 1.0)
	assert_gt(float(Variants.number(Variants.dict(bot["up"])["voice_kbps"])), 0.0, "voice counted apart")
	var md: String = R.markdown(r)
	assert_string_contains(md, "Criterion 4:")
	gut.p("120 ms: light p95 %s ms, about-turn p95 %s ms, criterion 4 %s" % [light["p95"], turn["p95"], "pass" if Variants.flag(r["criterion4_pass"]) else "FAIL"])


func test_planted_margin_delay_shows_in_the_probes() -> void:
	var clean: Dictionary = R.run({"rtt_ms": 120, "loss": 0.02, "seconds": 20.0})
	var planted: Dictionary = R.run({"rtt_ms": 120, "loss": 0.02, "seconds": 20.0, "plant_margin_delay_ms": 100.0})
	assert_true(Variants.flag(clean["criterion4_pass"]), "criterion 4 passes clean (NET-12's turn rate and band)")
	# With the turn band, the margin carries the about-turns: the planted delay shows there.
	var a: float = float(Variants.number(Variants.dict(clean["about_turn"])["p95"]))
	var b: float = float(Variants.number(Variants.dict(planted["about_turn"])["p95"]))
	assert_gte(b - a, 80.0, "the margin's 100 ms shows in the about-turn probe: %.0f ms to %.0f ms" % [a, b])
