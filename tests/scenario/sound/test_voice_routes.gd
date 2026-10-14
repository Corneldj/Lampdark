extends "res://tests/scenario/kit/scenario_test.gd"
## SND-07: voice frames through the server, end to end over the kit's network. Range by road per
## band; the rock line (2 tiles of rock at half range, muffled, heard from the listener's wall
## face; 3 tiles, brick or a door stop it); closed portals; the routes; direct lines and shared
## channels; stream ids and headers that name nobody.


func before_all() -> void:
	assert_true(Tuning.load_server())


## Downstream voice packets a miner's client received since the last call.
func _heard(h: MinerHandle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Array in h.connection.voice_in:
		var packet: PackedByteArray = raw[0]
		out.append(VoicePackets.read_down(packet))
	h.connection.voice_in.clear()
	return out


func _clear(miners: Array[MinerHandle]) -> void:
	for h: MinerHandle in miners:
		h.connection.voice_in.clear()


## A straight road, 30 tiles, the speaker at its west end.
func _corridor() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(32), "#a" + ".".repeat(29) + "#", "#".repeat(32)]))


func test_road_range_by_band() -> void:
	# reached / not reached, tiles: whisper 3/4, talk 12/13, shout and scream 24/25.
	var cases: Array = [[1, 3, 4], [2, 12, 13], [3, 24, 25], [4, 24, 25]]
	for c: Array in cases:
		var band: int = int(Variants.number(c[0]))
		var reached: int = int(Variants.number(c[1]))
		var not_reached: int = int(Variants.number(c[2]))
		var s: Scenario = make({"seed": 70, "fixture": _corridor()})
		var a: Vector2i = s.fixture.spot("a")
		var speaker: MinerHandle = s.add_miner("ann", a)
		var near: MinerHandle = s.add_miner("ben", a + Vector2i(reached, 0))
		var far: MinerHandle = s.add_miner("cat", a + Vector2i(not_reached, 0))
		s.step(3)
		_clear([near, far])
		speaker.at(s.run.tick).say(band, 5)
		s.step(8)
		assert_gt(_heard(near).size(), 0, "band %d reaches %d tiles" % [band, reached])
		assert_eq(_heard(far).size(), 0, "band %d does not reach %d tiles" % [band, not_reached])


