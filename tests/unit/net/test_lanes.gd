extends GutTest
## Lanes over real ENet through a lossy UDP link (NET-02): reliable lanes deliver everything in
## order under 5% loss; unreliable lanes never deliver an older message after a newer one.

const Emulator = preload("res://tests/support/udp_link_emulator.gd")
const Pump = preload("res://tests/support/net_pump.gd")

var server: EnetTransport
var client: EnetTransport
var link: Emulator
var server_peer: int = -1
var client_peer: int = -1
## lane -> received sequence numbers, per direction
var at_server: Dictionary = {}
var at_client: Dictionary = {}


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	server = EnetTransport.new()
	assert_eq(server.listen("127.0.0.1", 0), OK)
	link = Emulator.new()
	var link_port: int = link.start(server.bound_port())
	client = EnetTransport.new()
	client_peer = client.connect_to("127.0.0.1", link_port)
	at_server.clear()
	at_client.clear()
	server_peer = -1
	assert_true(Pump.until(_step, func() -> bool: return server_peer > 0 and client.is_connected_to(client_peer), 5.0), "connected")


func after_each() -> void:
	client.close()
	server.close()
	link.close()


func _step() -> void:
	link.pump(Time.get_ticks_usec())
	for event: TransportEvent in server.poll():
		if event.kind == TransportEvent.Kind.CONNECTED:
			server_peer = event.peer
		elif event.kind == TransportEvent.Kind.MESSAGE:
			_record(at_server, event)
	link.pump(Time.get_ticks_usec())
	for event: TransportEvent in client.poll():
		if event.kind == TransportEvent.Kind.MESSAGE:
			_record(at_client, event)


func _record(into: Dictionary, event: TransportEvent) -> void:
	var list: PackedInt64Array = into.get(event.lane, PackedInt64Array())
	list.append(event.data.decode_s64(0))
	into[event.lane] = list


func _seq(n: int) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, n)
	return bytes


func _received(into: Dictionary, lane: int) -> PackedInt64Array:
	var list: PackedInt64Array = into.get(lane, PackedInt64Array())
	return list


func test_all_five_lanes_both_ways() -> void:
	for lane: int in Lane.COUNT:
		assert_eq(client.send(client_peer, lane, _seq(lane)), OK)
		assert_eq(server.send(server_peer, lane, _seq(100 + lane)), OK)
	assert_true(Pump.until(_step, func() -> bool:
		for lane: int in Lane.COUNT:
			if _received(at_server, lane).is_empty() or _received(at_client, lane).is_empty():
				return false
		return true, 5.0), "every lane delivered both ways")
	for lane: int in Lane.COUNT:
		assert_eq(_received(at_server, lane), PackedInt64Array([lane]))
		assert_eq(_received(at_client, lane), PackedInt64Array([100 + lane]))


func test_reliable_lanes_deliver_everything_in_order_under_5_percent_loss() -> void:
	link.loss_ppm = 50000
	link.jitter_usec = 3000
	var total: int = 10000
	var bulk_total: int = 2000
	# Lambdas capture locals by value, so the counters live in an Array.
	var sent: PackedInt64Array = PackedInt64Array([0, 0])
	var counters: Array = [sent]
	var done: bool = Pump.until(func() -> void:
		var c: PackedInt64Array = counters[0]
		for _i: int in 200:
			if c[0] < total:
				client.send(client_peer, Lane.Id.CONTROL, _seq(c[0]))
				c[0] += 1
			if c[1] < bulk_total:
				client.send(client_peer, Lane.Id.BULK, _seq(c[1]))
				c[1] += 1
		counters[0] = c
		_step(),
		func() -> bool: return _received(at_server, Lane.Id.CONTROL).size() >= total and _received(at_server, Lane.Id.BULK).size() >= bulk_total,
		90.0)
	assert_true(done, "all reliable messages arrived (control %d, bulk %d)" % [
		_received(at_server, Lane.Id.CONTROL).size(), _received(at_server, Lane.Id.BULK).size()])
	var expected: PackedInt64Array = PackedInt64Array()
	for i: int in total:
		expected.append(i)
	assert_eq(_received(at_server, Lane.Id.CONTROL), expected, "control: every message, in order")
	assert_eq(_received(at_server, Lane.Id.BULK), expected.slice(0, bulk_total), "bulk: every message, in order")
	var loss_rate: float = float(link.dropped) / float(link.dropped + link.forwarded)
	assert_between(loss_rate, 0.03, 0.07, "the link dropped about 5%% of datagrams (%.1f%% of %d)" % [
		loss_rate * 100.0, link.dropped + link.forwarded])


func test_unreliable_lanes_never_deliver_an_older_message_after_a_newer_one() -> void:
	link.loss_ppm = 50000
	link.jitter_usec = 30000
	var count: int = 1500
	var counters: Array = [0]
	Pump.until(func() -> void:
		for _i: int in 5:
			var n: int = counters[0]
			if n < count:
				for lane: int in [Lane.Id.INPUTS, Lane.Id.VOICE]:
					client.send(client_peer, lane, _seq(n))
				server.send(server_peer, Lane.Id.FRAMES, _seq(n))
				counters[0] = n + 1
		_step(),
		func() -> bool: return int(Variants.number(counters[0])) >= count,
		10.0)
	Pump.until(_step, func() -> bool: return false, 0.3)
	var lanes: Array[Array] = [[at_server, Lane.Id.INPUTS], [at_server, Lane.Id.VOICE], [at_client, Lane.Id.FRAMES]]
	for pair: Array in lanes:
		var into: Dictionary = pair[0]
		var lane: int = pair[1]
		var got: PackedInt64Array = _received(into, lane)
		assert_gt(got.size(), count / 10, "%s delivered messages (%d)" % [Lane.lane_name(lane), got.size()])
		var ordered: bool = true
		for i: int in range(1, got.size()):
			if got[i] <= got[i - 1]:
				ordered = false
		assert_true(ordered, "%s never went backwards" % Lane.lane_name(lane))
		assert_lt(got.size(), count, "%s lost or discarded some, as unreliable lanes may" % Lane.lane_name(lane))
	assert_gt(link.reordered, 50, "the link really reordered datagrams (%d)" % link.reordered)
