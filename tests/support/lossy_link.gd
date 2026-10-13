extends TransportFilter
## A deterministic lossy link over the in-process transport, on a virtual clock: unreliable
## lanes are delayed by `delay_steps` calls to advance(), dropped and duplicated by seeded
## chance. Reliable lanes pass with the same delay and are never dropped (the in-process
## transport has no retransmission). NET-12 builds the full emulator.

var loss_ppm: int = 0
var duplicate_ppm: int = 0
var delay_steps: int = 0
var dropped: int = 0
var duplicated: int = 0
## [steps left, peer, lane, bytes]
var _queue: Array[Array] = []
var _rng: LbRng


func _init(wrapped: Transport, seed_value: int) -> void:
	super(wrapped)
	_rng = LbRng.from_seed(seed_value)


func filter_send(peer: int, lane: int, data: PackedByteArray) -> Error:
	if not inner.is_connected_to(peer):
		return ERR_DOES_NOT_EXIST
	var copies: int = 1
	if not Lane.is_reliable(lane):
		if loss_ppm > 0 and _rng.chance_ppm(loss_ppm):
			dropped += 1
			return OK
		if duplicate_ppm > 0 and _rng.chance_ppm(duplicate_ppm):
			duplicated += 1
			copies = 2
	for _i: int in copies:
		_queue.append([delay_steps, peer, lane, data])
	if delay_steps == 0:
		advance()
	return OK


## One step of virtual time: sends whatever is due.
func advance() -> void:
	var waiting: Array[Array] = []
	for item: Array in _queue:
		var steps: int = item[0]
		if steps > 0:
			item[0] = steps - 1
			waiting.append(item)
			continue
		var peer: int = item[1]
		var lane: int = item[2]
		var bytes: PackedByteArray = item[3]
		inner.send(peer, lane, bytes)
	_queue = waiting
