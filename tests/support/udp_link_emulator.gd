extends RefCounted
## A UDP proxy between one client and a server, for transport tests (NET-02). It drops,
## delays, jitters (and so reorders) or blackholes datagrams below ENet's own reliability,
## so reliable lanes must really retransmit. NET-12 builds the full emulator.

var loss_ppm: int = 0
var delay_usec: int = 0
var jitter_usec: int = 0
var blackhole: bool = false

var _client_side: PacketPeerUDP = PacketPeerUDP.new()
var _server_side: PacketPeerUDP = PacketPeerUDP.new()
var _client_ip: String = ""
var _client_port: int = 0
var _rng: LbRng = LbRng.from_seed(0x11C0)
## Array of [release_usec, sequence, to_server, bytes]
var _queue: Array[Array] = []
var _sequence: int = 0
var forwarded: int = 0
## Every datagram the client sent and its UDP payload bytes, counted before any loss (NET-03's
## uplink measurement adds the 28 bytes of IPv4 and UDP headers per datagram).
var client_datagrams: int = 0
var client_bytes: int = 0
## STM-04: server to client, as the client's datagrams (UDP payload; add 28 per datagram for IPv4 and UDP).
var server_datagrams: int = 0
var server_bytes: int = 0
var dropped: int = 0
## Datagrams released after a later-arriving one in the same direction.
var reordered: int = 0
var _last_released: Dictionary = {true: -1, false: -1}


## Listens on a free local port and forwards to the server. Returns the port to connect to.
func start(server_port: int) -> int:
	if _client_side.bind(0, "127.0.0.1") != OK:
		return -1
	_server_side.bind(0, "127.0.0.1")
	_server_side.set_dest_address("127.0.0.1", server_port)
	return _client_side.get_local_port()


func pump(now_usec: int) -> void:
	while _client_side.get_available_packet_count() > 0:
		var bytes: PackedByteArray = _client_side.get_packet()
		client_datagrams += 1
		client_bytes += bytes.size()
		_client_ip = _client_side.get_packet_ip()
		_client_port = _client_side.get_packet_port()
		_schedule(now_usec, true, bytes)
	while _server_side.get_available_packet_count() > 0:
		var down: PackedByteArray = _server_side.get_packet()
		server_datagrams += 1
		server_bytes += down.size()
		_schedule(now_usec, false, down)
	_queue.sort_custom(func(a: Array, b: Array) -> bool:
		var a_time: int = a[0]
		var b_time: int = b[0]
		var a_seq: int = a[1]
		var b_seq: int = b[1]
		return a_time < b_time or (a_time == b_time and a_seq < b_seq))
	while not _queue.is_empty():
		var head: Array = _queue[0]
		var release: int = head[0]
		if release > now_usec:
			break
		var item: Array = _queue.pop_front()
		var bytes: PackedByteArray = item[3]
		var to_server: bool = item[2]
		var sequence: int = item[1]
		var last: int = _last_released[to_server]
		if sequence < last:
			reordered += 1
		else:
			_last_released[to_server] = sequence
		if to_server:
			_server_side.put_packet(bytes)
		elif not _client_ip.is_empty():
			_client_side.set_dest_address(_client_ip, _client_port)
			_client_side.put_packet(bytes)
		forwarded += 1


func close() -> void:
	_client_side.close()
	_server_side.close()


func _schedule(now_usec: int, to_server: bool, bytes: PackedByteArray) -> void:
	if blackhole or (loss_ppm > 0 and _rng.chance_ppm(loss_ppm)):
		dropped += 1
		return
	var release: int = now_usec + delay_usec + (_rng.range(0, jitter_usec) if jitter_usec > 0 else 0)
	_queue.append([release, _sequence, to_server, bytes])
	_sequence += 1
