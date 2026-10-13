class_name DebugMessages
extends RefCounted
## FND-08: the debug lane's payloads (Protocol.Msg DEBUG_*). Dev and QA builds only; a release build
## neither has this folder nor accepts the lane. Payloads are plain Variants (no objects).


static func encode(data: Dictionary) -> PackedByteArray:
	return var_to_bytes(data)


## {} when malformed.
static func decode(payload: PackedByteArray) -> Dictionary:
	if payload.is_empty():
		return {}
	var v: Variant = bytes_to_var(payload)
	return v if v is Dictionary else {}
