class_name InputService
extends SimSystem
## Stage 2 of the tick (NET-03): feeds each welcomed client's input packets into its
## InputBuffer and consumes exactly one input per client. Systems read the result through
## RunState.input_for(slot). input_starved goes to MNR-04 (cancel, nothing spent), MNR-01 (stop)
## and NET-11; input_resumed clears it. Hired Hands (MOD-08) write the same records.

signal input_starved(slot: int)
signal input_resumed(slot: int)

var net: ServerNet
var tick_ms: float = 50.0
var interp_ms: float = 100.0
var grace_ms: float = 250.0
var unknown_messages: int = 0
## FND-09: every applied input is appended here when set.
var recorder: InputLog = null
## FND-09's replay: when set, inputs come from this log by tick and the network is ignored.
var replay: InputLog = null
var _buffers: Dictionary = {}
var _current: Dictionary = {}
## slot -> counters of sessions that have dropped, so end-of-run stats keep them.
var _finished: Dictionary = {}
## A running hash of every input applied, in order: part of the run's state, so a replay or a
## second run that applies anything different cannot reach the same state hash (FND-09).
var applied_digest: int = 0


func _init(server_net: ServerNet) -> void:
	net = server_net
	if Tuning.current.has_key(&"net.tick_hz"):
		tick_ms = 1000.0 / Tuning.f(&"net.tick_hz")
		interp_ms = Tuning.f(&"net.interp_delay_ms")
		grace_ms = Tuning.f(&"net.input_stamp_grace_ms")


func stage() -> int:
	return StageTable.Stage.INPUTS


func order() -> int:
	return 0


func buffer_for(slot: int) -> InputBuffer:
	if not _buffers.has(slot):
		_buffers[slot] = InputBuffer.new()
	var buffer: InputBuffer = _buffers[slot]
	return buffer


## What this tick consumed for a slot; null before its first input.
func input_for(slot: int) -> InputBuffer.Consumed:
	if not _current.has(slot):
		return null
	var consumed: InputBuffer.Consumed = _current[slot]
	return consumed


func tick(run: RunState) -> void:
	if replay != null:
		_replay_tick(run)
		return
	for slot: int in net.dropped_slots:
		if _buffers.has(slot):
			Log.info("inputs at drop: " + _describe(slot))
			_finished[slot] = _merge(Variants.dict(_finished.get(slot, {})), _counters(buffer_for(slot)))
		_buffers.erase(slot)
		_current.erase(slot)
	var peers: Dictionary = {}
	for session: Sessions.Session in net.sessions.welcomed():
		peers[session.slot] = session.peer
	var routed: Array = Variants.array(net.routed.get(Lane.Id.INPUTS, []))
	net.routed.erase(Lane.Id.INPUTS)
	for raw: Variant in routed:
		var item: Array = Variants.array(raw)
		var slot: int = item[0]
		var type: int = item[1]
		var payload: PackedByteArray = item[2]
		var packet: InputPacket = InputPacket.decode(payload) if type == Protocol.Msg.INPUT else null
		if packet == null or not peers.has(slot):
			unknown_messages += 1
			continue
		var peer: int = peers[slot]
		if run.replication != null:
			run.replication.on_ack(slot, run.tick, packet.ack_frame, packet.ack_bits)
		var plausible_ms: float = net.transport.stats(peer).rtt_ms + interp_ms + grace_ms
		# The newest frame this client can have seen is the one sent at the end of the last tick.
		buffer_for(slot).receive(packet, run.tick, run.tick - 1, ceili(plausible_ms / tick_ms))
	_current.clear()
	for session: Sessions.Session in net.sessions.welcomed():
		var consumed: InputBuffer.Consumed = buffer_for(session.slot).consume()
		if consumed == null:
			continue
		_current[session.slot] = consumed
		_fold(run.tick, session.slot, consumed)
		if run.now_judge != null:
			run.now_judge.on_consumed(run.tick, session.slot, consumed)
		if recorder != null:
			recorder.append(run.tick, session.slot, consumed)
		if consumed.starved_now:
			input_starved.emit(session.slot)
		if consumed.resumed_now:
			input_resumed.emit(session.slot)


