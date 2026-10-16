class_name SheetCodec
extends RefCounted
## LFT-14: the sheets' wire form, Protocol.Msg.SHEET. A message is a run of ops, each a kind byte
## and its fields (little-endian; points as SheetStroke blobs; text as a length byte and UTF-8).
## Commits, rubs and the sync go reliably on the bulk lane; strokes as they are made go
## unreliably (the client's on the inputs lane, the server's relay on the frames lane, only to the
## miners at the table). Nothing here names an author, but a public lobby's label carries its
## author's SteamID for STM-08's text filter, never shown.

enum Op {
	COMMIT_STROKE = 1,  ## client: seq u16, blob
	COMMIT_LABEL = 2,  ## client: seq u16, x s16, y s16, text
	RUB = 3,  ## client: the rubber's centres, a blob
	SKETCH = 4,  ## client, inputs lane: its stroke's number u16, the newest points (a blob)
	RESYNC = 5,  ## client: its copy failed the freeze's digest; send the sheet again
	RESET = 10,  ## server: forget every stroke and label
	ADD_STROKE = 11,  ## server: id u32, blob
	ADD_LABEL = 12,  ## server: id u32, x s16, y s16, text, author (empty outside public lobbies)
	REMOVE = 13,  ## server: id u32
	ACCEPT = 14,  ## server, to the drawer: seq u16, id u32 (your stroke or label is on the sheet)
	DROPPED = 15,  ## server, to the drawer: seq u16 (it marked nothing)
	FULL = 16,  ## server: u8, the sheet is at its cap and the pencil marks nothing
	PEN = 17,  ## server, frames lane: pen u16, blob (a stroke as it is made, unsigned)
	PEN_UP = 18,  ## server: pen u16 (that stroke is done or abandoned)
	FREEZE = 19,  ## server: digest s64, count u32, run uuid (the sheet as the cage left it)
}


static func commit_stroke(seq: int, points: PackedVector2Array) -> PackedByteArray:
	var blob: PackedByteArray = SheetStroke.encode(points)
	if blob.is_empty():
		return PackedByteArray()
	var out: PackedByteArray = _head(Op.COMMIT_STROKE, 2)
	out.encode_u16(1, seq & 0xFFFF)
	out.append_array(blob)
	return out


static func commit_label(seq: int, anchor: Vector2, text: String) -> PackedByteArray:
	var out: PackedByteArray = _head(Op.COMMIT_LABEL, 6)
	out.encode_u16(1, seq & 0xFFFF)
	out.encode_s16(3, clampi(int(anchor.x), SheetStroke.MIN, SheetStroke.MAX))
	out.encode_s16(5, clampi(int(anchor.y), SheetStroke.MIN, SheetStroke.MAX))
	return _text(out, text)


static func rub(centres: PackedVector2Array) -> PackedByteArray:
	var blob: PackedByteArray = SheetStroke.encode(centres)
	if blob.is_empty():
		return PackedByteArray()
	var out: PackedByteArray = _head(Op.RUB, 0)
	out.append_array(blob)
	return out


static func sketch(stroke_seq: int, points: PackedVector2Array) -> PackedByteArray:
	var blob: PackedByteArray = SheetStroke.encode(points)
	if blob.is_empty():
		return PackedByteArray()
	var out: PackedByteArray = _head(Op.SKETCH, 2)
	out.encode_u16(1, stroke_seq & 0xFFFF)
	out.append_array(blob)
	return out


static func resync() -> PackedByteArray:
	return _head(Op.RESYNC, 0)


static func reset() -> PackedByteArray:
	return _head(Op.RESET, 0)


static func add_stroke(id: int, points: PackedVector2Array) -> PackedByteArray:
	return add_stroke_blob(id, SheetStroke.encode(points))


