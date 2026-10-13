class_name TransportFilter
extends Transport
## Wraps any transport (NET-02's hook for NET-12's link emulator: delay, jitter, loss,
## duplication). This base passes everything through unchanged. The inner transport keeps
## its own lane checks, size cap, statistics and timeouts.

var inner: Transport


func _init(wrapped: Transport) -> void:
	super()
	inner = wrapped
	build = wrapped.build


func listen(bind_address: String, port: int) -> Error:
	return inner.listen(bind_address, port)


func connect_to(host: String, port: int) -> int:
	return inner.connect_to(host, port)


func send(peer: int, lane: int, data: PackedByteArray) -> Error:
	return filter_send(peer, lane, data)


func poll() -> Array[TransportEvent]:
	return filter_receive(inner.poll())


func disconnect_peer(peer: int) -> void:
	inner.disconnect_peer(peer)


func flush() -> void:
	inner.flush()


func is_local_peer(peer: int) -> bool:
	return inner.is_local_peer(peer)


func is_connected_to(peer: int) -> bool:
	return inner.is_connected_to(peer)


func peers() -> PackedInt64Array:
	return inner.peers()


func stats(peer: int) -> PeerStats:
	return inner.stats(peer)


func close() -> void:
	inner.close()


## Override to delay, drop or duplicate outgoing messages.
func filter_send(peer: int, lane: int, data: PackedByteArray) -> Error:
	return inner.send(peer, lane, data)


## Override to delay, drop or duplicate incoming events.
func filter_receive(events: Array[TransportEvent]) -> Array[TransportEvent]:
	return events
