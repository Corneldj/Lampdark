extends GutTest
## NET-12: the emulator reproduces a configured RTT within +-5 ms and loss within +-0.5 percentage
## points over 10,000 packets; reliable lanes are delayed in order and never dropped; bursty loss
## keeps its long-run rate; a timeline scripts an outage.

const ECHO_LANE: int = Lane.Id.FRAMES

var hub: InProcessTransport.Hub
var server: InProcessTransport
var client_base: InProcessTransport
var link: LinkEmulator
var peer: int = -1
var server_peer: int = -1


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	Transport.virtual_clock_usec = 1000000
	hub = InProcessTransport.Hub.new()
	server = InProcessTransport.new(hub)
	server.listen("kit", 1)
	client_base = InProcessTransport.new(hub)
	link = LinkEmulator.new(client_base, 0, 0.0, 17)
	peer = link.connect_to("kit", 1)
	for e: TransportEvent in server.poll():
		if e.kind == TransportEvent.Kind.CONNECTED:
			server_peer = e.peer
	link.poll()


func after_each() -> void:
	Transport.virtual_clock_usec = -1


## Sends `n` stamped packets up, the server echoing each at once; returns [mean rtt ms, up loss,
## down loss, delivered in order on a reliable lane].
func _run(n: int, lane: int) -> Array:
	var sent_at: Dictionary = {}
	var rtts: Array[float] = []
	var server_got: int = 0
	var order_ok: bool = true
	var last_seen: int = -1
	var i: int = 0
	var step_usec: int = 1000
	while i < n or Transport.virtual_clock_usec < 1000000 + n * step_usec + 2000000:
		if i < n:
			var b: PackedByteArray = PackedByteArray()
			b.resize(4)
			b.encode_u32(0, i)
			sent_at[i] = Transport.now_usec()
			link.send(peer, lane, b)
			link.flush()
			i += 1
		for e: TransportEvent in server.poll():
			if e.kind == TransportEvent.Kind.MESSAGE:
				server_got += 1
				server.send(server_peer, e.lane, e.data)
		server.flush()
		for e: TransportEvent in link.poll():
			if e.kind == TransportEvent.Kind.MESSAGE:
				var k: int = e.data.decode_u32(0)
				if k < last_seen:
					order_ok = false
				last_seen = maxi(last_seen, k)
				rtts.append((Transport.now_usec() - int(Variants.number(sent_at[k]))) / 1000.0)
		Transport.virtual_clock_usec += step_usec
	var mean: float = 0.0
	for r: float in rtts:
		mean += r
	mean /= maxf(1.0, rtts.size())
	var up_loss: float = 1.0 - float(server_got) / n
	var down_loss: float = 1.0 - float(rtts.size()) / maxf(1.0, server_got)
	return [mean, up_loss, down_loss, order_ok]


func test_rtt_and_loss_over_10000_packets() -> void:
	link.configure(120, 2.0)
	var r: Array = _run(10000, ECHO_LANE)
	assert_almost_eq(float(Variants.number(r[0])), 120.0, 5.0, "mean round trip %.1f ms" % float(Variants.number(r[0])))
	assert_almost_eq(float(Variants.number(r[1])), 0.02, 0.005, "up loss %.4f" % float(Variants.number(r[1])))
	assert_almost_eq(float(Variants.number(r[2])), 0.02, 0.005, "down loss %.4f" % float(Variants.number(r[2])))
	assert_eq(link.up.sent, 10000)


func test_reliable_lanes_delay_in_order_and_never_drop() -> void:
	link.configure(80, 30.0)
	var r: Array = _run(2000, Lane.Id.CONTROL)
	assert_almost_eq(float(Variants.number(r[0])), 80.0, 12.0)
	assert_eq(float(Variants.number(r[1])), 0.0, "never dropped up")
	assert_eq(float(Variants.number(r[2])), 0.0, "nor down")
	assert_true(Variants.flag(r[3]), "and in order")


func test_bursty_loss_keeps_its_long_run_rate() -> void:
	link.configure(40, 0.0)
	link.set_burst(0.01, 0.24)  # bad 4% of the time, losing everything then
	var r: Array = _run(10000, ECHO_LANE)
	assert_almost_eq(float(Variants.number(r[1])), 0.01 / (0.01 + 0.24), 0.012, "up loss %.4f" % float(Variants.number(r[1])))


func test_a_scripted_outage() -> void:
	link.configure(40, 0.0)
	link.timeline = [{"at_s": 2.0, "both": {"loss": 1.0}}, {"at_s": 4.0, "both": {"loss": 0.0}}] as Array[Dictionary]
	var r: Array = _run(6000, ECHO_LANE)  # 6 s of packets, 2 s of them in the outage
	assert_almost_eq(float(Variants.number(r[1])), 2.0 / 6.0, 0.01, "a third lost up")
