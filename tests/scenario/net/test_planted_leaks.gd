extends "res://tests/scenario/kit/scenario_test.gd"
## NET-08: each planted leak fails the audit with the right rule, one fixture each. Faults are
## planted where production would make them: a frame recomputed for a facing the miner does not
## have, a lowered identity threshold, a bite production was not told of, an own light changed after
## the grid was summed, a voice route through a shut gate, a record queued past the delivery stage;
## or, where no production path could carry one, a crafted message on the wire.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const W = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _hall() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(40)])
	for y: int in 9:
		rows.append(("#a" + ".".repeat(37) + "#") if y == 4 else ("#" + ".".repeat(38) + "#"))
	rows.append("#".repeat(40))
	return FixtureMap.from_ascii(rows)


## A run with Ann facing east at x+10 and the audit attached.
func _setup(seed_value: int, fixture: FixtureMap = null) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": fixture if fixture != null else _hall()})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	return [s, audit]


func _plant(s: Scenario, fn: Callable, stage: int, order: int) -> void:
	assert_true(s.run.add_system(StreamAudit.Hook.new(fn, stage, order, "plant_%d_%d" % [stage, order])))


func _expect_rule(audit: StreamAudit, rule: String, contains: String, label: String) -> void:
	var hits: Array[Dictionary] = audit.by_rule(rule)
	var matched: bool = false
	for v: Dictionary in hits:
		if str(v["detail"]).contains(contains) or str(v["record"]).contains(contains):
			matched = true
	if not matched:
		gut.p("%s: violations %s" % [label, audit.violations.slice(0, 6)])
	assert_true(matched, "%s fails rule '%s' (%s)" % [label, rule, contains])


func _peer(s: Scenario, slot: int) -> int:
	for session: Sessions.Session in s.net.sessions.welcomed():
		if session.slot == slot:
			return session.peer
	return -1


func test_an_unseen_entity() -> void:
	var p: Array = _setup(901)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var a: Vector2i = s.fixture.spot("a") + Vector2i(15, 0)
	var ann: MinerHandle = s.add_miner("ann", a)
	var ben: MinerHandle = s.add_miner("ben", a + Vector2i(-4, 0))  # behind her, lit by his own lamp
	W.lamp(s, Vector2(a) + Vector2(0.5, 0.5), 5.0, ann.entity_id)
	W.lamp(s, Vector2(a) + Vector2(-3.5, 0.5), 3.0, ben.entity_id)
	s.step(5)
	assert_eq(audit.violation_count, 0, "clean before the plant")
	# A frame computed for a facing she does not have (a stale-facing bug): Ben behind her is sent.
	_plant(s, func(r: RunState) -> void:
		var self_id: int = r.vision.watched_entity(ann.slot)
		r.vision.native.set_observer(ann.slot, self_id, r.registry.get_entity(self_id).position, 32768)
		r.vision.frames[ann.slot] = r.vision.native.compute(ann.slot), StageTable.Stage.VISIBILITY, 50)
	s.step(2)
	_expect_rule(audit, "entity", "reference has level 0", "an unseen entity")


func test_an_identity_field_in_the_fringe() -> void:
	var p: Array = _setup(902)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var a: Vector2i = s.fixture.spot("a") + Vector2i(5, 0)
	var ann: MinerHandle = s.add_miner("ann", a)
	var moth: int = s.place_creature(WorldIds.EntityKind.MOTH, a + Vector2i(10, 0))
	W.lamp(s, Vector2(a) + Vector2(15.5, 0.5), 5.8)  # about 0.18 on the Moth's brightest tile: the fringe
	s.step(5)
	var x: Dictionary = Variants.dict(audit._expected.get(ann.slot, {}))
	var ents: Dictionary = Variants.dict(x.get("entities", {}))
	assert_eq(int(Variants.number(ents.get(moth, 0))) >> 8, LbAuditReference.LEVEL_TOKEN, "the Moth is in the fringe")
	s.run.vision.native.set_identity_threshold(moth, 0.05)  # production loses the 0.30 rule
	s.step(2)
	_expect_rule(audit, "entity", "identity for entity %d" % moth, "an identity field in the fringe")


func test_a_margin_tile_behind_the_miner() -> void:
	var p: Array = _setup(903)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var a: Vector2i = s.fixture.spot("a") + Vector2i(18, 0)
	var ann: MinerHandle = s.add_miner("ann", a)
	W.lamp(s, Vector2(a) + Vector2(0.5, 0.5), 4.0, ann.entity_id)
	s.step(5)
	_plant(s, func(r: RunState) -> void:
		var self_id: int = r.vision.watched_entity(ann.slot)
		r.vision.native.set_observer(ann.slot, self_id, r.registry.get_entity(self_id).position, 32768)
		r.vision.frames[ann.slot] = r.vision.native.compute(ann.slot), StageTable.Stage.VISIBILITY, 50)
	s.step(2)
	_expect_rule(audit, "geometry", "neither seen nor in the margin", "a margin tile behind the miner")


