class_name RingMessages
extends RefCounted
## MNR-05: the interact ring as its actor's client receives it (Protocol.Msg RING, control lane, to
## the actor only): open or closed, the option ids the target's visible state and the actor's kit
## allow, the chosen one, and for a body its belt (kind and count per slot; never a no-slot thing).
## No entity id, position or hidden state (a mark) ever rides here.


static func encode(open: bool, options: Array[String], chosen: int, belt: Array) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(1 if open else 0)
	b.put_u8(clampi(chosen + 1, 0, 255))
	b.put_u8(options.size())
	for o: String in options:
		var raw: PackedByteArray = o.to_utf8_buffer()
		b.put_u8(raw.size())
		b.put_data(raw)
	b.put_u8(belt.size())
	for raw_slot: Variant in belt:
		var row: Array = Variants.array(raw_slot)
		b.put_u8(int(Variants.number(row[0])))
		b.put_u8(int(Variants.number(row[1])))
	return b.data_array


## {open, chosen (-1 none), options: Array[String], belt: Array of [kind, count]}, or {} if malformed.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 4:
		return {}
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	var open: bool = b.get_u8() == 1
	var chosen: int = b.get_u8() - 1
	var options: Array[String] = []
	for _i: int in b.get_u8():
		var got: Array = b.get_data(b.get_u8())
		var raw: PackedByteArray = got[1]
		options.append(raw.get_string_from_utf8())
	var belt: Array = []
	for _j: int in b.get_u8():
		belt.append([b.get_u8(), b.get_u8()])
	return {"open": open, "chosen": chosen, "options": options, "belt": belt}
