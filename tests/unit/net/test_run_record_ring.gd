extends "res://tests/scenario/kit/scenario_test.gd"
## NET-07's rolling ring: sealed 2 s blocks, rolling at net.record_window_s (shortened here), its
## memory counted, and never audio: the record's schema holds frames as sent, the frames' true
## light, and each voice frame's band, speaker and listeners only.

const W = preload("res://tests/scenario/net/record_world.gd")
## The authoritative track's keys (RecordBlock); nothing else may appear.
const AUTH_KEYS: Array[String] = ["t", "m", "c", "x", "fl", "s", "d", "n", "v", "g", "dr", "lie", "fall", "death"]
const STREAM_KEYS: Array[String] = ["f", "l", "r"]


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_ring_rolls_and_its_blocks_are_whole() -> void:
	var s: Scenario = make({"seed": 81, "fixture": "test", "overrides": {"net.record_window_s": 20.0}})
	W.crew(s, 2, 81)
	s.step(1200)
	var r: RunRecord = s.run.record
	var span: int = r.ring_ticks
	assert_eq(span, 400)
	assert_false(r.ring.is_empty())
	assert_lte(r.ring.size(), span / r.block_ticks + 1, "no more than net.record_window_s of blocks")
	assert_gte(r.ring[0].start, s.run.tick - span - r.block_ticks - r.seal_lag_ticks, "the oldest block rolled off")
	for i: int in range(1, r.ring.size()):
		assert_eq(r.ring[i].start, r.ring[i - 1].start + r.block_ticks, "blocks are contiguous")
	assert_gt(s.run.tick - 1 - r.sealed_to(), 0)
	# A block seals a part a tick: its authoritative track, each client's stream, then the ring.
	assert_lte(s.run.tick - 1 - r.sealed_to(), r.block_ticks + r.seal_lag_ticks + 2 + 2, "sealing lags by at most a block, the ack window and its parts")
	var counted: int = 0
	for b: RecordBlock in r.ring:
		counted += b.size()
	assert_eq(r.ring_bytes(), counted, "the running count matches the blocks")
	assert_eq(r.memory_bytes(), r.ring_bytes() + r.windows_bytes() + r._open_bytes)
	assert_gt(r._open_bytes, 0)
	var per_block: float = float(r.ring_bytes()) / r.ring.size()
	gut.p("two clients: %.1f KB a block, %.2f MB for the ring of %d blocks" % [per_block / 1024.0, r.ring_bytes() / 1048576.0, r.ring.size()])


## The keyframes come from NET-04's encoder: the view it records for each frame is exactly the view
## the client decodes from that frame, field for field, under loss.
func test_the_encoders_views_are_the_clients() -> void:
	var s: Scenario = make({"seed": 83, "fixture": "test"})
	var miners: Array[MinerHandle] = W.crew(s, 2, 83, [150, 4.0])
	var ann: MinerHandle = miners[0]
	var compared: Array[int] = [0]
	var differ: Array[int] = []
	s.client(ann).on_decoded = func(d: FrameDecoder.Decoded) -> void:
		var sent: Dictionary = s.run.replication.native.sent_view(ann.slot, d.tick)
		if sent.is_empty():
			return
		compared[0] += 1
		if sent != d.view.to_dict():
			differ.append(d.tick)
	s.step(400)
	assert_gt(compared[0], 350)
	assert_eq(differ, [] as Array[int], "every view, field for field")


func test_the_schema_never_holds_audio() -> void:
	var s: Scenario = make({"seed": 82, "fixture": "test"})
	var miners: Array[MinerHandle] = W.crew(s, 2, 82)
	miners[1].at(20).say(3, 80)
	s.step(260)
	var r: RunRecord = s.run.record
	var area: int = r.frame_size.x * r.frame_size.y
	var bands: int = 0
	var problems: Array[String] = []
	for b: RecordBlock in r.ring:
		var key: Dictionary = b.auth_keyframe()
		for k: Variant in key.keys():
			if not ["tick", "ids", "kinds", "xy", "flags", "sources", "doors"].has(str(k)):
				problems.append("auth keyframe key %s" % k)
		for raw: Variant in b.auth_ticks():
			var e: Dictionary = raw
			for k: Variant in e.keys():
				if not AUTH_KEYS.has(str(k)):
					problems.append("auth key %s" % k)
			_no_bytes(e, "auth tick", problems)
			for v: Variant in Variants.array(e.get("v", [])):
				var line: Array = v
				bands += 1
				if line.size() != 3 or not (line[0] is int and line[1] is int and line[2] is int):
					problems.append("voice line %s" % [line])
		for raw: Variant in b.streams.keys():
			var slot: int = raw
			var lines: Dictionary = b.stream_ticks(slot)
			for k: Variant in lines.keys():
				if not STREAM_KEYS.has(str(k)):
					problems.append("stream key %s" % k)
			for f: Variant in Variants.array(lines.get("f", [])):
				var frame: Array = f
				var bytes: PackedByteArray = frame[1]
				if FrameDecoder.header(bytes).is_empty():
					problems.append("a stream entry that is not a frame (tick %s)" % frame[0])
			for l: Variant in Variants.array(lines.get("l", [])):
				var line: Array = l
				var light: PackedByteArray = line[2]
				if light.size() != area:
					problems.append("a light line of %d bytes" % light.size())
	gut.p("voice frames kept as bands: %d" % bands)
	assert_gt(bands, 0, "the speech was kept, as bands")
	assert_eq(problems, [] as Array[String])


## No byte array anywhere in the authoritative track: frames and light live in the streams only.
func _no_bytes(value: Variant, where: String, problems: Array[String]) -> void:
	if value is PackedByteArray:
		problems.append("bytes in the %s" % where)
	elif value is Dictionary:
		var d: Dictionary = value
		for k: Variant in d.keys():
			_no_bytes(d[k], where, problems)
	elif value is Array:
		var a: Array = value
		for v: Variant in a:
			_no_bytes(v, where, problems)