func test_a_margin_entity_in_a_bite() -> void:
	var p: Array = _setup(904)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var a: Vector2i = s.fixture.spot("a") + Vector2i(5, 0)
	var ann: MinerHandle = s.add_miner("ann", a)
	W.lamp(s, Vector2(a) + Vector2(0.5, 0.5), 4.0, ann.entity_id)
	s.step(8)
	# Find a margin tile in front of her and stand a Moth on it; the bite covers it (VIS-10), but
	# production is not told. Ben stands on it.
	var margin: Dictionary = audit._expected[ann.slot]["margin"]
	var spot: Vector2i = Vector2i(-1, -1)
	for raw: Variant in margin.keys():
		var t: Vector2i = raw
		if t.y == a.y and t.x > a.x:
			spot = t
			break
	assert_ne(spot, Vector2i(-1, -1), "a margin tile ahead")
	audit.bite_tiles = func(_slot: int) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for dy: int in range(-2, 3):
			for dx: int in range(-2, 3):
				out.append(spot + Vector2i(dx, dy))
		return out
	var moth: int = s.add_miner("ben", spot).entity_id  # (the spawn guard keeps creatures off margins; a miner stands there)
	s.step(3)
	_expect_rule(audit, "entity", "a margin token for entity %d" % moth, "a margin entity in a bite")


func test_a_margin_record_with_the_own_light_shuttered() -> void:
	var p: Array = _setup(905)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var a: Vector2i = s.fixture.spot("a") + Vector2i(5, 0)
	var ann: MinerHandle = s.add_miner("ann", a)
	var extra: int = s.run.light.grid.add_point("candle", LbLightGrid.COLOUR_AMBER, ann.entity_id, 0, 0.0, 1.0, Vector2(a) + Vector2(0.5, 0.5), 0)
	s.step(6)
	assert_eq(audit.violation_count, 0)
	# After the grid was summed, production's own light gains a radius (a stale lamp state).
	_plant(s, func(r: RunState) -> void:
		r.light.grid.update_point(extra, Vector2(a) + Vector2(0.5, 0.5), 4.0, 1.0), StageTable.Stage.ROAD_GRAPH, 950)
	s.step(1)
	_expect_rule(audit, "geometry", "neither seen nor in the margin", "a margin record with the own light shuttered")


func test_a_tell_cue_at_the_creature() -> void:
	var p: Array = _setup(906)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var moth: int = s.place_creature(WorldIds.EntityKind.MOTH, a + Vector2i(20, 0))
	s.step(5)
	var r: AudioRecord = AudioRecord.new()
	r.type = LocalSounds.Type.MOTH_STIR
	r.flags = AudioRecord.DIFFUSE
	r.start_tick = s.run.tick
	r.level_np = 10.0
	r.remaining_np = 8.0
	r.points.append(s.run.registry.get_entity(moth).position)  # the creature's own position
	s.run.audio.deliver(ann.slot, r)
	s.step(3)
	_expect_rule(audit, "audio", "a tell point on a creature", "a tell cue carrying a creature's position (CRT-01)")


func test_a_crew_count_on_the_wire() -> void:
	var p: Array = _setup(907)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(3)
	# DIR-05's numbers have no record type: any message carrying them is an unregistered one.
	var b: PackedByteArray = PackedByteArray([4, 2, 1])  # crew 4, active hunters 2, active flag
	s.net.transport.send(_peer(s, ann.slot), Lane.Id.CONTROL, Protocol.frame(99, b))
	_expect_rule(audit, "registry", "no audit rule", "the crew count, capacity or an active flag (DIR-05)")


func test_an_audio_event_with_no_delivery() -> void:
	var p: Array = _setup(908)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(3)
	var r: AudioRecord = AudioRecord.new()
	r.type = NoiseTypes.Type.HAMMER
	r.start_tick = s.run.tick
	r.apparent = Vector2(30.5, 5.5)
	r.level_np = 14.0
	r.remaining_np = 10.0
	s.run.replication.queue_audio(ann.slot, r)  # past SND-03's delivery stage
	s.step(2)
	_expect_rule(audit, "audio", "no delivery", "an audio event with no delivery")


func test_a_voice_frame_through_a_shut_gate() -> void:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(20), "#a...G....b.......#", "#".repeat(20)])
	var p: Array = _setup(909, FixtureMap.from_ascii(rows))
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var ben: MinerHandle = s.add_miner("ben", s.fixture.spot("b"))
	s.step(3)
	ann.at(s.run.tick).say(3, 12)
	s.step(3)
	assert_eq(audit.violation_count, 0, "the gate cuts her voice: nothing to judge yet")
	# A route the forwarder should never have: to Ben, behind the shut gate.
	var st: Dictionary = s.run.voice._speaking[ann.slot]
	var streams: Dictionary = st["streams"]
	streams[ben.slot] = 4242
	var routes: Array = s.run.voice.compute(ann.slot, 3, streams)
	routes.append({"listener": ben.slot, "stream": 4242, "gain_db": 0.0, "flags": 0, "crackle": false, "muffle": 0.0, "loss": 0.0,
		"x": 2.5, "y": 1.5})
	s.run.voice.forwarder.set_routes(ann.slot, routes, int(Variants.number(st["utterance"])))
	s.step(3)
	_expect_rule(audit, "voice", "no road", "a voice frame through a shut gate")