func test_gain_falls_with_path_length_to_the_edge_gain() -> void:
	var s: Scenario = make({"seed": 71, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var speaker: MinerHandle = s.add_miner("ann", a)
	var near: MinerHandle = s.add_miner("ben", a + Vector2i(1, 0))
	var edge: MinerHandle = s.add_miner("cat", a + Vector2i(12, 0))
	s.step(3)
	_clear([near, edge])
	speaker.at(s.run.tick).say(2, 3)
	s.step(6)
	var g_near: int = int(Variants.number(_heard(near)[0]["gain_db"]))
	var g_edge: int = int(Variants.number(_heard(edge)[0]["gain_db"]))
	assert_between(g_near, -2, 0, "next to the speaker: nearly 0 dB")
	assert_eq(g_edge, roundi(Tuning.f(&"voice.edge_gain_db")), "at the range's edge: the edge gain")


## Two roads with `rows` between them; the speaker over the listener. `wall` fills the between.
func _pillar(rows: int, wall: String) -> FixtureMap:
	var p: PackedStringArray = PackedStringArray(["#".repeat(16), "#....a.........#"])
	for i: int in rows:
		p.append("#####" + wall + "##########")
	p.append("#....b.........#")
	p.append("#".repeat(16))
	return FixtureMap.from_ascii(p)


func test_rock_line_two_tiles_reaches_muffled_from_the_wall_face() -> void:
	var s: Scenario = make({"seed": 72, "fixture": _pillar(2, "#")})
	var speaker: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var b: Vector2i = s.fixture.spot("b")
	var listener: MinerHandle = s.add_miner("ben", b)
	s.step(3)
	_clear([listener])
	speaker.at(s.run.tick).say(2, 4)
	s.step(7)
	var got: Array[Dictionary] = _heard(listener)
	assert_gt(got.size(), 0, "talk through 2 tiles of rock, 3 tiles away")
	if got.size() > 0:
		assert_true(Variants.flag(got[0]["muffled"]), "muffled")
		var at: Vector2 = got[0]["position"]
		assert_eq(Vector2i(floori(at.x), floori(at.y)), b + Vector2i(0, -1), "heard from the listener's wall face")


func test_rock_line_stopped_by_three_tiles_brick_or_a_door() -> void:
	for layout: Array in [[3, "#", "3 tiles of rock"], [2, "B", "brick"], [2, "D", "an air door"]]:
		var rows_between: int = int(Variants.number(layout[0]))
		var s: Scenario = make({"seed": 73, "fixture": _pillar(rows_between, str(layout[1]))})
		var speaker: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
		var listener: MinerHandle = s.add_miner("ben", s.fixture.spot("b"))
		s.step(3)
		_clear([listener])
		speaker.at(s.run.tick).say(4, 4)
		s.step(7)
		assert_eq(_heard(listener).size(), 0, "%s stops a scream's rock line" % layout[2])


func test_a_shut_gate_on_the_only_path_stops_everything_and_an_open_way_round_is_used() -> void:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(20), "#a...G....b.......#", "#".repeat(20)])
	var s: Scenario = make({"seed": 74, "fixture": FixtureMap.from_ascii(rows)})
	var speaker: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var listener: MinerHandle = s.add_miner("ben", s.fixture.spot("b"))
	s.step(3)
	_clear([listener])
	speaker.at(s.run.tick).say(4, 4)
	s.step(7)
	assert_eq(_heard(listener).size(), 0, "a shut gate on the only path: even a scream is cut")
	assert_true(s.set_gate(1, true))
	s.step(2)
	speaker.at(s.run.tick).say(2, 4)
	s.step(7)
	assert_gt(_heard(listener).size(), 0, "the gate open: heard")
	# Two rooms joined by two gates: the short way shut, the long way round open.
	var two: PackedStringArray = PackedStringArray([
		"#".repeat(16),
		"#a...G........b#",
		"#.############.#",
		"#.......G......#",
		"#".repeat(16)])
	var t: Scenario = make({"seed": 75, "fixture": FixtureMap.from_ascii(two)})
	var sp: MinerHandle = t.add_miner("ann", t.fixture.spot("a"))
	var li: MinerHandle = t.add_miner("ben", t.fixture.spot("b"))
	t.step(3)
	_clear([li])
	sp.at(t.run.tick).say(3, 4)
	t.step(7)
	assert_eq(_heard(li).size(), 0, "both gates shut: nothing")
	assert_true(t.set_gate(2, true))
	t.step(2)
	sp.at(t.run.tick).say(3, 4)
	t.step(7)
	assert_gt(_heard(li).size(), 0, "a shout takes the open way round")


