class_name LineRouter
extends RefCounted
## LFT-12 (Gameplay §6.6, §12.5; GDD §15.4): a phone line's road home, through GEN-05's derived cells
## (LbLayouts.route_home: the shortest road from the phone to a gate of base camp, every collapse
## standing). It is a pure function of the seed and the phone, so any generation order finds the same
## line (Proposed: a fall that came before the phone generated cuts the line as one after does,
## rather than turning the line aside). Server-only.

## How far past the phone's own ring the road may wander (cells, Proposed).
const MARGIN_CELLS: int = 2


## {found, tiles (its length), cells (in order), crossings ([cell, collapse id] each)}.
static func route(layouts: LbLayouts, tile: Vector2i) -> Dictionary:
	var cell: Vector2i = WorldCoords.cell_of(tile)
	var r: Dictionary = layouts.route_home(tile, maxi(absi(cell.x), absi(cell.y)) + MARGIN_CELLS)
	var xs: PackedInt32Array = r.get("x", PackedInt32Array())
	var ys: PackedInt32Array = r.get("y", PackedInt32Array())
	var cells: Array[Vector2i] = []
	for i: int in xs.size():
		var c: Vector2i = WorldCoords.cell_of(Vector2i(xs[i], ys[i]))
		if cells.is_empty() or cells[cells.size() - 1] != c:
			cells.append(c)
	return {"found": Variants.flag(r.get("found", false)), "tiles": xs.size(), "cells": cells,
		"crossings": Variants.array(r.get("crossings", [])), "explored": int(Variants.number(r.get("explored", 0)))}
