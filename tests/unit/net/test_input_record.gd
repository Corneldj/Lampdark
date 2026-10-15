extends GutTest
## NET-03's input record and packet: packing, bounds, malformed packets, and the schema rule
## that a client sends intent only (GDD §15.11).


func _round_trip(p: InputPacket) -> InputPacket:
	var message: Dictionary = Protocol.unframe(p.encode())
	assert_eq(int(Variants.number(message["type"])), Protocol.Msg.INPUT)
	var payload: PackedByteArray = message["payload"]
	return InputPacket.decode(payload)


func _record(move_dir: int, gait: InputRecord.Gait, facing: int, holds: int, desired: int) -> InputRecord:
	var r: InputRecord = InputRecord.new()
	r.move_dir = move_dir
	r.gait = gait
	r.facing = facing
	r.holds = holds
	r.desired = desired
	return r


func test_record_packs_into_seven_bytes_and_back() -> void:
	var r: InputRecord = _record(254, InputRecord.Gait.RUN, 65535, InputRecord.HOLD_FEEL | InputRecord.HOLD_AIM, 5)
	r.shown_delta = 3
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	r.pack(b)
	assert_eq(b.data_array.size(), InputRecord.SIZE)
	b.seek(0)
	var back: InputRecord = InputRecord.unpack(b)
	assert_eq(back.move_dir, 254)
	assert_eq(back.gait, InputRecord.Gait.RUN)
	assert_eq(back.facing, 65535)
	assert_eq(back.holds, InputRecord.HOLD_FEEL | InputRecord.HOLD_AIM)
	assert_eq(back.desired, 5)
	assert_eq(back.shown_delta, 3)
	assert_true(back.is_valid())


func test_bounds() -> void:
	assert_true(_record(InputRecord.NO_DIRECTION, InputRecord.Gait.CROUCH, 0, 0, 0).is_valid())
	var bad_gait: PackedByteArray = PackedByteArray([0, 0, 3, 0, 0, 0, 0])
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bad_gait
	assert_false(InputRecord.unpack(b).is_valid(), "gait 3 is out of range, not mapped to a default")
	var bad_wick: PackedByteArray = PackedByteArray([0, 0, 1 | (6 << 2), 0, 0, 0, 0])
	b.data_array = bad_wick
	assert_false(InputRecord.unpack(b).is_valid(), "wick step 3 is out of range")
	var action_bytes: PackedByteArray = PackedByteArray([0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0])
	b.data_array = action_bytes
	assert_false(ActionRecord.unpack(b).is_valid(), "unknown action kind")
	assert_eq(_record(0, InputRecord.Gait.WALK, 16384, 0, 2).facing_radians(), PI / 2.0)


func test_stop_releases_controls_and_movement_only() -> void:
	var r: InputRecord = _record(10, InputRecord.Gait.RUN, 1234, InputRecord.HOLD_INTERACT, 3)
	var s: InputRecord = r.stopped()
	assert_eq(s.move_dir, InputRecord.NO_DIRECTION)
	assert_eq(s.holds, 0)
	assert_eq(s.facing, 1234)
	assert_eq(s.desired, 3, "the lamp keeps its wanted state")


func test_packet_round_trip() -> void:
	var p: InputPacket = InputPacket.new()
	p.ack_frame = 0xFFFE
	p.ack_bits = 0x80000001
	p.recv_delay = 17
	p.shown_tick = 4000000000
	p.shown_fraction = 200
	p.newest_seq = 1
	for i: int in 4:
		var r: InputRecord = _record(i * 10, InputRecord.Gait.WALK, i * 1000, i, 2)
		r.shown_delta = i
		p.inputs.append(r)
	var a: ActionRecord = ActionRecord.new()
	a.action_seq = 0xFFFF
	a.kind = ActionRecord.Kind.TRIGGER
	a.arg = 7
	a.tick = 123456
	a.aim = 40000
	p.actions.append(a)
	p.cue_reports.append(PackedInt64Array([99, 4000000001, 128]))
	var back: InputPacket = _round_trip(p)
	assert_not_null(back)
	assert_eq(back.ack_frame, 0xFFFE)
	assert_eq(back.ack_bits, 0x80000001)
	assert_eq(back.recv_delay, 17)
	assert_eq(back.shown_tick, 4000000000)
	assert_eq(back.shown_fraction, 200)
	assert_eq(back.inputs.size(), 4)
	assert_eq([back.inputs[0].seq, back.inputs[1].seq, back.inputs[2].seq, back.inputs[3].seq], [1, 0, 0xFFFF, 0xFFFE],
		"redundant copies are consecutive and wrap")
	assert_eq(back.inputs[3].facing, 3000)
	assert_eq(back.inputs[2].shown_delta, 2)
	assert_eq(back.actions[0].action_seq, 0xFFFF)
	assert_eq(back.actions[0].kind, ActionRecord.Kind.TRIGGER)
	assert_eq(back.actions[0].tick, 123456)
	assert_eq(back.actions[0].aim, 40000)
	assert_eq(back.cue_reports[0], PackedInt64Array([99, 4000000001, 128]))


