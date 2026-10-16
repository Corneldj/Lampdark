class_name SheetStroke
extends RefCounted
## LFT-14: one pencil stroke on a sheet (the map table; LFT-15's map pages and LFT-03's Manual use
## the same model). A polyline in sheet units: integers from MIN to MAX on each axis, the shaft at
## (0, 0), 256 units to a printed square, north up; nothing ties a unit to a world tile. On the wire
## and in the diff log a stroke is its point count, an int16 start and int8 deltas, so no step is
## longer than STEP_MAX on either axis. Its author is the server's alone: a client never learns who
## drew a stroke (Gameplay §14.3: unsigned).

const MIN: int = -16384
const MAX: int = 16383
## The longest step a delta can carry, on either axis; also the longest step the pencil sends.
const STEP_MAX: int = 127
## The most points a blob can carry (its count is one byte).
const POINTS_MAX: int = 255

var id: int = 0
## Server only: the author's index in the sheet's author table; -1 on a client.
var author: int = -1
var points: PackedVector2Array = PackedVector2Array()
## Its blob, written once (the server journals and sends the same bytes to every client).
var _blob: PackedByteArray = PackedByteArray()
var _bounds: Rect2 = Rect2()
var _bounded: bool = false


static func make(stroke_id: int, by: int, at: PackedVector2Array, blob: PackedByteArray = PackedByteArray()) -> SheetStroke:
	var s: SheetStroke = SheetStroke.new()
	s.id = stroke_id
	s.author = by
	s.points = at
	s._blob = blob
	return s


## The stroke's blob (encode() of its points), kept once written.
func encoded() -> PackedByteArray:
	if _blob.is_empty():
		_blob = encode(points)
	return _blob


## The points' bounding box (a dot's is empty, at the dot).
func bounds() -> Rect2:
	if not _bounded:
		_bounds = bounds_of(points)
		_bounded = true
	return _bounds


static func bounds_of(at: PackedVector2Array) -> Rect2:
	if at.is_empty():
		return Rect2()
	var lo: Vector2 = at[0]
	var hi: Vector2 = at[0]
	for p: Vector2 in at:
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)


## True when every point is a whole number inside the sheet.
static func in_range(at: PackedVector2Array) -> bool:
	for p: Vector2 in at:
		if p.x != roundf(p.x) or p.y != roundf(p.y) or p.x < MIN or p.x > MAX or p.y < MIN or p.y > MAX:
			return false
	return true


## True when every step is at least `min_step` and at most STEP_MAX units long (the pencil's
## spacing; GDD §15.11's stroke-length cap is the point count).
static func spaced(at: PackedVector2Array, min_step: float) -> bool:
	for i: int in range(1, at.size()):
		var d: float = at[i].distance_to(at[i - 1])
		if d < min_step or d > STEP_MAX:
			return false
	return true


## The blob: a count byte, an int16 start, then an int8 pair a step. Empty if it cannot be written
## (no points, too many, out of range, or a step past STEP_MAX on an axis).
static func encode(at: PackedVector2Array) -> PackedByteArray:
	var n: int = at.size()
	if n == 0 or n > POINTS_MAX or not in_range(at):
		return PackedByteArray()
	var out: PackedByteArray = PackedByteArray()
	out.resize(1 + 4 + 2 * (n - 1))
	out[0] = n
	out.encode_s16(1, int(at[0].x))
	out.encode_s16(3, int(at[0].y))
	for i: int in range(1, n):
		var dx: int = int(at[i].x - at[i - 1].x)
		var dy: int = int(at[i].y - at[i - 1].y)
		if absi(dx) > STEP_MAX or absi(dy) > STEP_MAX:
			return PackedByteArray()
		out.encode_s8(5 + 2 * (i - 1), dx)
		out.encode_s8(6 + 2 * (i - 1), dy)
	return out


## The blob's size in bytes for `n` points.
static func blob_size(n: int) -> int:
	return 1 + 4 + 2 * maxi(0, n - 1)


## Reads a blob at `at` in `bytes`: [points, the offset after it], or [] when it is short, empty or
## leaves the sheet.
static func decode(bytes: PackedByteArray, at: int = 0) -> Array:
	if at < 0 or at + 5 > bytes.size():
		return []
	var n: int = bytes[at]
	if n == 0 or at + blob_size(n) > bytes.size():
		return []
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(n)
	var x: int = bytes.decode_s16(at + 1)
	var y: int = bytes.decode_s16(at + 3)
	out[0] = Vector2(x, y)
	for i: int in range(1, n):
		x += bytes.decode_s8(at + 5 + 2 * (i - 1))
		y += bytes.decode_s8(at + 6 + 2 * (i - 1))
		out[i] = Vector2(x, y)
	if not in_range(out):
		return []
	return [out, at + blob_size(n)]
