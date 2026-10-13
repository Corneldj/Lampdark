class_name HeldGeometryCache
extends RefCounted
## VIS-05 (Gameplay §5.10): the walls a client holds. The tile layout as received (floor and walls,
## Proposed), for cells within vision.held_geometry_cells (Chebyshev, in cells) of the miner's last
## server-acknowledged position: ReceivedView applies NET-04's held rule with exactly that, so this
## never keys on the predicted position. No light and no entities are held. A held tile is drawn
## only while it is in the drawn set (DrawnSet): never remembered, never outlined.


static func cell_of(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / WorldIds.CELL_TILES), floori(float(tile.y) / WorldIds.CELL_TILES))


## The held tiles of a view: {Vector2i: PackedByteArray [material, state]}, within the held cells of
## the acknowledged own position.
static func tiles(view: ReceivedView) -> Dictionary:
	var out: Dictionary = {}
	var own_cell: Vector2i = cell_of(view.own_tile())
	var held: int = Tuning.i(&"vision.held_geometry_cells")
	for raw: Variant in view.geometry.keys():
		var t: Vector2i = raw
		var c: Vector2i = cell_of(t)
		if absi(c.x - own_cell.x) <= held and absi(c.y - own_cell.y) <= held:
			out[t] = view.geometry[raw]
	return out