func test_redundant_copies_pack_against_their_newer_neighbour() -> void:
	var still: InputPacket = InputPacket.new()
	var aiming: InputPacket = InputPacket.new()
	for i: int in 4:
		var r: InputRecord = _record(40, InputRecord.Gait.WALK, 1000, InputRecord.HOLD_AIM, 2)
		r.shown_delta = i
		still.inputs.append(r)
		var a: InputRecord = r.duplicate_record()
		a.facing = 1000 + i * 37
		aiming.inputs.append(a)
	var base: int = Protocol.frame(Protocol.Msg.INPUT, PackedByteArray()).size() + 17
	assert_eq(still.encode().size(), base + 7 + 3 * 1, "an unchanged copy costs one byte")
	assert_eq(aiming.encode().size(), base + 7 + 3 * 3, "a copy that only turned costs three")
	var back: InputPacket = _round_trip(aiming)
	for i: int in 4:
		assert_eq(back.inputs[i].facing, 1000 + i * 37)
		assert_eq(back.inputs[i].holds, InputRecord.HOLD_AIM)
		assert_eq(back.inputs[i].shown_delta, i)
	var odd: InputPacket = InputPacket.new()
	odd.inputs.append(_record(1, InputRecord.Gait.RUN, 2, 3, 4))
	var older: InputRecord = _record(200, InputRecord.Gait.CROUCH, 60000, 0, 1)
	older.shown_delta = 9
	odd.inputs.append(older)
	var odd_back: InputRecord = _round_trip(odd).inputs[1]
	assert_eq([odd_back.move_dir, odd_back.gait, odd_back.facing, odd_back.holds, odd_back.desired, odd_back.shown_delta],
		[200, InputRecord.Gait.CROUCH, 60000, 0, 1, 9], "every field can differ")


func test_malformed_packets_are_refused() -> void:
	var p: InputPacket = InputPacket.new()
	p.inputs.append(InputRecord.new())
	var message: Dictionary = Protocol.unframe(p.encode())
	var payload: PackedByteArray = message["payload"]
	assert_not_null(InputPacket.decode(payload))
	assert_null(InputPacket.decode(payload.slice(0, payload.size() - 1)), "truncated")
	assert_null(InputPacket.decode(PackedByteArray()), "empty")
	var too_many: PackedByteArray = payload.duplicate()
	too_many[14] = 9
	assert_null(InputPacket.decode(too_many), "more than eight inputs")
	var two: InputPacket = InputPacket.new()
	two.inputs.append(InputRecord.new())
	two.inputs.append(InputRecord.new())
	message = Protocol.unframe(two.encode())
	var two_payload: PackedByteArray = message["payload"]
	assert_not_null(InputPacket.decode(two_payload))
	two_payload[15 + InputRecord.SIZE] = 0x80
	assert_null(InputPacket.decode(two_payload), "an unknown field-mask bit")
	two_payload[15 + InputRecord.SIZE] = InputRecord.DELTA_FACING | InputRecord.DELTA_HOLDS
	assert_null(InputPacket.decode(two_payload), "a mask promising more bytes than remain")


func test_seq_diff_wraps() -> void:
	assert_eq(InputPacket.seq_diff(0, 0xFFFF), 1)
	assert_eq(InputPacket.seq_diff(0xFFFF, 0), -1)
	assert_eq(InputPacket.seq_diff(100, 90), 10)


## Never: an input field that sets a position, a hit, a light value or a state.
func test_schema_carries_intent_only() -> void:
	var scripts: Array[GDScript] = [InputRecord, ActionRecord, InputPacket]
	var allowed: Array[PackedStringArray] = [
		PackedStringArray(["seq", "shown_delta", "move_dir", "gait", "facing", "holds", "desired"]),
		PackedStringArray(["action_seq", "kind", "arg", "tick", "aim"]),
		PackedStringArray(["ack_frame", "ack_bits", "recv_delay", "shown_tick", "shown_fraction", "newest_seq",
			"inputs", "actions", "cue_reports"]),
	]
	var forbidden: RegEx = RegEx.create_from_string("pos|coord|cell|tile|hit|damage|health|light|lux|state|result|oil|kill")
	for i: int in scripts.size():
		var instance: Object = scripts[i].new()
		var fields: PackedStringArray = PackedStringArray()
		for property: Dictionary in instance.get_property_list():
			var usage: int = property["usage"]
			if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				fields.append(str(property["name"]))
		var expected: PackedStringArray = allowed[i]
		fields.sort()
		expected.sort()
		assert_eq(fields, expected, "%s fields are exactly the reviewed intent fields" % scripts[i].resource_path)
		for field: String in fields:
			assert_null(forbidden.search(field), "%s is not a result field" % field)
	var actions: PackedStringArray = PackedStringArray(ActionRecord.Kind.keys())
	assert_eq(actions, PackedStringArray(["CALLOUT", "LAMP_SIGNAL", "CHALK", "RING_CHOICE", "TRIGGER", "TAP_ROCK", "CLOSE_UP", "WATCH"]),
		"a trigger carries its tick and aim; no action kind reports a hit")
