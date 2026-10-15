extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-16, under NET-08's audit: each shot gives one 40 np event, a muzzle_flash source of peak 1.0
## and radius 6 for exactly 2 ticks, SND-04's deafen for the shooter and everyone within 3 tiles,
## and one shot_fired; the shooter's client learns nothing of what it hit.

const R = preload("res://tests/unit/mnr/revolver_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_one_shot_and_its_effects() -> void:
	var s: Scenario = make({"seed": 1241, "fixture": R.hall()})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(5, 2))
	var two: MinerHandle = R.miner(s, "two", Vector2i(7, 2), 180.0)
	var four: MinerHandle = R.miner(s, "four", Vector2i(5, 1) + Vector2i(4, 0), 180.0)
	s.step(2)
	R.armed(s, ann)
	R.aim(s, ann)
	s.step(3)
	var events_before: int = s.run.noise.event_log.size()
	var fired: Array[Vector2i] = []
	s.run.revolver.shot_fired.connect(func(t: Vector2i) -> void: fired.append(t))
	var flash_ticks: Array[int] = []
	var probe: Callable = func(sc: Scenario) -> void:
		for f: Dictionary in sc.run.revolver.flashes:
			var info: Dictionary = sc.run.light.grid.source_info(int(Variants.number(f["source"])))
			if not info.is_empty() and str(info["kind"]) == Shot.FLASH_KIND:
				flash_ticks.append(sc.run.tick)
				assert_eq(float(Variants.number(info["radius"])), 6.0, "radius 6")
				assert_eq(float(Variants.number(info["peak"])), 1.0, "peak 1.0")
	s.on_tick = probe
	R.trigger(s, ann, 90.0)  # straight down into the floor's far wall: nobody hit
	s.step(10)
	s.on_tick = Callable()
	var shots: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		if e.type == NoiseTypes.Type.SHOT:
			shots.append(e)
	assert_eq(shots.size(), 1, "one shot event")
	assert_eq(shots[0].level_np, 40.0, "40 np")
	assert_eq(flash_ticks.size(), 2, "the flash lasts exactly 2 ticks")
	assert_eq(fired.size(), 1, "one shot_fired")
	assert_true(s.run.deafen.is_deafened(ann.slot), "the shooter")
	assert_true(s.run.deafen.is_deafened(two.slot), "2 tiles off")
	assert_false(s.run.deafen.is_deafened(four.slot), "beyond 3 tiles")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p(str(v))
	assert_eq(audit.violation_count, 0, "no hit, miss or counter in any stream")
