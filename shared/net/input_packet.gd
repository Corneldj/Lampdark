class_name InputPacket
extends RefCounted
## The client's packet each tick (NET-03): frame acknowledgements for NET-04, the shown tick,
## the newest input and up to three before it, unacknowledged one-shot actions, and cue reports
## for NET-06's 'Now!' judge.

## Newest frame tick received (u16 of it) and a bitmask of the 32 before it.
var ack_frame: int = 0
var ack_bits: int = 0
## How long the newest frame waited before this packet left, in 2 ms units.
var recv_delay: int = 0
## The tick the client was showing: its interpolated view time (NET-05), u32 plus a fraction.
var shown_tick: int = 0
var shown_fraction: int = 0
## The newest input's sequence number; inputs[0] is newest, inputs[i] is newest_seq - i.
var newest_seq: int = 0
var inputs: Array[InputRecord] = []
var actions: Array[ActionRecord] = []
## [cue_id, shown_tick, fraction] for each timed cue presented and not yet acknowledged.
var cue_reports: Array[PackedInt64Array] = []


func encode() -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u16(ack_frame & 0xFFFF)
	b.put_u32(ack_bits & 0xFFFFFFFF)
	b.put_u8(clampi(recv_delay, 0, 255))
	b.put_u32(shown_tick & 0xFFFFFFFF)
	b.put_u8(clampi(shown_fraction, 0, 255))
	b.put_u16(newest_seq & 0xFFFF)
	b.put_u8(inputs.size())
	for i: int in inputs.size():
		if i == 0:
			inputs[0].pack(b)
		else:
			inputs[i].pack_delta(b, inputs[i - 1])
	b.put_u8(actions.size())
	for a: ActionRecord in actions:
		a.pack(b)
	b.put_u8(cue_reports.size())
	for c: PackedInt64Array in cue_reports:
		b.put_u32(c[0] & 0xFFFFFFFF)
		b.put_u32(c[1] & 0xFFFFFFFF)
		b.put_u8(clampi(c[2], 0, 255))
	return Protocol.frame(Protocol.Msg.INPUT, b.data_array)


## Parses a payload (after Protocol.unframe). Returns null if it is malformed.
static func decode(payload: PackedByteArray) -> InputPacket:
	if payload.size() < 17:
		return null
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = payload
	var p: InputPacket = InputPacket.new()
	p.ack_frame = b.get_u16()
	p.ack_bits = b.get_u32()
	p.recv_delay = b.get_u8()
	p.shown_tick = b.get_u32()
	p.shown_fraction = b.get_u8()
	p.newest_seq = b.get_u16()
	var n: int = b.get_u8()
	if n > 8 or (n > 0 and b.get_available_bytes() < InputRecord.SIZE + 1):
		return null
	for i: int in n:
		var r: InputRecord
		if i == 0:
			r = InputRecord.unpack(b)
		else:
			if b.get_available_bytes() < 2:
				return null
			var mask: int = b.get_u8()
			var size: int = InputRecord.delta_size(mask)
			if size < 0 or b.get_available_bytes() < size + 1:
				return null
			r = InputRecord.unpack_delta(b, mask, p.inputs[i - 1])
		r.seq = (p.newest_seq - i) & 0xFFFF
		p.inputs.append(r)
	var a_count: int = b.get_u8()
	if b.get_available_bytes() < a_count * ActionRecord.SIZE + 1:
		return null
	for _i: int in a_count:
		p.actions.append(ActionRecord.unpack(b))
	var c_count: int = b.get_u8()
	if b.get_available_bytes() < c_count * 9:
		return null
	for _i: int in c_count:
		p.cue_reports.append(PackedInt64Array([b.get_u32(), b.get_u32(), b.get_u8()]))
	return p


## Wrap-aware comparison of u16 sequence numbers: a - b in [-32768, 32767].
static func seq_diff(a: int, b: int) -> int:
	var d: int = (a - b) & 0xFFFF
	return d - 0x10000 if d >= 0x8000 else d
