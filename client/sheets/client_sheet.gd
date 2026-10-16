class_name ClientSheet
extends RefCounted
## LFT-14: this client's copy of the map table's sheet (GDD §15.3: synced to every conscious
## client, shown only in the table's close-up). It holds the strokes and labels the server sent
## (never their authors), its own commits until the server answers, the others' strokes as they
## are made (by pen number: unsigned), whether the sheet is full, and, once it freezes for the map
## card, whether this copy matches the server's (a mismatch asks for the whole sheet again).
## Commits go reliably on the bulk lane, held back so no more than mine.sheet_strokes_per_s leave
## in any second and a little; the stroke being drawn goes unreliably at mine.sheet_sketch_hz.

## A little slack on the server's one-second window, so jitter never bunches commits into it.
const WINDOW_USEC: int = 1100000

## Which sheet this copy is (SheetKind): the Manual's pencil (LFT-03) leads its messages with SELECT.
var kind: int = SheetKind.Kind.MAP_TABLE
## (lane, payload) -> Error: sends one SHEET message (ClientConnection wires it).
var send: Callable = Callable()
## STM-08's FilterText: (text, author SteamID) -> String. Every label that carries an author (a
## public lobby's) goes through it before it is drawn, the map card included. Unset: as written.
var filter: Callable = Callable()
var sheet: Sheet = Sheet.new()
## seq -> {"points"} or {"anchor", "text"}: own commits the server has not answered.
var pending: Dictionary = {}
## pen -> {"points": PackedVector2Array, "at_usec": int}: the others' strokes as they are made.
var pens: Dictionary = {}
var full: bool = false
## {} until the sheet freezes; then {digest, count, run_uuid, matched}.
var frozen: Dictionary = {}
## Bumped whenever anything drawn changes (pending, pens and the flags included).
var revision: int = 0
var messages: int = 0
var malformed: int = 0
var _next_seq: int = 1
## Commits waiting for the window: [seq, payload].
var _outbox: Array[Array] = []
var _sent_usec: Array[int] = []
## The stroke being drawn: its number, its points, how many were sent, when the next packet may go.
var _sketch_seq: int = 0
var _sketch_points: PackedVector2Array = PackedVector2Array()
var _sketch_sent: int = 0
var _sketch_due: int = 0
## pen -> when it was lifted (a late packet for it is ignored).
var _lifted: Dictionary = {}
var _resync_asked: bool = false


func _init(of_kind: int = SheetKind.Kind.MAP_TABLE) -> void:
	kind = of_kind


## One SHEET message from the server, all of it for this sheet. False when malformed.
func on_message(payload: PackedByteArray, now_usec: int) -> bool:
	var ops: Array[Dictionary] = SheetCodec.decode(payload)
	if ops.is_empty():
		malformed += 1
		return false
	apply_ops(ops, now_usec)
	return true


## This sheet's ops from one message (ClientConnection splits a message by sheet).
func apply_ops(ops: Array[Dictionary], now_usec: int) -> void:
	messages += 1
	for d: Dictionary in ops:
		if int(Variants.number(d["op"])) != SheetCodec.Op.SELECT:
			_apply(d, now_usec)
	revision += 1


func _apply(d: Dictionary, now_usec: int) -> void:
	match int(Variants.number(d["op"])):
		SheetCodec.Op.RESET:
			sheet.clear()
			pending.clear()
			pens.clear()
			frozen = {}
		SheetCodec.Op.ADD_STROKE:
			var points: PackedVector2Array = d["points"]
			sheet.add_stroke(SheetStroke.make(int(Variants.number(d["id"])), -1, points))
		SheetCodec.Op.ADD_LABEL:
			var anchor: Vector2 = d["anchor"]
			var l: SheetLabel = SheetLabel.make(int(Variants.number(d["id"])), -1, anchor, str(d["text"]))
			l.author_identity = str(d["author"])
			sheet.add_label(l)
		SheetCodec.Op.REMOVE:
			sheet.remove(int(Variants.number(d["id"])))
		SheetCodec.Op.ACCEPT:
			var seq: int = int(Variants.number(d["seq"]))
			var mine: Dictionary = pending.get(seq, {})
			pending.erase(seq)
			if mine.has("points"):
				var points: PackedVector2Array = mine["points"]
				sheet.add_stroke(SheetStroke.make(int(Variants.number(d["id"])), -1, points))
			elif mine.has("text"):
				var anchor: Vector2 = mine["anchor"]
				sheet.add_label(SheetLabel.make(int(Variants.number(d["id"])), -1, anchor, str(mine["text"])))
		SheetCodec.Op.DROPPED:
			pending.erase(int(Variants.number(d["seq"])))
		SheetCodec.Op.FULL:
			full = Variants.flag(d["on"])
		SheetCodec.Op.PEN:
			var pen: int = int(Variants.number(d["pen"]))
			if _lifted.has(pen):
				return
			var p: Dictionary = pens.get(pen, {"points": PackedVector2Array()})
			var have: PackedVector2Array = p["points"]
			var more: PackedVector2Array = d["points"]
			# Each packet starts at the last point of the one before it.
			if not have.is_empty() and not more.is_empty() and have[have.size() - 1] == more[0]:
				more = more.slice(1)
			have.append_array(more)
			pens[pen] = {"points": have, "at_usec": now_usec}
		SheetCodec.Op.PEN_UP:
			var pen: int = int(Variants.number(d["pen"]))
			pens.erase(pen)
			_lifted[pen] = now_usec
		SheetCodec.Op.FREEZE:
			var digest: int = d["digest"]  # 64 bits: never through a float
			frozen = {"digest": digest, "count": int(Variants.number(d["count"])), "run_uuid": str(d["run_uuid"]),
				"matched": sheet.digest() == digest}
			if not Variants.flag(frozen["matched"]) and not _resync_asked:
				# Anything missing is sent again before the card is drawn.
				_resync_asked = true
				_send(Lane.Id.BULK, SheetCodec.resync())
			elif Variants.flag(frozen["matched"]):
				_resync_asked = false


