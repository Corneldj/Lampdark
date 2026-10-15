class_name SaveWire
extends RefCounted
## NET-09: the save messages between a server and its members. SAVE_DATA carries a snapshot's plain
## header, its section order and the sealed sections that changed since the last; JOURNAL one
## sealed journal entry; SAVE_ACK a sequence number. Members store what they are sent and open
## nothing (sealed sections are opaque to every client).


static func save_data(uuid: String, seq: int, header: Dictionary, order: PackedStringArray, changed: Dictionary) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_utf8_string(uuid)
	b.put_u32(seq)
	var h: PackedByteArray = var_to_bytes(header)
	b.put_u32(h.size())
	b.put_data(h)
	b.put_u16(order.size())
	for n: String in order:
		b.put_utf8_string(n)
	var names: Array = changed.keys()
	names.sort()
	b.put_u16(names.size())
	for raw: Variant in names:
		var blob: PackedByteArray = changed[raw]
		b.put_utf8_string(str(raw))
		b.put_u32(blob.size())
		b.put_data(blob)
	return b.data_array


## {uuid, seq, header, order, changed}, or {} if malformed.
static func read_save_data(payload: PackedByteArray) -> Dictionary:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = payload
	var uuid: String = b.get_utf8_string()
	var seq: int = b.get_u32()
	var hsize: int = b.get_u32()
	if b.get_position() + hsize > payload.size():
		return {}
	var header: Variant = bytes_to_var(payload.slice(b.get_position(), b.get_position() + hsize))
	b.seek(b.get_position() + hsize)
	var order: PackedStringArray = PackedStringArray()
	for _i: int in b.get_u16():
		order.append(b.get_utf8_string())
	var changed: Dictionary = {}
	for _i: int in b.get_u16():
		var n: String = b.get_utf8_string()
		var size: int = b.get_u32()
		if b.get_position() + size > payload.size():
			return {}
		changed[n] = payload.slice(b.get_position(), b.get_position() + size)
		b.seek(b.get_position() + size)
	if not header is Dictionary or b.get_position() != payload.size():
		return {}
	return {"uuid": uuid, "seq": seq, "header": header, "order": order, "changed": changed}


static func journal(uuid: String, sealed_entry: PackedByteArray) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_utf8_string(uuid)
	b.put_data(sealed_entry)
	return b.data_array


## {uuid, entry (sealed bytes)}, or {}.
static func read_journal(payload: PackedByteArray) -> Dictionary:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = payload
	var uuid: String = b.get_utf8_string()
	if uuid.is_empty() or b.get_position() >= payload.size():
		return {}
	return {"uuid": uuid, "entry": payload.slice(b.get_position())}


static func ack(seq: int) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u32(seq)
	return b.data_array


static func read_ack(payload: PackedByteArray) -> int:
	if payload.size() != 4:
		return -1
	return payload.decode_u32(0)
