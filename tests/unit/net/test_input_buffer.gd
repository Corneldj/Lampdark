extends GutTest
## NET-03's server input buffer: one input per tick, dedupe, ordering, the 200 ms repeat then
## stop, resume from the newest input, and the stamp sanity bound.

var buffer: InputBuffer
var tick: int = 0


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	buffer = InputBuffer.new()
	tick = 100


## A packet whose newest input is `newest`, with `copies` inputs; each input's move_dir is its
## seq modulo 200, so a test can tell which input was consumed.
func _packet(newest: int, copies: int = 4, shown: int = -1) -> InputPacket:
	var p: InputPacket = InputPacket.new()
	p.newest_seq = newest & 0xFFFF
	p.shown_tick = shown if shown >= 0 else tick - 3
	for i: int in copies:
		var r: InputRecord = InputRecord.new()
		r.seq = (newest - i) & 0xFFFF
		r.move_dir = r.seq % 200
		r.holds = InputRecord.HOLD_FEEL
		r.shown_delta = i
		p.inputs.append(r)
	return p


func _receive(p: InputPacket) -> void:
	buffer.receive(p, tick, tick - 1, 10)


func _consume() -> InputBuffer.Consumed:
	tick += 1
	return buffer.consume()


func test_tuning_sets_the_window() -> void:
	assert_eq(buffer.target, 1)
	assert_eq(buffer.max_ahead, 8)
	assert_eq(buffer.repeat_limit, 4, "200 ms at 20 Hz")


func test_nothing_before_the_first_input() -> void:
	assert_null(_consume())


func test_one_input_per_tick_in_order_behind_the_newest() -> void:
	_receive(_packet(10))
	var first: InputBuffer.Consumed = _consume()
	assert_true(first.real)
	assert_false(first.resumed_now, "a session's first input is not a resume")
	assert_eq(first.record.move_dir, 10, "the first input applies at once")
	_receive(_packet(11))
	var hold: InputBuffer.Consumed = _consume()
	assert_false(hold.real)
	assert_eq(hold.record.move_dir, 10, "then holds for the target depth while input 11 waits")
	for s: int in range(12, 21):
		_receive(_packet(s))
		var c: InputBuffer.Consumed = _consume()
		assert_true(c.real)
		assert_eq(c.record.move_dir, s - 1, "one tick behind the newest received")
	assert_eq(buffer.depth(), 1)
	assert_eq(buffer.real_count, 10)
	assert_eq(buffer.repeat_count, 0, "the depth-building hold is not a repeat")
	assert_eq(buffer.gaps, 0)


func test_duplicates_are_consumed_once() -> void:
	_receive(_packet(10))
	_receive(_packet(10))
	_receive(_packet(9))
	assert_eq(_consume().record.move_dir, 10)
	assert_false(_consume().real, "the depth-building hold")
	_receive(_packet(11))
	_receive(_packet(11))
	assert_eq(_consume().record.move_dir, 11)
	var after: InputBuffer.Consumed = _consume()
	assert_false(after.real, "input 11 was consumed once, not twice")
	assert_eq(after.record.move_dir, 11, "a repeat re-applies the held input")
	assert_eq(buffer.repeat_count, 1)


func test_out_of_order_packets_are_consumed_in_order() -> void:
	_receive(_packet(10, 1))
	_receive(_packet(13, 1))
	_receive(_packet(11, 1))
	_receive(_packet(12, 1))
	var seen: Array[int] = []
	var real: Array[bool] = []
	for _i: int in 5:
		var c: InputBuffer.Consumed = _consume()
		seen.append(c.record.move_dir)
		real.append(c.real)
	assert_eq(seen, [10, 10, 11, 12, 13] as Array[int])
	assert_eq(real, [true, false, true, true, true] as Array[bool])


