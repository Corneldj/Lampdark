class_name FeelMessages
extends RefCounted
## VIS-07: what the server tells a miner's own client about feeling and wall bumps (Protocol.Msg
## FEEL, control lane, to that client only). A feel answer is exactly {caption_key, bearing_q,
## verb_key}; a bump is {caption_key}. Never a position, an entity id, a token or a distance: the
## thing felt is never streamed. bearing_q is 0-15 in vision.feel_bearing_step_deg steps clockwise
## from east (+x), or NO_BEARING with nothing in reach.

enum Kind { FEEL = 1, BUMP = 2 }

const NO_BEARING: int = 255


static func feel(caption_key: String, bearing_q: int, verb_key: String) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(Kind.FEEL)
	_put_text(b, caption_key)
	b.put_u8(bearing_q)
	_put_text(b, verb_key)
	return b.data_array


static func bump(caption_key: String) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(Kind.BUMP)
	_put_text(b, caption_key)
	return b.data_array


## {kind, caption_key[, bearing_q, verb_key]}, or {} if malformed.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 2:
		return {}
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	var kind: int = b.get_u8()
	var caption: String = _get_text(b)
	if kind == Kind.BUMP:
		return {"kind": kind, "caption_key": caption}
	if kind != Kind.FEEL or b.get_available_bytes() < 2:
		return {}
	var bearing: int = b.get_u8()
	return {"kind": kind, "caption_key": caption, "bearing_q": bearing, "verb_key": _get_text(b)}


static func _put_text(b: StreamPeerBuffer, text: String) -> void:
	var raw: PackedByteArray = text.to_utf8_buffer()
	b.put_u8(mini(raw.size(), 255))
	b.put_data(raw.slice(0, 255))


static func _get_text(b: StreamPeerBuffer) -> String:
	var n: int = b.get_u8()
	var got: Array = b.get_data(n)
	var raw: PackedByteArray = got[1]
	return raw.get_string_from_utf8()