## The pencil's finished stroke (at most mine.sheet_stroke_max_points, spaced by SheetOps): shown
## at once as this client's own, sent when the window allows. Its seq, or -1 if it marks nothing
## (the sheet is full, or the stroke cannot be written).
func commit_stroke(points: PackedVector2Array, now_usec: int) -> int:
	if full or points.is_empty():
		return -1
	var seq: int = _take_seq()
	var payload: PackedByteArray = SheetCodec.commit_stroke(seq, points)
	if payload.is_empty():
		return -1
	pending[seq] = {"points": points}
	_outbox.append([seq, payload])
	_lift_sketch()
	pump(now_usec)
	revision += 1
	return seq


## A typed label at `anchor` (the field already stops at the cap). Its seq, or -1.
func commit_label(anchor: Vector2, text: String, now_usec: int) -> int:
	var words: String = SheetOps.clip_label(text, Tuning.i(&"mine.sheet_label_max_chars"))
	if full or words.strip_edges().is_empty():
		return -1
	var seq: int = _take_seq()
	pending[seq] = {"anchor": SheetOps.on_sheet(anchor), "text": words}
	_outbox.append([seq, SheetCodec.commit_label(seq, SheetOps.on_sheet(anchor), words)])
	pump(now_usec)
	revision += 1
	return seq


## The rubber's path since the last call (centres at most SheetStroke.STEP_MAX apart): sent at
## once; the server does the rubbing and sends what it took.
func rub(centres: PackedVector2Array) -> bool:
	if centres.is_empty():
		return false
	var payload: PackedByteArray = SheetCodec.rub(centres)
	return not payload.is_empty() and _send(Lane.Id.BULK, payload) == OK


## The stroke being drawn, whole so far (`stroke` numbers it; a new number starts a new one).
## pump() sends what is new.
func sketching(stroke: int, points: PackedVector2Array) -> void:
	if stroke != _sketch_seq:
		_sketch_seq = stroke
		_sketch_sent = 0
		_sketch_due = 0
	_sketch_points = points


## Each client frame: commits the window allows, and the stroke being drawn at its rate.
func pump(now_usec: int) -> void:
	while not _outbox.is_empty():
		while not _sent_usec.is_empty() and now_usec - _sent_usec[0] >= WINDOW_USEC:
			_sent_usec.pop_front()
		if _sent_usec.size() >= Tuning.i(&"mine.sheet_strokes_per_s"):
			break
		var item: Array = _outbox.pop_front()
		_sent_usec.append(now_usec)
		var payload: PackedByteArray = item[1]
		_send(Lane.Id.BULK, payload)
	if _sketch_points.size() > _sketch_sent and now_usec >= _sketch_due:
		var from: int = maxi(0, _sketch_sent - 1)
		var chunk: PackedVector2Array = _sketch_points.slice(from)
		if chunk.size() > Tuning.i(&"mine.sheet_stroke_max_points"):
			chunk = chunk.slice(chunk.size() - Tuning.i(&"mine.sheet_stroke_max_points"))
		_send(Lane.Id.INPUTS, SheetCodec.sketch(_sketch_seq, chunk))
		_sketch_sent = _sketch_points.size()
		_sketch_due = now_usec + roundi(1000000.0 / maxf(1.0, Tuning.f(&"mine.sheet_sketch_hz")))
	for raw: Variant in pens.keys():
		var p: Dictionary = pens[raw]
		if now_usec - int(Variants.number(p["at_usec"])) > roundi(Tuning.f(&"mine.sheet_sketch_timeout_s") * 1000000.0):
			pens.erase(raw)
			revision += 1
	for raw: Variant in _lifted.keys():
		if now_usec - int(Variants.number(_lifted[raw])) > 10000000:
			_lifted.erase(raw)


## Commits still waiting for the window.
func outbox_size() -> int:
	return _outbox.size()


## A label as this client may draw it: through STM-08's filter whenever it carries its author.
func shown_text(l: SheetLabel) -> String:
	if l.author_identity.is_empty() or not filter.is_valid():
		return l.text
	return str(filter.call(l.text, l.author_identity))


## True once the sheet is frozen and this copy matches it: the map card may be drawn.
func card_ready() -> bool:
	return not frozen.is_empty() and Variants.flag(frozen["matched"])


func _lift_sketch() -> void:
	_sketch_points = PackedVector2Array()
	_sketch_sent = 0


func _take_seq() -> int:
	var seq: int = _next_seq
	_next_seq = (_next_seq % 0xFFFF) + 1
	return seq


func _send(lane: int, payload: PackedByteArray) -> Error:
	if not send.is_valid():
		return ERR_UNCONFIGURED
	var body: PackedByteArray = SheetCodec.select(kind) if kind != SheetKind.Kind.MAP_TABLE else PackedByteArray()
	body.append_array(payload)
	var r: Variant = send.call(lane, body)
	return int(Variants.number(r)) as Error
