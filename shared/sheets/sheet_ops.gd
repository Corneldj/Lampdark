class_name SheetOps
extends RefCounted
## LFT-14: the sheet's geometry and text rules, the same on the server and every client. The
## rubber (Proposed: partial) takes out what lies under its circle and cuts a stroke where it
## crosses the edge, so one stroke may become several. The pencil's points are spaced
## mine.sheet_point_spacing_units to SheetStroke.STEP_MAX apart; a long drag is chained into
## strokes of at most mine.sheet_stroke_max_points that share their ends. A label is one line of
## at most mine.sheet_label_max_chars grapheme clusters. Nothing here ever snaps to anything.

## The longest step the client's pencil makes (rounding to whole units can add up to √2).
const STEP_SAFE: float = 125.0
## A label's UTF-8 bytes, a character at most (its worst-case save size stays inside 4 MB).
const LABEL_BYTES_PER_CHAR: int = 4


## The rubber's circles in turn over one polyline (Proposed: partial): [touched, pieces
## (Array[PackedVector2Array])]. What lies strictly inside a circle goes; a step crossing an edge is
## cut there, rounded to whole units, so a stroke may leave several pieces of two points or more; a
## dot inside goes whole; a point on the edge, or a tangent, is untouched. Native (LbSheet.rub, the
## server's hot path). Untouched, the one piece is the polyline itself.
static func rub_pieces(points: PackedVector2Array, centres: PackedVector2Array, radius: float) -> Array:
	var r: Array = LbSheet.rub(points, centres, radius)
	var pieces: Array[PackedVector2Array] = []
	for raw: Variant in Variants.array(r[1]):
		var piece: PackedVector2Array = raw
		pieces.append(piece)
	return [pieces, Variants.flag(r[0])]


## A label's box on the sheet: from its anchor (the left end of the line, at its middle), the
## height mine.sheet_label_height_units and mine.sheet_label_char_units a character. The server
## has no font, so this box is what the rubber touches.
static func label_rect(anchor: Vector2, text: String) -> Rect2:
	var h: float = Tuning.f(&"mine.sheet_label_height_units")
	var w: float = Tuning.f(&"mine.sheet_label_char_units") * maxi(1, grapheme_count(text))
	return Rect2(anchor.x, anchor.y - h * 0.5, w, h)


## True when the circle reaches into the box.
static func circle_touches(rect: Rect2, centre: Vector2, radius: float) -> bool:
	var nearest: Vector2 = centre.clamp(rect.position, rect.end)
	return nearest.distance_squared_to(centre) < radius * radius


## The user-perceived characters in `text` (grapheme clusters).
static func grapheme_count(text: String) -> int:
	if text.is_empty():
		return 0
	var breaks: PackedInt32Array = TextServerManager.get_primary_interface().string_get_character_breaks(text, "")
	return breaks.size() if not breaks.is_empty() else text.length()


## `text` cut to at most `max_chars` grapheme clusters and their byte cap: what the label field
## holds (it stops at the cap, Gameplay §A.11).
static func clip_label(text: String, max_chars: int) -> String:
	var one_line: String = text.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	var breaks: PackedInt32Array = TextServerManager.get_primary_interface().string_get_character_breaks(one_line, "")
	var out: String = one_line
	if breaks.size() > max_chars:
		out = one_line.substr(0, breaks[max_chars - 1]) if max_chars > 0 else ""
	while out.to_utf8_buffer().size() > max_chars * LABEL_BYTES_PER_CHAR and not out.is_empty():
		out = out.substr(0, out.length() - 1)
	return out


## The server's check of a label's text: one line, no control characters, 1 to `max_chars`
## grapheme clusters within the byte cap.
static func label_ok(text: String, max_chars: int) -> bool:
	if text.strip_edges().is_empty() or text.to_utf8_buffer().size() > max_chars * LABEL_BYTES_PER_CHAR:
		return false
	for i: int in text.length():
		var c: int = text.unicode_at(i)
		if c < 0x20 or (c >= 0x7F and c <= 0x9F) or c == 0x2028 or c == 0x2029:
			return false
	return grapheme_count(text) <= max_chars


## The pencil following the cursor from `last`: the new points, none until it is `spacing` away,
## and long jumps split into even steps of at most STEP_SAFE. Whole units, never snapped.
static func follow(last: Vector2, cursor: Vector2, spacing: float) -> PackedVector2Array:
	var target: Vector2 = _whole(cursor)
	var out: PackedVector2Array = PackedVector2Array()
	var dist: float = last.distance_to(target)
	if dist < spacing:
		return out
	var steps: int = ceili(dist / STEP_SAFE)
	for i: int in range(1, steps + 1):
		out.append(_whole(last.lerp(target, float(i) / steps)))
	return out


## The straight-line aid (GDD §14.5): points between the two chosen points only, evenly spaced at
## most STEP_SAFE apart; a dot when they are closer than `spacing`.
static func straight(a: Vector2, b: Vector2, spacing: float) -> PackedVector2Array:
	var from: Vector2 = _whole(a)
	var to: Vector2 = _whole(b)
	var dist: float = from.distance_to(to)
	if dist < spacing:
		return PackedVector2Array([from])
	var steps: int = ceili(dist / STEP_SAFE)
	var out: PackedVector2Array = PackedVector2Array([from])
	for i: int in range(1, steps + 1):
		out.append(_whole(from.lerp(to, float(i) / steps)))
	return out


## A long polyline as chained strokes of at most `max_points`, each starting where the last ended.
static func chain(points: PackedVector2Array, max_points: int) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if points.size() <= max_points:
		out.append(points)
		return out
	var at: int = 0
	while at < points.size() - 1:
		var end: int = mini(at + max_points, points.size())
		out.append(points.slice(at, end))
		at = end - 1
	return out


## Points clamped to the sheet and rounded to whole units.
static func on_sheet(p: Vector2) -> Vector2:
	return _whole(p).clamp(Vector2(SheetStroke.MIN, SheetStroke.MIN), Vector2(SheetStroke.MAX, SheetStroke.MAX))


static func _whole(p: Vector2) -> Vector2:
	return Vector2(roundf(p.x), roundf(p.y))
