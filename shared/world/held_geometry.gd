class_name HeldGeometry
extends RefCounted
## What a client may know of a tile it holds (NET-04's geometry records): whether a body passes
## it. The same rule as the server's material table (data/world/materials.json): floor is open,
## a gate or an air door is open only when its state says so, everything else is solid. Tiles the
## client does not hold count as open, so walking into an unseen wall overruns until the server's
## stop arrives (NET-05): nothing about unseen tiles is ever requested.

const STATE_OPEN: int = 1


static func is_solid(material: int, state: int) -> bool:
	if material == WorldIds.TileMaterial.FLOOR:
		return false
	if material == WorldIds.TileMaterial.STEEL or material == WorldIds.TileMaterial.WOODEN_DOOR:
		return (state & STATE_OPEN) == 0
	return true


## A solidity query over a client's held geometry ({Vector2i: PackedByteArray [material, state]}).
static func query(geometry: Dictionary) -> Callable:
	return func(tile: Vector2i) -> bool:
		if not geometry.has(tile):
			return false
		var g: PackedByteArray = geometry[tile]
		return is_solid(g[0], g[1])
