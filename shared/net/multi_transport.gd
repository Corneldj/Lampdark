class_name MultiTransport
extends Transport
## STM-04: several transports behind NET-02's one channel API, so one server serves its host over
## loopback ENet and friends over SDR at once. Each child keeps its own peers; this maps them into
## disjoint ranges (child i's peer p is i * STRIDE + p). Children listen before they are added;
## connect_to is not offered (a server only listens). Silence timeouts stay with the children.

const STRIDE: int = 1 << 40

var children: Array[Transport] = []


func _init(transports: Array[Transport]) -> void:
	super()
	children = transports
	connection_timeout_usec = 0  # each child times its own peers out


func _send_raw(peer: int, lane: int, data: PackedByteArray) -> Error:
	return children[peer / STRIDE].send(peer % STRIDE, lane, data)


func _poll_raw() -> Array[TransportEvent]:
	var out: Array[TransportEvent] = []
	for i: int in children.size():
		for e: TransportEvent in children[i].poll():
			e.peer += i * STRIDE
			out.append(e)
	return out


func _flush() -> void:
	for t: Transport in children:
		t.flush()


func _disconnect(peer: int) -> void:
	children[peer / STRIDE].disconnect_peer(peer % STRIDE)


func _is_local(peer: int) -> bool:
	return children[peer / STRIDE].is_local_peer(peer % STRIDE)


func verified_identity(peer: int) -> String:
	return children[peer / STRIDE].verified_identity(peer % STRIDE) if peer / STRIDE < children.size() else ""


func stats(peer: int) -> PeerStats:
	var child_stats: PeerStats = children[peer / STRIDE].stats(peer % STRIDE) if peer / STRIDE < children.size() else super.stats(peer)
	var own: PeerStats = super.stats(peer)
	own.rtt_ms = child_stats.rtt_ms
	own.loss = child_stats.loss
	return own


func _close() -> void:
	for t: Transport in children:
		t.close()
