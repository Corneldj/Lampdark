extends GutTest
## NET-03's one-shot actions: queued on the client, resent until a frame header acknowledges
## them, applied by the server exactly once and in order, never by a repeat.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _wire(p: InputPacket) -> InputPacket:
	var message: Dictionary = Protocol.unframe(p.encode())
	var payload: PackedByteArray = message["payload"]
	return InputPacket.decode(payload)


func _applied(c: InputBuffer.Consumed) -> Array[int]:
	var out: Array[int] = []
	for a: ActionRecord in c.actions:
		out.append(a.action_seq)
	return out


func test_actions_are_resent_until_acknowledged() -> void:
	var sender: ClientInputSender = ClientInputSender.new()
	sender.sample(InputRecord.new(), 0)
	assert_eq(sender.queue_action(ActionRecord.Kind.CALLOUT, 3), 0, "action_seq starts at 0")
	assert_eq(sender.queue_action(ActionRecord.Kind.TRIGGER, 0, 41, 9000), 1)
	assert_eq(sender.build_packet(0, 0, 0).actions.size(), 2)
	assert_eq(sender.build_packet(0, 0, 0).actions.size(), 2, "still unacknowledged, so sent again")
	sender.on_frame(5, 0xFFFF, 1, 0)
	assert_eq(sender.pending_actions().size(), 2, "0xFFFF acknowledges nothing yet")
	sender.on_frame(6, 0, 1, 0)
	assert_eq(sender.pending_actions().size(), 1)
	assert_eq(sender.pending_actions()[0].kind, ActionRecord.Kind.TRIGGER)
	assert_eq(sender.pending_actions()[0].tick, 41)
	sender.on_frame(7, 1, 1, 0)
	assert_eq(sender.build_packet(0, 0, 0).actions.size(), 0)


func test_server_applies_each_action_once_in_order() -> void:
	var sender: ClientInputSender = ClientInputSender.new()
	var buffer: InputBuffer = InputBuffer.new()
	sender.queue_action(ActionRecord.Kind.CHALK, 1)
	sender.queue_action(ActionRecord.Kind.LAMP_SIGNAL, 2)
	var applied: Array[int] = []
	for t: int in 6:
		sender.sample(InputRecord.new(), t)
		var p: InputPacket = _wire(sender.build_packet(t, 0, 0))
		buffer.receive(p, t, t, 10)
		buffer.receive(p, t, t, 10)
		applied.append_array(_applied(buffer.consume()))
	assert_eq(applied, [0, 1] as Array[int], "resent six times and duplicated, applied once")
	assert_eq(buffer.action_ack(), 1)


func test_a_later_action_waits_for_an_earlier_one() -> void:
	var buffer: InputBuffer = InputBuffer.new()
	var p: InputPacket = InputPacket.new()
	p.inputs.append(InputRecord.new())
	var second: ActionRecord = ActionRecord.new()
	second.action_seq = 1
	p.actions.append(second)
	buffer.receive(p, 0, 0, 10)
	assert_eq(_applied(buffer.consume()), [] as Array[int], "action 1 waits for action 0")
	assert_eq(buffer.action_ack(), 0xFFFF)
	var first: ActionRecord = ActionRecord.new()
	first.action_seq = 0
	p.actions = [first, second] as Array[ActionRecord]
	p.newest_seq = 1
	buffer.receive(p, 1, 1, 10)
	assert_eq(_applied(buffer.consume()), [0, 1] as Array[int])


func test_repeats_and_stops_never_reapply_an_action() -> void:
	var buffer: InputBuffer = InputBuffer.new()
	var p: InputPacket = InputPacket.new()
	p.inputs.append(InputRecord.new())
	p.actions.append(ActionRecord.new())
	buffer.receive(p, 0, 0, 10)
	var total: int = 0
	for _i: int in 10:
		total += buffer.consume().actions.size()
	assert_eq(total, 1)


func test_action_sequence_wraps() -> void:
	var sender: ClientInputSender = ClientInputSender.new()
	var buffer: InputBuffer = InputBuffer.new()
	sender.next_action_seq = 0xFFFE
	buffer._next_action = 0xFFFE
	for _i: int in 4:
		sender.queue_action(ActionRecord.Kind.RING_CHOICE)
	sender.sample(InputRecord.new(), 0)
	buffer.receive(_wire(sender.build_packet(0, 0, 0)), 0, 0, 10)
	assert_eq(_applied(buffer.consume()), [0xFFFE, 0xFFFF, 0, 1] as Array[int])
	sender.on_frame(1, buffer.action_ack(), 0, 0)
	assert_eq(sender.pending_actions().size(), 0)


func test_an_invalid_action_is_skipped_without_stalling_the_rest() -> void:
	var buffer: InputBuffer = InputBuffer.new()
	var p: InputPacket = InputPacket.new()
	p.inputs.append(InputRecord.new())
	var bad: ActionRecord = ActionRecord.new()
	bad.kind = 9 as ActionRecord.Kind
	var good: ActionRecord = ActionRecord.new()
	good.action_seq = 1
	p.actions = [bad, good] as Array[ActionRecord]
	buffer.receive(p, 0, 0, 10)
	assert_eq(_applied(buffer.consume()), [1] as Array[int])
	assert_eq(buffer.invalid_actions, 1)


func test_frame_acknowledgements_ride_on_the_packet() -> void:
	var sender: ClientInputSender = ClientInputSender.new()
	sender.sample(InputRecord.new(), 0)
	for tick: int in [100, 101, 103, 104]:
		sender.on_frame(tick, 0xFFFF, 2, 1000000)
	var p: InputPacket = sender.build_packet(102, 0, 1000000 + 9000)
	assert_eq(p.ack_frame, 104)
	assert_eq(p.ack_bits, 0b1101, "103, (not 102), 101 and 100 before the newest")
	assert_eq(p.recv_delay, 4, "9 ms in 2 ms units")
	assert_eq(sender.server_depth, 2)


func test_redundancy_carries_the_previous_three() -> void:
	var sender: ClientInputSender = ClientInputSender.new()
	assert_eq(sender.redundancy, 3)
	for t: int in 6:
		var r: InputRecord = InputRecord.new()
		r.move_dir = t
		sender.sample(r, 50 + t)
	var p: InputPacket = sender.build_packet(56, 0, 0)
	assert_eq(p.inputs.size(), 4)
	assert_eq(p.newest_seq, 5)
	assert_eq([p.inputs[0].move_dir, p.inputs[3].move_dir], [5, 2])
	assert_eq([p.inputs[0].shown_delta, p.inputs[3].shown_delta], [1, 4], "each copy keeps its own stamp")
