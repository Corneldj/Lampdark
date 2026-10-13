extends "res://tests/scenario/kit/scenario_test.gd"
## NET-04's client decoder: it agrees with the native reference on every frame, refuses
## malformed frames, and its records hold only the reviewed fields (the schema check).

const N = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_gdscript_and_native_decoders_agree() -> void:
	var s: Scenario = make({"seed": 41, "fixture": N.road()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("a") + Vector2i(4, 0), {"facing_deg": 180.0})
	N.lamp(s, Vector2(6.5, 2.5), 5.5, bob.entity_id)
	ann.at(0).move(0.0, InputRecord.Gait.WALK, 30)
	bob.at(0).face(180.0)
	s.step(40)
	var frames: Array[PackedByteArray] = N.frames(s.client(ann))
	assert_gt(frames.size(), 30)
	var decoder: FrameDecoder = FrameDecoder.new()
	var saw_entity: bool = false
	for payload: PackedByteArray in frames:
		var mine: FrameDecoder.Decoded = decoder.decode(payload)
		assert_true(mine.ok)
		var native: Dictionary = LbFrameCodec.decode_records(payload)
		assert_true(Variants.flag(native["ok"]))
		assert_eq(mine.tick, int(Variants.number(native["tick"])))
		assert_eq(mine.events.size(), Variants.array(native["events"]).size())
		saw_entity = saw_entity or not mine.view.entities.is_empty()
	assert_true(saw_entity, "Bob, in his own core, was identified")
	var last: ReceivedView = decoder.history[decoder.history.keys().max()]
	assert_gt(last.tiles.size(), 10)
	assert_gt(last.geometry.size(), 10)


func test_malformed_frames_decode_to_nothing() -> void:
	var s: Scenario = make({"seed": 42, "fixture": N.road()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	N.lamp(s, Vector2(2.5, 2.5))
	s.step(6)
	var payload: PackedByteArray = N.frames(s.client(ann))[0]
	var decoder: FrameDecoder = FrameDecoder.new()
	assert_false(decoder.decode(payload.slice(0, payload.size() - 1)).ok, "truncated")
	var wrong: PackedByteArray = payload.duplicate()
	wrong[0] = 9
	assert_false(decoder.decode(wrong).ok, "unknown version")
	assert_false(decoder.decode(PackedByteArray()).ok, "empty")
	var later: PackedByteArray = N.frames(s.client(ann))[4]
	var fresh: FrameDecoder = FrameDecoder.new()
	var d: FrameDecoder.Decoded = fresh.decode(later)
	if d.baseline_tick >= 0:
		assert_false(d.ok, "a delta against a baseline this decoder never had is refused")


## Never: a server entity ID, seed, Pull, intensity, variant or illusion ID in any frame. The
## decoded records carry exactly these fields.
func test_schema() -> void:
	var s: Scenario = make({"seed": 43, "fixture": N.road()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("a") + Vector2i(3, 0))
	N.lamp(s, Vector2(4.5, 2.5), 5.5, bob.entity_id)
	s.run.registry.create(WorldIds.EntityKind.COAT_HEAP, Vector2(8.5, 2.5))
	s.run.noise.emit(NoiseTypes.Type.GASP, Vector2i(4, 2), {"voice_id": 2, "source": bob.entity_id})
	s.step(6)
	var view: ReceivedView = s.client(ann).records_at(5)
	var allowed_entity: Array = ["level", "size_or_kind", "position", "facing", "cues", "in_hand", "flame"]
	for raw: Variant in view.entities.values():
		for key: Variant in Variants.dict(raw).keys():
			assert_true(str(key) in allowed_entity, "entity field %s" % key)
	assert_eq(view.own.keys(), ["position", "facing", "gait", "speed_q", "flags", "stamina_q", "lamp_radius", "flame"])
	var events: Array[Dictionary] = s.client(ann).audio_events(0, 10)
	assert_gt(events.size(), 0)
	for e: Dictionary in events:
		for key: Variant in e.keys():
			assert_true(str(key) in ["number", "type", "start_tick", "apparent", "remaining_np", "duration_s", "voice", "arrived",
				"level_np", "flags", "gain_db", "points"],
				"event field %s" % key)
	var forbidden: RegEx = RegEx.create_from_string("entity|seed|pull|intensity|variant|illusion|source|id$")
	for name: String in ["level", "size_or_kind", "position", "facing", "number", "type", "start_tick", "apparent",
			"remaining_np", "duration_s", "voice", "gait", "speed_q", "flags"]:
		assert_null(forbidden.search(name), "%s names nothing secret" % name)
	assert_ne(s.run.replication.native.token_of(ann.slot, bob.entity_id), bob.entity_id, "a token is not the entity id")
