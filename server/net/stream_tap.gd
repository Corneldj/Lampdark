class_name StreamTap
extends RefCounted
## NET-04's stream tap: every frame exactly as sent, per client, for NET-07's run record and
## NET-08's audit. Records are decoded (LbFrameCodec) only while someone listens.

## records: LbFrameCodec.decode_records(bytes): the records the frame carries.
signal published(slot: int, tick: int, bytes: PackedByteArray, records: Dictionary)


func publish(slot: int, tick: int, bytes: PackedByteArray) -> void:
	if published.get_connections().is_empty():
		return
	published.emit(slot, tick, bytes, LbFrameCodec.decode_records(bytes))
