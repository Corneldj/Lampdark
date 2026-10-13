extends LinkFilter
## The kit's link emulation on one client's connection, until NET-12's emulating filter takes
## its place behind the same LinkFilter face: half the RTT each way on the virtual clock, and
## seeded loss on the unreliable lanes in both directions. Reliable lanes are delayed but never
## dropped, since the in-process transport has no retransmission.

## [due_usec, order, peer, lane, bytes] waiting to go out; [due_usec, order, event] waiting to arrive.
var _out: Array[Array] = []
var _in: Array[Array] = []
var _order: int = 0
var _rng: LbRng
var dropped_up: int = 0
var dropped_down: int = 0
## Virtual send and delivery time of each input packet, by its newest seq (the 60 ms check).
var input_sent_usec: Dictionary = {}
var input_delivered_usec: Dictionary = {}
## Input seqs dropped outright (withhold_inputs): stripped from every packet, copies included.
var withheld_seqs: Dictionary = {}


func _init(wrapped: Transport, seed_value: int) -> void:
	super(wrapped)
	_rng = LbRng.from_seed(seed_value)
	pass_through = false


func filter_send(peer: int, lane: int, raw: PackedByteArray) -> Error:
	var data: PackedByteArray = _strip_withheld(lane, raw)
	if data.is_empty():
		return OK
	var seq: int = _input_seq(lane, data)
	if seq >= 0:
		input_sent_usec[seq] = Transport.now_usec()
	if _idle():
		_note_delivery(lane, data)
		return inner.send(peer, lane, data)
	if _lose(lane):
		dropped_up += 1
		return OK
	_out.append([Transport.now_usec() + rtt_ms * 500, _order, peer, lane, data])
	_order += 1
	_release_out()
	return OK


func filter_receive(events: Array[TransportEvent]) -> Array[TransportEvent]:
	_release_out()
	var now: int = Transport.now_usec()
	var out: Array[TransportEvent] = []
	for event: TransportEvent in events:
		if event.kind != TransportEvent.Kind.MESSAGE or (_idle() and _in.is_empty()):
			out.append(event)
			continue
		if _lose(event.lane):
			dropped_down += 1
			continue
		_in.append([now + rtt_ms * 500, _order, event])
		_order += 1
	var waiting: Array[Array] = []
	for item: Array in _in:
		var due: int = item[0]
		if due <= now:
			var event: TransportEvent = item[2]
			out.append(event)
		else:
			waiting.append(item)
	_in = waiting
	return out


func _release_out() -> void:
	var now: int = Transport.now_usec()
	var waiting: Array[Array] = []
	for item: Array in _out:
		var due: int = item[0]
		if due <= now:
			var peer: int = item[2]
			var lane: int = item[3]
			var bytes: PackedByteArray = item[4]
			_note_delivery(lane, bytes)
			inner.send(peer, lane, bytes)
		else:
			waiting.append(item)
	_out = waiting


## Removes withheld inputs from an input packet. Copies are consecutive, so the packet keeps
## only the inputs newer than the newest withheld one; a packet left with none is not sent.
func _strip_withheld(lane: int, data: PackedByteArray) -> PackedByteArray:
	if withheld_seqs.is_empty() or lane != Lane.Id.INPUTS:
		return data
	var message: Dictionary = Protocol.unframe(data)
	if message.is_empty():
		return data
	var payload: PackedByteArray = message["payload"]
	var packet: InputPacket = InputPacket.decode(payload)
	if packet == null:
		return data
	var kept: Array[InputRecord] = []
	for r: InputRecord in packet.inputs:
		if withheld_seqs.has(r.seq):
			break
		kept.append(r)
	if kept.size() == packet.inputs.size():
		return data
	if kept.is_empty():
		return PackedByteArray()
	packet.inputs = kept
	return packet.encode()


func _note_delivery(lane: int, data: PackedByteArray) -> void:
	var seq: int = _input_seq(lane, data)
	if seq >= 0:
		input_delivered_usec[seq] = Transport.now_usec()


static func _input_seq(lane: int, data: PackedByteArray) -> int:
	if lane != Lane.Id.INPUTS:
		return -1
	var message: Dictionary = Protocol.unframe(data)
	if message.is_empty():
		return -1
	var payload: PackedByteArray = message["payload"]
	var packet: InputPacket = InputPacket.decode(payload)
	return packet.newest_seq if packet != null else -1


func _idle() -> bool:
	return rtt_ms <= 0 and loss_pct <= 0.0 and _out.is_empty()


func _lose(lane: int) -> bool:
	return loss_pct > 0.0 and not Lane.is_reliable(lane) and _rng.chance_ppm(roundi(loss_pct * 10000.0))
