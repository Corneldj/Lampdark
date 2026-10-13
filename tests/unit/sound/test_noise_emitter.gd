extends GutTest
## SND-02's emission API: periodic rates, silence, voice ids, client records and the event log.

var run: RunState
var noise: NoiseSystem


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	run = RunState.create(5, ServerConfig.Mode.FRIENDS, false)
	noise = NoiseSystem.new()
	run.add_system(noise)


func _count(type: NoiseTypes.Type) -> int:
	return noise.event_log.filter(func(e: NoiseSystem.Event) -> bool: return e.type == type).size()


func test_periodic_emitters_fire_at_their_rates() -> void:
	var miner: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(3.5, 3.5))
	var walk: int = noise.start_periodic(NoiseTypes.Type.STEP_WALK, miner.id)
	for _i: int in 200:
		run.run_tick()
	noise.stop_periodic(walk)
	assert_eq(_count(NoiseTypes.Type.STEP_WALK), 20, "a 10 s walk gives 20 steps")
	var run_steps: int = noise.start_periodic(NoiseTypes.Type.STEP_RUN, miner.id)
	for _i: int in 120:
		run.run_tick()
	noise.stop_periodic(run_steps)
	assert_eq(_count(NoiseTypes.Type.STEP_RUN), 12, "a full 6 s run gives 12")
	var victim: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(8.5, 3.5))
	noise.start_periodic(NoiseTypes.Type.DRAG_SCRAPE, victim.id)
	for _i: int in 100:
		run.run_tick()
	assert_eq(_count(NoiseTypes.Type.DRAG_SCRAPE), 5, "a drag scrapes once a second")
	assert_true(noise.event_log.all(func(e: NoiseSystem.Event) -> bool: return e.source_entity > 0), "each knows its true source")


func test_a_periodic_emitter_follows_its_entity_and_ends_with_it() -> void:
	var miner: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(3.5, 3.5))
	noise.start_periodic(NoiseTypes.Type.STEP_WALK, miner.id)
	run.run_tick()
	run.registry.move(miner.id, Vector2(9.5, 3.5))
	for _i: int in 10:
		run.run_tick()
	assert_eq(noise.event_log[1].origins, [Vector2i(9, 3)] as Array[Vector2i])
	run.registry.destroy(miner.id)
	for _i: int in 20:
		run.run_tick()
	assert_eq(noise.event_log.size(), 2)


func test_silent_sources_emit_nothing() -> void:
	assert_eq(noise.emit(NoiseTypes.Type.NONE, Vector2i(1, 1)), 0)
	assert_push_error("unknown type")
	assert_eq(noise.emit(NoiseTypes.Type.VOICE, Vector2i(1, 1)), 0, "voice without a band level is nothing")
	assert_push_error("needs level_np")
	run.run_tick()
	assert_eq(noise.event_log.size(), 0)


func test_voice_ids_ride_only_on_vocal_types() -> void:
	noise.emit(NoiseTypes.Type.GASP, Vector2i(1, 1), {"voice_id": 3, "source": 77})
	noise.emit(NoiseTypes.Type.VOICE, Vector2i(1, 1), {"voice_id": 3, "level_np": 12.0})
	noise.emit(NoiseTypes.Type.SHOT, Vector2i(1, 1), {"voice_id": 3})
	assert_push_error("not vocal")
	run.run_tick()
	assert_eq(noise.event_log[0].voice_id, 3)
	assert_eq(noise.event_log[1].level_np, 12.0, "voice at its band's np")
	assert_eq(noise.event_log[2].voice_id, -1, "a shot never carries a voice")
	var gasp_record: Dictionary = noise.client_record(noise.event_log[0], {"apparent": Vector2(1.5, 1.5), "remaining_np": 9.0, "true_source": Vector2i(1, 1)})
	var shot_record: Dictionary = noise.client_record(noise.event_log[2], {"apparent": Vector2(1.5, 1.5), "remaining_np": 30.0})
	var voice_id: int = gasp_record["voice_id"]
	assert_eq(voice_id, 3)
	assert_false(shot_record.has("voice_id"))
	for record: Dictionary in [gasp_record, shot_record]:
		for key: Variant in record.keys():
			assert_true(str(key) in ["event_id", "type", "tick", "apparent", "remaining_np", "duration_s", "voice_id", "level_np", "muffled"],
				"%s may reach a client" % key)


func test_event_ids_rise_and_every_event_is_logged_once() -> void:
	var ids: Array[int] = []
	for i: int in 5:
		ids.append(noise.emit(NoiseTypes.Type.ROCK_TAP, Vector2i(i, 0), {"source": 10 + i}))
	run.run_tick()
	ids.append(noise.emit(NoiseTypes.Type.SHOT, Vector2i(0, 0)))
	run.run_tick()
	assert_eq(ids, [1, 2, 3, 4, 5, 6] as Array[int])
	assert_eq(noise.event_log.map(func(e: NoiseSystem.Event) -> int: return e.id), [1, 2, 3, 4, 5, 6])
	assert_eq(noise.event_log[3].source_entity, 13, "with its true source")
	assert_eq(noise.event_log[3].origins, [Vector2i(3, 0)] as Array[Vector2i])
	assert_eq(noise.event_log[5].tick, 1)
