class_name Transport
extends RefCounted
## The one channel API every network path uses (NET-02). ENet (dev, bots, M1, local
## processes), the in-process hub (scenario kit) and SDR (STM-03) implement it; nothing
## above it may assume IP addresses or ports.
##
## Subclasses implement _listen, _connect, _send_raw, _poll_raw, _disconnect and _close.
## This base adds what every transport shares: lane checks, the unreliable size cap,
## last-heard tracking, and silence turning into exactly one DROPPED(timeout) per peer.

## Unreliable payloads above this are refused, so they are never fragmented.
var unreliable_max_bytes: int = 1200
## A peer silent this long is dropped. 0 disables the check.
var connection_timeout_usec: int = 5000000
## The build this runs in (detected from feature tags; tests may replace it).
var build: BuildInfo = BuildInfo.detect(FeatureProvider.new())

var _stats: Dictionary = {}
var _live: Dictionary = {}


func _init() -> void:
	if Tuning.current.has_key(&"net.unreliable_max_bytes"):
		unreliable_max_bytes = Tuning.i(&"net.unreliable_max_bytes")
		connection_timeout_usec = roundi(Tuning.f(&"net.connection_timeout_s") * 1000000.0)


## When >= 0, the transport clock reads this instead of the wall clock: FND-09's scenario kit
## advances it by exactly one tick per step, so handshakes, pings and timeouts replay exactly.
static var virtual_clock_usec: int = -1


static func now_usec() -> int:
	return virtual_clock_usec if virtual_clock_usec >= 0 else Time.get_ticks_usec()


## Starts accepting peers.
func listen(bind_address: String, port: int) -> Error:
	return _listen(bind_address, port)


## Starts connecting. Returns the peer ID, or -1.
func connect_to(host: String, port: int) -> int:
	return _connect(host, port)


## Sends bytes on a lane. An unreliable payload over unreliable_max_bytes is refused.
func send(peer: int, lane: int, data: PackedByteArray) -> Error:
	if lane < 0 or lane >= Lane.COUNT:
		push_error("Transport.send: no lane %d" % lane)
		return ERR_INVALID_PARAMETER
	if not Lane.is_reliable(lane) and data.size() > unreliable_max_bytes:
		push_error("Transport.send: %d bytes exceed the %d-byte unreliable limit on %s" % [
			data.size(), unreliable_max_bytes, Lane.lane_name(lane)])
		return ERR_INVALID_PARAMETER
	if not _live.has(peer):
		return ERR_DOES_NOT_EXIST
	var error: Error = _send_raw(peer, lane, data)
	if error == OK:
		stats(peer).bytes_out += data.size()
	return error


## Everything that happened since the last poll, then any silence timeouts.
func poll() -> Array[TransportEvent]:
	var now: int = now_usec()
	var events: Array[TransportEvent] = []
	for event: TransportEvent in _poll_raw():
		match event.kind:
			TransportEvent.Kind.CONNECTED:
				_live[event.peer] = true
				stats(event.peer).last_heard_usec = now
				events.append(event)
			TransportEvent.Kind.MESSAGE:
				if not _live.has(event.peer):
					continue
				var peer_stats: PeerStats = stats(event.peer)
				peer_stats.last_heard_usec = now
				peer_stats.bytes_in += event.data.size()
				events.append(event)
			TransportEvent.Kind.DROPPED:
				if _live.erase(event.peer):
					events.append(event)
	if connection_timeout_usec > 0:
		for peer: Variant in _live.keys():
			var id: int = int(Variants.number(peer))
			if now - stats(id).last_heard_usec > connection_timeout_usec:
				_live.erase(id)
				_disconnect(id)
				events.append(TransportEvent.dropped(id, "timeout"))
	return events


## Sends anything queued now, rather than at the next poll.
func flush() -> void:
	_flush()


func disconnect_peer(peer: int) -> void:
	if _live.erase(peer):
		_disconnect(peer)


func is_connected_to(peer: int) -> bool:
	return _live.has(peer)


## STM-03: the identity the transport itself authenticated for this peer (SDR: the remote SteamID);
## "" where the transport authenticates nobody (ENet, the in-process hub).
func verified_identity(_peer: int) -> String:
	return ""


## FND-08: the peer runs on this machine (a dev server grants it the debug lane without a token).
func is_local_peer(peer: int) -> bool:
	return _is_local(peer)


func peers() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for peer: Variant in _live.keys():
		out.append(int(Variants.number(peer)))
	out.sort()
	return out


func stats(peer: int) -> PeerStats:
	if not _stats.has(peer):
		_stats[peer] = PeerStats.new()
	var peer_stats: PeerStats = _stats[peer]
	return peer_stats


func close() -> void:
	_live.clear()
	_close()


func _listen(_bind_address: String, _port: int) -> Error:
	return ERR_UNAVAILABLE


func _connect(_host: String, _port: int) -> int:
	return -1


func _send_raw(_peer: int, _lane: int, _data: PackedByteArray) -> Error:
	return ERR_UNAVAILABLE


func _poll_raw() -> Array[TransportEvent]:
	return []


func _is_local(_peer: int) -> bool:
	return false


func _disconnect(_peer: int) -> void:
	pass


func _flush() -> void:
	pass


func _close() -> void:
	pass
