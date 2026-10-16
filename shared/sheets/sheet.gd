class_name Sheet
extends RefCounted
## LFT-14: one survey sheet's contents, the server's and each client's copy alike (Gameplay §12.7;
## LFT-15's map pages and LFT-03's Manual pencil use it too). Strokes (SheetStroke) and typed labels,
## each with an id; a label counts as one stroke toward mine.sheet_max_strokes. Rubbing out
## (Proposed: partial) removes what lies under the rubber and may split a stroke into pieces that
## each count; if the split would pass the cap the whole stroke goes instead, and a touched label
## goes whole. Only what someone drew is ever here: nothing of the mine reaches a sheet.

## The spatial index's bucket size: four printed squares.
const BUCKET_UNITS: int = 1024

## id -> SheetStroke.
var strokes: Dictionary = {}
## id -> SheetLabel.
var labels: Dictionary = {}
## Bumped on every change (renderers redraw what changed).
var revision: int = 0
## Buckets changed since a renderer last took them: Vector2i -> true.
var dirty: Dictionary = {}
var _buckets: Dictionary = {}
var _rects: Dictionary = {}


func count() -> int:
	return strokes.size() + labels.size()


func has(id: int) -> bool:
	return strokes.has(id) or labels.has(id)


func add_stroke(s: SheetStroke) -> void:
	remove(s.id)
	strokes[s.id] = s
	_index(s.id, s.bounds().grow(1.0))


func add_label(l: SheetLabel) -> void:
	remove(l.id)
	labels[l.id] = l
	_index(l.id, l.rect())


## Removes a stroke or label; false if there was none.
func remove(id: int) -> bool:
	if not _rects.has(id):
		return false
	var r: Rect2 = _rects[id]
	for b: Vector2i in _buckets_of(r):
		var ids: Dictionary = _buckets.get(b, {})
		ids.erase(id)
		if ids.is_empty():
			_buckets.erase(b)
		dirty[b] = true
	_rects.erase(id)
	strokes.erase(id)
	labels.erase(id)
	revision += 1
	return true


func clear() -> void:
	for b: Variant in _buckets.keys():
		dirty[b] = true
	strokes.clear()
	labels.clear()
	_buckets.clear()
	_rects.clear()
	revision += 1


## Ids whose boxes meet `rect`, ascending.
func ids_near(rect: Rect2) -> Array[int]:
	var seen: Dictionary = {}
	for b: Vector2i in _buckets_of(rect):
		for raw: Variant in Variants.dict(_buckets.get(b, {})).keys():
			var id: int = raw
			var r: Rect2 = _rects[id]
			if r.intersects(rect, true):
				seen[id] = true
	var out: Array[int] = []
	for raw: Variant in seen.keys():
		out.append(int(Variants.number(raw)))
	out.sort()
	return out


## The ids indexed in bucket `b` (renderers draw a bucket at a time).
func ids_in_bucket(b: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in Variants.dict(_buckets.get(b, {})).keys():
		out.append(int(Variants.number(raw)))
	out.sort()
	return out


func buckets() -> Array:
	return _buckets.keys()


## Takes the dirty buckets (a renderer's call).
func take_dirty() -> Array:
	var out: Array = dirty.keys()
	dirty.clear()
	return out


## What the rubber does along `centres` (circles of `radius`). `may_touch(author) -> bool` says
## whose strokes it may touch (in public, only the rubber's own). New pieces take ids from
## `next_id() -> int`. Returns {removed: Array[int], added: Array[SheetStroke]}, already applied.
func rub(centres: PackedVector2Array, radius: float, may_touch: Callable, cap: int, next_id: Callable) -> Dictionary:
	var removed: Array[int] = []
	var added: Array[SheetStroke] = []
	if centres.is_empty():
		return {"removed": removed, "added": added}
	var area: Rect2 = SheetStroke.bounds_of(centres).grow(radius)
	for id: int in ids_near(area):
		if labels.has(id):
			var l: SheetLabel = labels[id]
			if not Variants.flag(may_touch.call(l.author)):
				continue
			var r: Rect2 = l.rect()
			for c: Vector2 in centres:
				if SheetOps.circle_touches(r, c, radius):
					remove(id)
					removed.append(id)
					break
			continue
		var s: SheetStroke = strokes[id]
		if not Variants.flag(may_touch.call(s.author)):
			continue
		var near: PackedVector2Array = PackedVector2Array()
		var reach: Rect2 = s.bounds().grow(radius)
		for c: Vector2 in centres:
			if reach.has_point(c):
				near.append(c)
		if near.is_empty():
			continue
		var cut: Array = SheetOps.rub_pieces(s.points, near, radius)
		if not Variants.flag(cut[1]):
			continue
		var pieces: Array[PackedVector2Array] = cut[0]
		remove(id)
		removed.append(id)
		# The pieces each count; past the cap the whole stroke goes instead.
		if count() + pieces.size() > cap:
			continue
		for piece: PackedVector2Array in pieces:
			var p: SheetStroke = SheetStroke.make(int(Variants.number(next_id.call())), s.author, piece)
			add_stroke(p)
			added.append(p)
	return {"removed": removed, "added": added}


## The drawn extent: every stroke's and label's box (empty when nothing is drawn).
func extent() -> Rect2:
	var out: Rect2 = Rect2()
	var first: bool = true
	for raw: Variant in _rects.keys():
		var r: Rect2 = _rects[raw]
		out = r if first else out.merge(r)
		first = false
	return out


## A hash of the contents (ids, points, anchors and texts, in id order): every client holding
## the same strokes and labels holds the same digest (the map card's check).
func digest() -> int:
	var ids: Array = _rects.keys()
	ids.sort()
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for raw: Variant in ids:
		var id: int = raw
		var head: PackedByteArray = PackedByteArray()
		head.resize(8)
		head.encode_s64(0, id)
		ctx.update(head)
		if strokes.has(id):
			var s: SheetStroke = strokes[id]
			ctx.update(SheetStroke.encode(s.points))
		else:
			var l: SheetLabel = labels[id]
			ctx.update(SheetStroke.encode(PackedVector2Array([l.anchor])))
			ctx.update(l.text.to_utf8_buffer())
	return ctx.finish().decode_s64(0)


func _index(id: int, r: Rect2) -> void:
	_rects[id] = r
	for b: Vector2i in _buckets_of(r):
		var ids: Dictionary = _buckets.get(b, {})
		ids[id] = true
		_buckets[b] = ids
		dirty[b] = true
	revision += 1


static func bucket_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / BUCKET_UNITS), floori(p.y / BUCKET_UNITS))


static func _buckets_of(r: Rect2) -> Array[Vector2i]:
	var lo: Vector2i = bucket_of(r.position)
	var hi: Vector2i = bucket_of(r.end)
	var out: Array[Vector2i] = []
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			out.append(Vector2i(x, y))
	return out
