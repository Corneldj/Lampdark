class_name ChalkStore
extends RefCounted
## MNR-10: every chalk mark of the run, kept by the floor tile it was made from: on the floor, or
## on the rib face bordering it (ChalkMarks.Surface); one mark a surface, a new one replacing it
## (Proposed). Each mark is a GEN-13 diff-log record ("x,y:<surface key>" -> {glyph}), replayed
## when its cell comes back, and reaches clients only through VIS-03's tile data at 0.30 (the
## vision's chalk). Only a roof fall erases chalk (`erase_chalk`, HAZ-03). The author is kept for
## logs only and never sent. Server-only.

## floor tile -> PackedByteArray (ChalkMarks.SURFACES glyph bytes, 0 for none).
var marks: Dictionary = {}
## "x,y:<surface key>" -> the miner who made it (logs only).
var authors: Dictionary = {}
## (tile: Vector2i, glyphs: PackedByteArray) -> void: VIS-03's tile data (VisionSystem.set_chalk).
var show: Callable = func(_tile: Vector2i, _glyphs: PackedByteArray) -> void: pass
var _run: RunState = null


func bind(run: RunState) -> void:
	_run = run
	if run.vision != null:
		show = run.vision.set_chalk
	if run.diff_log != null:
		run.diff_log.register(DiffLog.Kind.CHALK, _replay)


static func key_of(tile: Vector2i, surface: int) -> String:
	return "%d,%d:%s" % [tile.x, tile.y, ChalkMarks.SURFACE_KEYS[surface]]


func glyph_at(tile: Vector2i, surface: int) -> int:
	var g: PackedByteArray = marks.get(tile, PackedByteArray())
	return g[surface] if g.size() == ChalkMarks.SURFACES else 0


## Puts `glyph` on `surface` of `tile`, replacing whatever was there.
func put(run: RunState, tile: Vector2i, surface: int, glyph: int, author: int) -> void:
	_put_glyph(tile, surface, glyph)
	authors[key_of(tile, surface)] = author
	if run.diff_log != null:
		run.diff_log.record(WorldCoords.cell_of(tile), DiffLog.Kind.CHALK, key_of(tile, surface), {"glyph": glyph})


## HAZ-03: a roof fall erases every mark on its fallen tiles, and on the rib faces that border them
## (a face whose wall fell, or whose floor did, no longer exists).
func erase_chalk(run: RunState, tiles: Array[Vector2i]) -> int:
	var erased: int = 0
	for t: Vector2i in tiles:
		for s: int in ChalkMarks.SURFACES:
			erased += _wipe(run, t, s)
		for s: int in [ChalkMarks.Surface.NORTH, ChalkMarks.Surface.EAST, ChalkMarks.Surface.SOUTH, ChalkMarks.Surface.WEST]:
			var step: Vector2i = ChalkMarks.FACE_STEP[s]
			erased += _wipe(run, t - step, s)
	return erased


func _wipe(run: RunState, tile: Vector2i, surface: int) -> int:
	if glyph_at(tile, surface) == 0:
		return 0
	_put_glyph(tile, surface, 0)
	authors.erase(key_of(tile, surface))
	if run.diff_log != null:
		run.diff_log.erase(WorldCoords.cell_of(tile), DiffLog.Kind.CHALK, key_of(tile, surface))
	return 1


func _put_glyph(tile: Vector2i, surface: int, glyph: int) -> void:
	var g: PackedByteArray = marks.get(tile, PackedByteArray())
	if g.size() != ChalkMarks.SURFACES:
		g = PackedByteArray()
		g.resize(ChalkMarks.SURFACES)
	g[surface] = glyph
	var any: bool = false
	for b: int in g:
		any = any or b != 0
	if any:
		marks[tile] = g
	else:
		marks.erase(tile)
	show.call(tile, g if any else PackedByteArray())


## GEN-13: a mark back when its cell is committed again (or a save resumes).
func _replay(_r: RunState, _cell: Vector2i, key: String, p: Dictionary, _t: int) -> void:
	var parts: PackedStringArray = key.split(":")
	var xy: PackedStringArray = parts[0].split(",")
	var surface: int = ChalkMarks.SURFACE_KEYS.find(parts[1])
	if surface < 0:
		return
	var tile: Vector2i = Vector2i(int(xy[0]), int(xy[1]))
	var glyph: int = int(Variants.number(p.get("glyph", 0)))
	if glyph_at(tile, surface) != glyph:
		_put_glyph(tile, surface, glyph)
