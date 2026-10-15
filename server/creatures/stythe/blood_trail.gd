class_name BloodTrail
extends RefCounted
## CRT-15 (Gameplay §7.4, §8.1): the blood trail. Every floor tile a dragged or collected victim
## crosses is smeared, pointing along the drag (toward the lair), permanent for the run: it always
## leads to the lair, never home, and trails from several drags converge there. A tile crossed
## twice keeps its latest direction (Proposed). The grab tile takes the heading of the first step
## off it. A roof fall (HAZ-03) erases the tiles it covers through `erase`.
##
## The smear itself is VIS-10's (seen at 0.12, a decal with its direction) and GEN-13 keeps it in
## the diff log, so evicted cells and saves keep their trails: ServerSystems wires `smear` and `wipe`
## to the vision's trail (a creature reads only its own sense). Server-only.

## (tile: Vector2i, direction: int) -> void: smear the tile (VIS-10's mark_trail).
var smear: Callable = func(_tile: Vector2i, _direction: int) -> void: pass
## (tile: Vector2i) -> void: wipe it (VIS-10's erase_trail).
var wipe: Callable = func(_tile: Vector2i) -> void: pass
## tile -> {direction, tick}: every trail tile of the run.
var tiles: Dictionary = {}
## The tile the victim was last on, and whether it is smeared yet (the grab tile waits for a
## heading).
var _last: Vector2i = Vector2i(2147483647, 0)
var _last_smeared: bool = true
var _run: RunState = null


func attach(run: RunState, st: StytheCreature) -> void:
	_run = run
	st.drag_tile_crossed.connect(_on_crossed)


## CRT-14's drag_tile_crossed: -1 at the grab tile, then each new tile with the heading.
func _on_crossed(tile: Vector2i, direction: int) -> void:
	if direction < 0:
		_last = tile
		_last_smeared = false
		return
	if not _last_smeared and _last.x != 2147483647:
		mark(_last, direction)
	# A pull of more than a tile (the grab draws the victim onto the Stythe) crosses the tiles
	# between: the trail stays continuous.
	if _last.x != 2147483647:
		for t: Vector2i in between(_last, tile):
			mark(t, direction)
	mark(tile, direction)
	_last = tile
	_last_smeared = true


## The tiles strictly between `a` and `b` on the straight line (one per step of the longer axis).
static func between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d: Vector2i = b - a
	var steps: int = maxi(absi(d.x), absi(d.y))
	for i: int in range(1, steps):
		out.append(a + Vector2i(roundi(d.x * float(i) / steps), roundi(d.y * float(i) / steps)))
	return out


func mark(tile: Vector2i, direction: int) -> void:
	tiles[tile] = {"direction": posmod(direction, 8), "tick": _run.tick if _run != null else 0}
	smear.call(tile, posmod(direction, 8))


## HAZ-03: a roof fall erases blood on exactly its tiles.
func erase(fallen: Array[Vector2i]) -> void:
	for t: Vector2i in fallen:
		tiles.erase(t)
		wipe.call(t)


func direction_at(tile: Vector2i) -> int:
	return int(Variants.number(Variants.dict(tiles.get(tile, {})).get("direction", -1)))
