extends "res://tests/scenario/kit/scenario_test.gd"
## UI-03: the hatch's '[ticking, close]' shows, with its arc, only for a miner it reached: within
## 3 tiles of the host (CRT-06's local emitter; its radius stood in here until CRT-06).

const F = preload("res://tests/scenario/ui/caption_feed.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_only_within_three_tiles() -> void:
	var s: Scenario = make({"seed": 311, "fixture": "test"})
	var host: Vector2i = Vector2i(2, 1)
	var ann: MinerHandle = s.add_miner("ann", host + Vector2i(2, 0))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(5, 13))
	var fa: F = F.new(ann, self)
	var fb: F = F.new(bob, self)
	s.on_tick = func(sc: Scenario) -> void:
		fa.pump(sc)
		fb.pump(sc)
	s.step(5)
	s.run.audio.local(s.run, LocalSounds.Type.HATCH_TICKING, host, 3.0, 6.0, 1.0)
	s.step(6)
	assert_eq(fa.texts(), ["[ticking, close]"] as Array[String], "within 3 tiles: captioned")
	var b: Variant = fa.system.history[0]["bearing"]
	assert_true(b != null, "with its arc")
	assert_eq(fb.texts(), [] as Array[String], "beyond 3 tiles: not delivered, not captioned")
	fa.free_nodes()
	fb.free_nodes()