## ADD_STROKE with the stroke's blob as already written (SheetStroke.encoded()).
static func add_stroke_blob(id: int, blob: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = _head(Op.ADD_STROKE, 4)
	out.encode_u32(1, id)
	out.append_array(blob)
	return out


static func add_label(id: int, anchor: Vector2, text: String, author: String) -> PackedByteArray:
	var out: PackedByteArray = _head(Op.ADD_LABEL, 8)
	out.encode_u32(1, id)
	out.encode_s16(5, int(anchor.x))
	out.encode_s16(7, int(anchor.y))
	return _text(_text(out, text), author)


static func remove(id: int) -> PackedByteArray:
	var out: PackedByteArray = _head(Op.REMOVE, 4)
	out.encode_u32(1, id)
	return out


static func accept(seq: int, id: int) -> PackedByteArray:
	var out: PackedByteArray = _head(Op.ACCEPT, 6)
	out.encode_u16(1, seq & 0xFFFF)
	out.encode_u32(3, id)
	return out


static func dropped(seq: int) -> PackedByteArray:
	var out: PackedByteArray = _head(Op.DROPPED, 2)
	out.encode_u16(1, seq & 0xFFFF)
	return out


static func full(on: bool) -> PackedByteArray:
	var out: PackedByteArray = _head(Op.FULL, 1)
	out[1] = 1 if on else 0
	return out


static func pen(pen_id: int, points: PackedVector2Array) -> PackedByteArray:
	var blob: PackedByteArray = SheetStroke.encode(points)
	if blob.is_empty():
		return PackedByteArray()
	var out: PackedByteArray = _head(Op.PEN, 2)
	out.encode_u16(1, pen_id & 0xFFFF)
	out.append_array(blob)
	return out


static func pen_up(pen_id: int) -> PackedByteArray:
	var out: PackedByteArray = _head(Op.PEN_UP, 2)
	out.encode_u16(1, pen_id & 0xFFFF)
	return out


static func freeze(digest: int, count: int, run_uuid: String) -> PackedByteArray:
	var out: PackedByteArray = _head(Op.FREEZE, 12)
	out.encode_s64(1, digest)
	out.encode_u32(9, count)
	return _text(out, run_uuid)


## Every op in a message, in order: dictionaries with "op" and its fields ("seq", "id", "points",
## "anchor", "text", "author", "pen", "on", "digest", "count", "run_uuid"). [] when any part is
## malformed: a message is taken whole or not at all.
static func decode(payload: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at: int = 0
	while at < payload.size():
		var op: int = payload[at]
		var d: Dictionary = {"op": op}
		var next: int = _fields(payload, at + 1, op, d)
		if next < 0:
			return [] as Array[Dictionary]
		out.append(d)
		at = next
	return out


## Reads one op's fields after its kind byte; the offset after them, or -1.
static func _fields(b: PackedByteArray, at: int, op: int, d: Dictionary) -> int:
	match op:
		Op.COMMIT_STROKE, Op.SKETCH, Op.PEN:
			if at + 2 > b.size():
				return -1
			d["pen" if op == Op.PEN else "seq"] = b.decode_u16(at)
			return _blob(b, at + 2, d)
		Op.COMMIT_LABEL:
			if at + 6 > b.size():
				return -1
			d["seq"] = b.decode_u16(at)
			d["anchor"] = Vector2(b.decode_s16(at + 2), b.decode_s16(at + 4))
			return _read_text(b, at + 6, d, "text")
		Op.RUB:
			return _blob(b, at, d)
		Op.RESYNC, Op.RESET:
			return at
		Op.ADD_STROKE:
			if at + 4 > b.size():
				return -1
			d["id"] = b.decode_u32(at)
			return _blob(b, at + 4, d)
		Op.ADD_LABEL:
			if at + 8 > b.size():
				return -1
			d["id"] = b.decode_u32(at)
			d["anchor"] = Vector2(b.decode_s16(at + 4), b.decode_s16(at + 6))
			var after: int = _read_text(b, at + 8, d, "text")
			return _read_text(b, after, d, "author") if after >= 0 else -1
		Op.REMOVE:
			if at + 4 > b.size():
				return -1
			d["id"] = b.decode_u32(at)
			return at + 4
		Op.ACCEPT:
			if at + 6 > b.size():
				return -1
			d["seq"] = b.decode_u16(at)
			d["id"] = b.decode_u32(at + 2)
			return at + 6
		Op.DROPPED, Op.PEN_UP:
			if at + 2 > b.size():
				return -1
			d["pen" if op == Op.PEN_UP else "seq"] = b.decode_u16(at)
			return at + 2
		Op.FULL:
			if at + 1 > b.size() or b[at] > 1:
				return -1
			d["on"] = b[at] == 1
			return at + 1
		Op.FREEZE:
			if at + 12 > b.size():
				return -1
			d["digest"] = b.decode_s64(at)
			d["count"] = b.decode_u32(at + 8)
			return _read_text(b, at + 12, d, "run_uuid")
	return -1


static func _blob(b: PackedByteArray, at: int, d: Dictionary) -> int:
	var r: Array = SheetStroke.decode(b, at)
	if r.is_empty():
		return -1
	var next: int = int(Variants.number(r[1]))
	d["points"] = r[0]
	d["blob"] = b.slice(at, next)
	return next


static func _read_text(b: PackedByteArray, at: int, d: Dictionary, field: String) -> int:
	if at + 1 > b.size():
		return -1
	var n: int = b[at]
	if at + 1 + n > b.size():
		return -1
	d[field] = b.slice(at + 1, at + 1 + n).get_string_from_utf8()
	return at + 1 + n


static func _head(op: Op, fields: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(1 + fields)
	out[0] = op
	return out


## Appends a length byte and the text's UTF-8 (at most 255 bytes; LFT-14's labels stay far under).
static func _text(out: PackedByteArray, text: String) -> PackedByteArray:
	var bytes: PackedByteArray = text.to_utf8_buffer()
	if bytes.size() > 255:
		bytes = bytes.slice(0, 255)
	out.append(bytes.size())
	out.append_array(bytes)
	return out
