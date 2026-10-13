class_name EnetTransport
extends Transport
## The ENet transport (NET-02): development, bots, M1 direct connections and local processes.
## Godot's low-level ENetConnection, one ENet channel per lane. Reliable lanes use
## FLAG_RELIABLE; unreliable lanes use ENet's default unreliable sequenced delivery, so an
## older packet is never delivered after a newer one. Godot's MultiplayerAPI is not used.

const MAX_PEERS: int = 32

var _host: ENetConnection = null
## int peer id -> ENetPacketPeer, and back.
var _peers: Dictionary = {}
var _ids: Dictionary = {}
var _next_peer: int = 1


## Release builds refuse any address but 127.0.0.1, so no Steam release build opens a port
## (online play goes through SDR, STM-03). Dev, QA and kill-test builds may bind anywhere.
func _listen(bind_address: String, port: int) -> Error:
	if build.is_release() and bind_address != "127.0.0.1":
		push_error("EnetTransport: release builds bind only to 127.0.0.1, not %s" % bind_address)
		return ERR_UNAUTHORIZED
	_host = ENetConnection.new()
	var error: Error = _host.create_host_bound(bind_address, port, MAX_PEERS, Lane.COUNT)
	if error != OK:
		_host = null
	return error


func _connect(host: String, port: int) -> int:
	if _host == null:
		_host = ENetConnection.new()
		if _host.create_host(1, Lane.COUNT) != OK:
			_host = null
			return -1
	var peer: ENetPacketPeer = _host.connect_to_host(host, port, Lane.COUNT)
	if peer == null:
		return -1
	return _register(peer)


func _send_raw(peer: int, lane: int, data: PackedByteArray) -> Error:
	if not _peers.has(peer):
		return ERR_DOES_NOT_EXIST
	var packet_peer: ENetPacketPeer = _peers[peer]
	var flags: int = ENetPacketPeer.FLAG_RELIABLE if Lane.is_reliable(lane) else 0
	return packet_peer.send(lane, data, flags) as Error


func _poll_raw() -> Array[TransportEvent]:
	var events: Array[TransportEvent] = []
	if _host == null:
		return events
	while true:
		var result: Array = _host.service(0)
		var type: int = int(Variants.number(result[0]))
		if type == ENetConnection.EVENT_NONE or type == ENetConnection.EVENT_ERROR:
			break
		var packet_peer: ENetPacketPeer = result[1]
		match type:
			ENetConnection.EVENT_CONNECT:
				# ENet's throttle drops unreliable packets at the sender when RTT rises. Inputs and
				# frames carry their own redundancy (NET-03, NET-04), so it stays fully open. Set
				# once connected: configuring a peer mid-handshake breaks the handshake.
				packet_peer.throttle_configure(5000, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)
				events.append(TransportEvent.connected(_register(packet_peer)))
			ENetConnection.EVENT_DISCONNECT:
				if _ids.has(packet_peer):
					var id: int = int(Variants.number(_ids[packet_peer]))
					_forget(id)
					events.append(TransportEvent.dropped(id, "disconnected"))
			ENetConnection.EVENT_RECEIVE:
				var lane: int = int(Variants.number(result[3]))
				var data: PackedByteArray = packet_peer.get_packet()
				if _ids.has(packet_peer):
					events.append(TransportEvent.message(int(Variants.number(_ids[packet_peer])), lane, data))
	for id: Variant in _peers.keys():
		var packet_peer: ENetPacketPeer = _peers[id]
		var peer_stats: PeerStats = stats(int(Variants.number(id)))
		peer_stats.rtt_ms = packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
		peer_stats.loss = packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE)
	return events


func _disconnect(peer: int) -> void:
	if _peers.has(peer):
		var packet_peer: ENetPacketPeer = _peers[peer]
		packet_peer.peer_disconnect_now()
		_forget(peer)


func _flush() -> void:
	if _host != null:
		_host.flush()


func _close() -> void:
	if _host != null:
		for id: Variant in _peers.keys():
			var packet_peer: ENetPacketPeer = _peers[id]
			packet_peer.peer_disconnect_now()
		_host.flush()
		_host.destroy()
		_host = null
	_peers.clear()
	_ids.clear()


## The UDP port actually bound (useful when listening on port 0).
func bound_port() -> int:
	return _host.get_local_port() if _host != null else 0


func _is_local(peer: int) -> bool:
	if not _peers.has(peer):
		return false
	var p: ENetPacketPeer = _peers[peer]
	var address: String = p.get_remote_address()
	return address == "127.0.0.1" or address == "::1" or address == "::ffff:127.0.0.1"


func _register(packet_peer: ENetPacketPeer) -> int:
	if _ids.has(packet_peer):
		return int(Variants.number(_ids[packet_peer]))
	var id: int = _next_peer
	_next_peer += 1
	_peers[id] = packet_peer
	_ids[packet_peer] = id
	# ENet's own timeout stays longer than ours, so silence is reported once, by the base.
	packet_peer.set_timeout(32, 30000, 60000)
	return id


func _forget(id: int) -> void:
	if _peers.has(id):
		_ids.erase(_peers[id])
		_peers.erase(id)