func _replay_tick(run: RunState) -> void:
	net.routed.erase(Lane.Id.INPUTS)
	_current.clear()
	for raw: Variant in Variants.array(replay.by_tick.get(run.tick, [])):
		var item: Array = Variants.array(raw)
		var slot: int = item[0]
		var consumed: InputBuffer.Consumed = item[1]
		_current[slot] = consumed
		_fold(run.tick, slot, consumed)
		if run.now_judge != null:
			run.now_judge.on_consumed(run.tick, slot, consumed)
		if recorder != null:
			recorder.append(run.tick, slot, consumed)
		if consumed.starved_now:
			input_starved.emit(slot)
		if consumed.resumed_now:
			input_resumed.emit(slot)


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(applied_digest)


func read_state(reader: SimStateReader) -> void:
	applied_digest = reader.get_i64()


func _fold(at_tick: int, slot: int, c: InputBuffer.Consumed) -> void:
	var keys: PackedInt64Array = PackedInt64Array([at_tick, slot, InputLog.flags_of(c), _packed(c.record)])
	for a: ActionRecord in c.actions:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		a.pack(b)
		var bytes: PackedByteArray = b.data_array
		bytes.resize(16)
		keys.append(bytes.decode_s64(0))
		keys.append(bytes.decode_s64(8))
	for r: PackedInt64Array in c.cue_reports:
		keys.append_array(r)
	applied_digest = LbHash.hash(applied_digest, HashDomain.NET_INPUT_DIGEST, keys)


static func _packed(record: InputRecord) -> int:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	record.pack(b)
	var bytes: PackedByteArray = b.data_array
	bytes.resize(8)
	return bytes.decode_s64(0)


## The newest one-shot action applied for a slot (for the frame header).
func action_ack(slot: int) -> int:
	return buffer_for(slot).action_ack() if _buffers.has(slot) else 0xFFFF


## The input last applied for a slot (for the frame header; NET-05 reconciles against it).
func input_ack(slot: int) -> int:
	return buffer_for(slot).applied_seq() if _buffers.has(slot) else 0xFFFF


## Inputs buffered for a slot (for the frame header; NET-05 nudges its clock by it).
func depth(slot: int) -> int:
	return buffer_for(slot).depth() if _buffers.has(slot) else 0


## Per-slot input counters for the server's stats log, or "" before any input.
func summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var slots: Array = _buffers.keys()
	slots.sort()
	for slot: Variant in slots:
		parts.append(_describe(int(Variants.number(slot))))
	return "; ".join(parts)


func _describe(slot: int) -> String:
	var b: InputBuffer = buffer_for(slot)
	return "slot %d: %d real, %d repeated, %d gaps, %d late, %d clamped stamps, %d invalid" % [
		slot, b.real_count, b.repeat_count, b.gaps, b.dropped_old, b.clamped_stamps, b.invalid + b.invalid_actions]


## Per-slot input counters for the stats file: every session that ever held the slot.
func counters() -> Dictionary:
	var out: Dictionary = {}
	for slot: Variant in _finished.keys():
		out[str(slot)] = _finished[slot]
	for slot: Variant in _buffers.keys():
		var b: InputBuffer = _buffers[slot]
		out[str(slot)] = _merge(Variants.dict(out.get(str(slot), {})), _counters(b))
	return out


static func _counters(b: InputBuffer) -> Dictionary:
	return {"real": b.real_count, "repeated": b.repeat_count, "gaps": b.gaps, "gap_ticks": b.gap_ticks,
		"starved": b.starved_count, "late": b.dropped_old, "ahead": b.dropped_ahead,
		"clamped_stamps": b.clamped_stamps, "invalid": b.invalid + b.invalid_actions}


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a.duplicate()
	for key: Variant in b.keys():
		out[key] = int(Variants.number(out.get(key, 0))) + int(Variants.number(b[key]))
	return out
