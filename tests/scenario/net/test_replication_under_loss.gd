extends "res://tests/scenario/kit/scenario_test.gd"
## NET-04: with 2% loss at 120 ms RTT every geometry record and every audio event arrives, late
## at worst: the client ends holding exactly what the server last sent it, and every event.

const N = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_nothing_is_dropped() -> void:
	var s: Scenario = make({"seed": 51, "fixture": "test"})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(2, 1))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(5, 13))
	ann.link(120, 2.0)
	var lamp_a: int = N.lamp(s, Vector2(2.5, 1.5), 5.5, ann.entity_id)
	var lamp_b: int = N.lamp(s, Vector2(5.5, 13.5), 5.5, bob.entity_id)
	ann.brain = load("res://tools/bots/brain.gd").call(&"create", "wander", 7)
	bob.brain = load("res://tools/bots/brain.gd").call(&"create", "wander", 8)
	s.on_tick = func(sc: Scenario) -> void:
		var ea: SimEntity = sc.run.registry.get_entity(ann.entity_id)
		var eb: SimEntity = sc.run.registry.get_entity(bob.entity_id)
		sc.run.light.grid.update_point(lamp_a, ea.position, 5.5, 1.0)
		sc.run.light.grid.update_point(lamp_b, eb.position, 5.5, 1.0)
	s.step(600)
	# Quiet ending: inputs stop, so the last frames settle.
	ann.brain = null
	bob.brain = null
	s.step(60)
	var heard: Array = s.run.noise.event_log.filter(func(e: NoiseSystem.Event) -> bool:
		return e.deliveries.any(func(d: Variant) -> bool: return int(Variants.number(Variants.dict(d)["listener"])) == ann.slot))
	var got: Array[Dictionary] = s.client(ann).audio_events(0, 100000)
	gut.p("events delivered to Ann: %d; received: %d; frames lost down: %d" % [heard.size(), got.size(), ann.link_filter.dropped_down])
	assert_gt(ann.link_filter.dropped_down, 5, "the link really lost frames")
	assert_eq(got.size(), heard.size(), "every audio event arrived")
	var stats: Dictionary = s.run.replication.native.last_stats(ann.slot)
	assert_eq(int(Variants.number(stats["geometry_pending"])), 0)
	var view: ReceivedView = s.client(ann).records_at(s.run.tick)
	var frame: Dictionary = s.run.vision.frame_for(ann.slot)
	var xs: PackedInt32Array = frame["tiles"]["x"]
	var ys: PackedInt32Array = frame["tiles"]["y"]
	for i: int in xs.size():
		assert_true(view.geometry.has(Vector2i(xs[i], ys[i])), "seen tile %d,%d has its geometry" % [xs[i], ys[i]])
