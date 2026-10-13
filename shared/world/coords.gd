class_name WorldCoords
## Typed world-coordinate helpers (FND-07) over the native LbWorld. Tiles are 1 m; +x east,
## +y south (north is up). Cells are 20x20 tiles, blocks 2x2 cells, regions 5x5 cells.
## Continuous positions are Vector2 in tile units.


static func cell_of(tile: Vector2i) -> Vector2i:
	return LbWorld.cell_of(tile)


static func local_of(tile: Vector2i) -> Vector2i:
	return LbWorld.local_of(tile)


static func tile_of(cell: Vector2i, local: Vector2i) -> Vector2i:
	return LbWorld.tile_of(cell, local)


## The tile under a continuous position: each axis floored.
static func tile_at(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x), floori(position.y))


static func block_of_cell(cell: Vector2i) -> Vector2i:
	return LbWorld.block_of_cell(cell)


static func region_of_cell(cell: Vector2i) -> Vector2i:
	return LbWorld.region_of_cell(cell)


static func cell_chebyshev(a: Vector2i, b: Vector2i) -> int:
	return LbWorld.cell_chebyshev(a, b)


static func cell_manhattan(a: Vector2i, b: Vector2i) -> int:
	return LbWorld.cell_manhattan(a, b)


## The ring (0-4) of a tile, by depth.ring_start_tiles. Whose tile counts is the caller's rule
## (Gameplay §10.6): a creature its own, the Pull the miner's, the seam's drink the lamp's.
## FND-08's `ring_override` (dev and QA, server-side): every ring lookup here returns this ring, so
## the ring-0 grey box can test deeper values (DIR-04). -1: off. Native code's own lookups (the
## generator's) are unaffected.
static var ring_override: int = -1


static func ring_of_tile(tile: Vector2i) -> int:
	return ring_override if ring_override >= 0 else LbWorld.ring_of_tile(tile)


static func ring_of_point(position: Vector2) -> int:
	return ring_override if ring_override >= 0 else LbWorld.ring_of_point(position.x, position.y)


## The shaft centre in tile units: (10.0, 10.0), the middle of cell (0,0).
static func shaft_centre() -> Vector2:
	return Vector2(WorldIds.SHAFT_CENTRE_X2 / 2.0, WorldIds.SHAFT_CENTRE_Y2 / 2.0)