func test_routes() -> void:
	var s: Scenario = make({"seed": 76, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var speaker: MinerHandle = s.add_miner("ann", a)
	var close: MinerHandle = s.add_miner("ben", a + Vector2i(3, 0))
	var mid: MinerHandle = s.add_miner("cat", a + Vector2i(5, 0))
	var far: MinerHandle = s.add_miner("dan", a + Vector2i(24, 0))
	s.step(3)
	var all: Array[MinerHandle] = [close, mid, far]
	# DRAGGED: whisper range, muffled, whatever the band.
	s.run.voice.set_route(speaker.slot, VoiceRoutes.Route.DRAGGED)
	_clear(all)
	speaker.at(s.run.tick).say(4, 4)
	s.step(7)
	var got: Array[Dictionary] = _heard(close)
	assert_gt(got.size(), 0, "dragged: heard within 3 tiles")
	assert_true(got.size() > 0 and Variants.flag(got[0]["muffled"]), "muffled")
	assert_eq(_heard(mid).size(), 0, "dragged: not at 5 tiles")
	# CUT and ASIDE: nobody.
	for route: VoiceRoutes.Route in [VoiceRoutes.Route.CUT, VoiceRoutes.Route.ASIDE]:
		s.run.voice.set_route(speaker.slot, route)
		_clear(all)
		speaker.at(s.run.tick).say(4, 4)
		s.step(7)
		for h: MinerHandle in all:
			assert_eq(_heard(h).size(), 0, "route %d reaches nobody" % route)
	# FALL_SCREAM: shout range whatever the band, 24 tiles.
	s.run.voice.set_route(speaker.slot, VoiceRoutes.Route.FALL_SCREAM)
	_clear(all)
	speaker.at(s.run.tick).say(1, 6)
	s.step(9)
	assert_eq(_heard(far).size(), 6, "the fall's scream reaches 24 tiles, every frame")


func test_direct_lines_and_shared_channels() -> void:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(60), "#a" + ".".repeat(57) + "#", "#".repeat(60)])
	var s: Scenario = make({"seed": 77, "fixture": FixtureMap.from_ascii(rows)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var ben: MinerHandle = s.add_miner("ben", a + Vector2i(50, 0))
	var cat: MinerHandle = s.add_miner("cat", a + Vector2i(55, 0))
	s.step(3)
	s.run.voice.open_direct(ann.slot, ben.slot)
	_clear([ben, cat])
	ann.at(s.run.tick).say(1, 5)
	s.step(8)
	var line: Array[Dictionary] = _heard(ben)
	assert_eq(line.size(), 5, "a phone line delivers every frame, 50 tiles away")
	assert_true(line.size() > 0 and Variants.flag(line[0]["telephone"]), "in telephone band")
	assert_eq(_heard(cat).size(), 0, "only the line's other end")
	s.run.voice.close_direct(ann.slot, ben.slot)
	s.run.voice.channel_join("lamp_check", ann.slot)
	s.run.voice.channel_join("lamp_check", cat.slot)
	_clear([ben, cat])
	var events_before: int = s.run.noise.event_log.size()
	ann.at(s.run.tick).say(2, 5)
	s.step(8)
	var shared: Array[Dictionary] = _heard(cat)
	assert_eq(shared.size(), 5, "a channel delivers every frame to every member")
	assert_true(shared.size() > 0 and Variants.flag(shared[0]["dry"]), "dry")
	assert_eq(_heard(ben).size(), 0, "outside the channel: nothing")
	var events_after: int = s.run.noise.event_log.size()
	assert_eq(events_after, events_before, "no Road Graph event from a channel")


func test_stream_ids_are_new_every_utterance_and_headers_name_nobody() -> void:
	var s: Scenario = make({"seed": 78, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var ben: MinerHandle = s.add_miner("ben", a + Vector2i(4, 0))
	s.step(3)
	var ids: Array[int] = []
	for utterance: int in 3:
		_clear([ben])
		ann.at(s.run.tick).say(2, 3)
		s.step(5)
		ann.connection.send_voice(VoicePackets.end(ann.voice_frames_sent))  # the band fell silent
		s.step(2)
		var got: Array[Dictionary] = _heard(ben)
		assert_gt(got.size(), 0)
		var stream: int = int(Variants.number(got[0]["stream"]))
		for d: Dictionary in got:
			assert_eq(int(Variants.number(d["stream"])), stream, "one stream per utterance")
		ids.append(stream)
	assert_ne(ids[0], ids[1], "a new stream id every utterance")
	assert_ne(ids[1], ids[2])
	var keys: Array = VoicePackets.read_down(PackedByteArray([1, 0, 2, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])).keys()
	keys.sort()
	assert_eq(keys, ["band", "crackle", "dry", "end", "gain_db", "muffled", "opus", "position", "probe", "seq", "stream", "telephone"],
		"a header's fields: nothing names a speaker or an entity")


func test_malformed_voice_is_refused_and_counted() -> void:
	var s: Scenario = make({"seed": 79, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var ben: MinerHandle = s.add_miner("ben", a + Vector2i(2, 0))
	s.step(3)
	_clear([ben])
	ann.connection.send_voice(PackedByteArray([0, 0, 6, 1, 2, 3]))  # band 6
	s.step(3)
	assert_eq(_heard(ben).size(), 0)
	assert_eq(s.run.voice.refused, 1, "refused and counted (NET-13 reads bad messages)")


func test_a_shut_air_door_cuts_voice_completely() -> void:
	# GEN-15's shelter: listeners beyond a shut air door receive no voice frames, even a scream.
	var rows: PackedStringArray = PackedStringArray(["#".repeat(20), "#a...D....b.......#", "#".repeat(20)])
	var s: Scenario = make({"seed": 80, "fixture": FixtureMap.from_ascii(rows)})
	var speaker: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var listener: MinerHandle = s.add_miner("ben", s.fixture.spot("b"))
	s.step(3)
	_clear([listener])
	speaker.at(s.run.tick).say(4, 6)
	s.step(9)
	assert_eq(_heard(listener).size(), 0, "no frame passes a shut air door")