func test_a_lost_packet_is_covered_by_the_next_ones_copies() -> void:
	_receive(_packet(10))
	_consume()
	_receive(_packet(11))
	_consume()
	# Packet 12 is lost; 13 carries 12 again, and arrives before 12 is due.
	var c: InputBuffer.Consumed = _consume()
	assert_true(c.real)
	assert_eq(c.record.move_dir, 11)
	_receive(_packet(13))
	c = _consume()
	assert_true(c.real)
	assert_eq(c.record.move_dir, 12, "the lost input came in the next packet's copies")
	c = _consume()
	assert_eq(c.record.move_dir, 13)
	assert_eq(buffer.repeat_count, 0)


func test_late_and_far_ahead_inputs_are_dropped_and_counted() -> void:
	_receive(_packet(10, 1))
	_consume()
	_consume()
	_receive(_packet(10, 1))
	assert_eq(buffer.dropped_old, 1, "an input already consumed is dropped")
	_receive(_packet(30, 1))
	assert_eq(buffer.dropped_ahead, 1, "more than eight ticks ahead is dropped")
	assert_eq(buffer.depth(), 0)


func test_repeats_for_200_ms_then_stops() -> void:
	_receive(_packet(10))
	assert_true(_consume().real)
	assert_false(_consume().real, "the depth-building hold")
	# Inputs stop. Four repeats (200 ms) re-apply the held state, then the miner stops.
	for i: int in 4:
		var c: InputBuffer.Consumed = _consume()
		assert_false(c.real)
		assert_false(c.starved, "repeat %d is not yet a stop" % (i + 1))
		assert_eq(c.record.move_dir, 10)
		assert_eq(c.record.holds, InputRecord.HOLD_FEEL, "held controls stay held while repeating")
	var stop: InputBuffer.Consumed = _consume()
	assert_true(stop.starved)
	assert_true(stop.starved_now, "input_starved fires on the fifth missing tick")
	assert_eq(stop.record.move_dir, InputRecord.NO_DIRECTION)
	assert_eq(stop.record.holds, 0, "held controls are released")
	var after: InputBuffer.Consumed = _consume()
	assert_true(after.starved)
	assert_false(after.starved_now, "the signal fires once")


func test_resume_starts_from_the_newest_input() -> void:
	_receive(_packet(10))
	_consume()
	_consume()
	for _i: int in 6:
		_consume()
	assert_true(buffer.starved)
	_receive(_packet(40))
	var resumed: InputBuffer.Consumed = _consume()
	assert_true(resumed.real)
	assert_true(resumed.resumed_now)
	assert_eq(resumed.record.move_dir, 40, "the newest input, older buffered ones discarded")
	var held: InputBuffer.Consumed = _consume()
	assert_eq(held.record.move_dir, 40, "held while the buffer refills to its target depth")
	assert_false(held.resumed_now)
	_receive(_packet(41))
	_receive(_packet(42))
	assert_eq(_consume().record.move_dir, 41)
	assert_eq(_consume().record.move_dir, 42)


func test_stamps_outside_the_plausible_window_are_clamped_and_counted() -> void:
	_receive(_packet(10, 1, tick - 2))
	assert_eq(buffer.clamped_stamps, 0)
	assert_eq(_consume().shown_tick, 98)
	_consume()
	var newest_frame: int = tick - 1
	_receive(_packet(11, 1, tick + 50))
	assert_eq(buffer.clamped_stamps, 1, "a stamp from the future")
	assert_eq(_consume().shown_tick, newest_frame, "clamped to the newest frame sent")
	var lowest: int = tick - 10
	_receive(_packet(12, 1, tick - 50))
	assert_eq(buffer.clamped_stamps, 2, "a stamp older than the bound")
	assert_eq(_consume().shown_tick, lowest, "clamped to the oldest plausible tick")


func test_redundant_copies_keep_their_own_stamp() -> void:
	_receive(_packet(10, 4, 90))
	assert_eq(_consume().shown_tick, 90)
	_consume()
	_receive(_packet(12, 4, 95))
	assert_eq(_consume().shown_tick, 94, "input 11 was stamped one tick before its packet")
	assert_eq(_consume().shown_tick, 95)


func test_invalid_records_are_skipped() -> void:
	var p: InputPacket = _packet(10, 1)
	p.inputs[0].desired = 7
	_receive(p)
	assert_eq(buffer.invalid, 1)
