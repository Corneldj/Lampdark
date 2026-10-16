class_name SheetPencil
extends RefCounted
## LFT-14: the map table's tools on this client (Gameplay §12.7, §4.8): the pencil (freehand, or
## GDD §14.5's straight-line aid), the rubber and the typed label. It turns the pointer's path, in
## sheet units, into ClientSheet's strokes, rubs and labels: the pencil's points spaced as SheetOps
## follows them and a long drag chained into strokes of at most mine.sheet_stroke_max_points, the
## stroke being drawn sent as it grows, the rubber's path sampled at half its radius. It never adds
## a point the pointer did not pass and never snaps; the straight-line aid draws only between the
## two points chosen. At the cap (the server's FULL) the pencil marks nothing.

enum Tool { NONE = 0, PENCIL = 1, RUBBER = 2 }

## The sheet this client holds and sends through (ClientConnection.sheet).
var sheet: ClientSheet = null
## GDD §14.5's aid: the pencil draws straight lines between press and release.
var straight_lines: bool = false
var tool: Tool = Tool.NONE
## The stroke being drawn, whole so far (freehand), and its number for the sketch.
var points: PackedVector2Array = PackedVector2Array()
## The straight line's chosen start and the pointer now (shown as a preview, never sent until
## release).
var line_from: Vector2 = Vector2.ZERO
var line_to: Vector2 = Vector2.ZERO
## The pointer, in sheet units (the cursor drawn).
var at: Vector2 = Vector2.ZERO
## Tools used this session (MOD-04's first-use glyphs and QA-04's telemetry read them).
var used: Dictionary = {}
var _stroke_no: int = 0
## The stroke being drawn began where a chained one ended (its lone first point is not a dot).
var _chained: bool = false
var _rub_path: PackedVector2Array = PackedVector2Array()
## The path's first point was sent already (the next batch starts there, so none leaves a gap).
var _rub_anchored: bool = false
var _rub_sent_usec: int = 0


func _init(client_sheet: ClientSheet = null) -> void:
	sheet = client_sheet


func press(which: Tool, pointer: Vector2, now_usec: int) -> void:
	at = SheetOps.on_sheet(pointer)
	if tool != Tool.NONE or sheet == null:
		return
	tool = which
	used[which] = true
	match which:
		Tool.PENCIL:
			if sheet.full:
				tool = Tool.NONE  # the pencil marks nothing until something is rubbed out
				return
			if straight_lines:
				line_from = at
				line_to = at
				return
			points = PackedVector2Array([at])
			_chained = false
			_stroke_no += 1
			sheet.sketching(_stroke_no, points)
		Tool.RUBBER:
			_rub_path = PackedVector2Array([at])
			_rub_anchored = false
			_rub(now_usec, true)


func drag(pointer: Vector2, now_usec: int) -> void:
	at = SheetOps.on_sheet(pointer)
	match tool:
		Tool.PENCIL:
			if straight_lines:
				line_to = at
				return
			var max_points: int = Tuning.i(&"mine.sheet_stroke_max_points")
			for p: Vector2 in SheetOps.follow(points[points.size() - 1], at, Tuning.f(&"mine.sheet_point_spacing_units")):
				points.append(p)
				if points.size() >= max_points:
					# A long drag goes on as a chained stroke from where this one ends.
					sheet.commit_stroke(points, now_usec)
					points = PackedVector2Array([p])
					_chained = true
					_stroke_no += 1
			sheet.sketching(_stroke_no, points)
		Tool.RUBBER:
			var step: float = Tuning.f(&"mine.sheet_rubber_radius_units") * 0.5
			var last: Vector2 = _rub_path[_rub_path.size() - 1]
			var dist: float = last.distance_to(at)
			if dist >= step:
				var n: int = ceili(dist / step)
				for i: int in range(1, n + 1):
					_rub_path.append(last.lerp(at, float(i) / n).round())
			_rub(now_usec, false)


func release(pointer: Vector2, now_usec: int) -> void:
	drag(pointer, now_usec)
	match tool:
		Tool.PENCIL:
			if straight_lines:
				var line: PackedVector2Array = SheetOps.straight(line_from, at, Tuning.f(&"mine.sheet_point_spacing_units"))
				for part: PackedVector2Array in SheetOps.chain(line, Tuning.i(&"mine.sheet_stroke_max_points")):
					sheet.commit_stroke(part, now_usec)
			elif points.size() >= 2 or (points.size() == 1 and not _chained):
				sheet.commit_stroke(points, now_usec)  # a press without a drag is a dot
			points = PackedVector2Array()
		Tool.RUBBER:
			_rub(now_usec, true)
			_rub_path = PackedVector2Array()
	tool = Tool.NONE


## The close-up shut mid-stroke: what was being drawn marks nothing.
func cancel() -> void:
	tool = Tool.NONE
	points = PackedVector2Array()
	_rub_path = PackedVector2Array()
	if sheet != null:
		sheet.sketching(_stroke_no + 1, PackedVector2Array())
		_stroke_no += 1


## A typed label with its left end at the pointer. Its seq, or -1 when it marks nothing.
func label(text: String, now_usec: int) -> int:
	used[&"label"] = true
	if sheet == null:
		return -1
	return sheet.commit_label(at, text, now_usec)


## The rubber's path goes at the sketch rate (or at once when `now` is set), each batch starting
## where the last ended.
func _rub(now_usec: int, now: bool) -> void:
	if _rub_path.size() - (1 if _rub_anchored else 0) <= 0:
		return
	var due: int = _rub_sent_usec + roundi(1000000.0 / maxf(1.0, Tuning.f(&"mine.sheet_sketch_hz")))
	var max_points: int = Tuning.i(&"mine.sheet_stroke_max_points")
	if not now and now_usec < due and _rub_path.size() < max_points:
		return
	var last: Vector2 = _rub_path[_rub_path.size() - 1]
	while not _rub_path.is_empty():
		var batch: PackedVector2Array = _rub_path.slice(0, max_points)
		sheet.rub(batch)
		_rub_path = _rub_path.slice(batch.size())
	_rub_path = PackedVector2Array([last])
	_rub_anchored = true
	_rub_sent_usec = now_usec
