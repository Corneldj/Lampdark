class_name DeafenedMessages
extends RefCounted
## SND-04: the Deafened record (Protocol.Msg DEAFENED, control lane, to the deafened miner's client
## only): how long the ringing lasts and how far the client dips its own ambient beds. The events it
## plays meanwhile arrive already dipped by the server; a second record restarts the ringing.


static func encode(duration_s: float, dip_db: float) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u16(clampi(roundi(duration_s * 100.0), 0, 65535))
	b.put_u8(clampi(roundi(dip_db), 0, 255))
	return b.data_array


## {duration_s, dip_db}, or {} if malformed.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() != 3:
		return {}
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	return {"duration_s": b.get_u16() / 100.0, "dip_db": float(b.get_u8())}