func test_a_feel_reply_with_a_position() -> void:
	var p: Array = _setup(910)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(3)
	var b: PackedByteArray = FeelMessages.feel("caption.feel.wall", 3, "verb.feel")
	b.append_array(PackedByteArray([12, 0, 0, 0, 5, 0, 0, 0]))  # x 12, y 5
	s.net.transport.send(_peer(s, ann.slot), Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.FEEL, b))
	_expect_rule(audit, "feel", "position", "a feel reply with a position")


func test_an_illusion_on_a_second_client() -> void:
	var p: Array = _setup(911)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var ben: MinerHandle = s.add_miner("ben", s.fixture.spot("a") + Vector2i(3, 0))
	s.step(3)
	_plant(s, func(r: RunState) -> void:
		if r.tick % 50 == 0:
			return
		var ev: Dictionary = {"type": NoiseTypes.Type.ROCK_TAP, "start_tick": r.tick, "apparent": Vector2(20.5, 4.5), "remaining_np": 6.0,
			"level_np": 10.0, "duration_s": 0.5, "voice": -1, "flags": 0, "gain_db": 0, "points": []}
		r.replication.append_illusion_event(ann.slot, ev, 77)
		r.replication.append_illusion_event(ben.slot, ev.duplicate(), 77), StageTable.Stage.ILLUSIONS, 0)
	s.step(2)
	_expect_rule(audit, "illusion", "second client", "an illusion on a second client")


func test_a_qa_illusion_id_from_a_release_server() -> void:
	var p: Array = _setup(912)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(3)
	s.net.flavour = BuildInfo.Flavour.RELEASE
	s.net.transport.send(_peer(s, ann.slot), Lane.Id.DEBUG, Protocol.frame(Protocol.Msg.DEBUG_TAG, PackedByteArray([1, 77, 0])))
	_expect_rule(audit, "debug", "release server", "a QA illusion id")


func test_a_server_entity_id() -> void:
	var p: Array = _setup(913)
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var moth: int = s.place_creature(WorldIds.EntityKind.MOTH, s.fixture.spot("a") + Vector2i(3, 0))
	s.step(3)
	# A full frame whose one entity record is keyed by the Moth's server id, not a token.
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(FrameDecoder.VERSION)
	b.put_u32(0)  # the tick, set when sent
	b.put_u16(0)  # full
	b.put_u16(0xFFFF)
	b.put_u16(0xFFFF)
	b.put_u8(0)
	b.put_u8(FrameDecoder.FLAG_FULL)
	var at: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	b.put_32(int(at.x * 256.0))
	b.put_32(int(at.y * 256.0))
	b.put_u16(0)
	b.put_u8(255)
	b.put_u8(100)
	b.put_u16(0)
	b.put_u8(120)
	b.put_u8(0)
	b.put_u8(0)
	for n: int in 3:  # tiles, removals, geometry
		b.put_u16(0)
	b.put_u16(1)
	b.put_u16(moth)
	b.put_u8(1)
	b.put_u8(SeenKind.Size.LARGE)
	b.put_16(192)
	b.put_16(0)
	b.put_u16(0)  # entity removals
	b.put_u8(0)  # no glow
	b.put_u8(0)  # no events
	var bytes: PackedByteArray = b.data_array
	var peer: int = _peer(s, ann.slot)
	_plant(s, func(r: RunState) -> void:
		bytes.encode_u32(1, r.tick)
		s.net.transport.send(peer, Lane.Id.FRAMES, Protocol.frame(Protocol.Msg.FRAME, bytes)), StageTable.Stage.SEND, 77)
	W.lamp(s, Vector2(s.fixture.spot("a")) + Vector2(0.5, 0.5), 5.0, ann.entity_id)
	s.step(2)
	_expect_rule(audit, "entity", "never issued", "a server entity id")


func test_a_road_graph_true_source() -> void:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(16), "#a.........#..#", "#.#######.###.#", "#.........b...#", "#".repeat(16)])
	var p: Array = _setup(914, FixtureMap.from_ascii(rows))
	var s: Scenario = p[0]
	var audit: StreamAudit = p[1]
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(3)
	var origin: Vector2i = s.fixture.spot("b")
	var id: int = s.run.noise.emit(NoiseTypes.Type.HAMMER, origin)
	s.step(1)
	var event: NoiseSystem.Event = null
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if e.id == id:
			event = e
	assert_not_null(event)
	# A record of that very delivery, placed at the true source instead of where the road brings it.
	var r: AudioRecord = AudioRecord.new()
	r.type = NoiseTypes.Type.HAMMER
	r.start_tick = s.run.tick
	r.apparent = Vector2(origin) + Vector2(0.5, 0.5)
	r.level_np = event.level_np
	r.remaining_np = 1.0
	s.run.audio.deliver(ann.slot, r, id)
	s.step(2)
	_expect_rule(audit, "audio", "true source", "a Road Graph delivery's true source")
