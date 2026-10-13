class_name SimEntity
extends RefCounted
## One server entity (NET-01): FND-07's ID and kind, a position in tile units, and flags.
## Server-only: NET-04 maps the ID to per-client tokens; it is never written to a client.

var id: int = 0
var kind: WorldIds.EntityKind = WorldIds.EntityKind.NONE
var position: Vector2 = Vector2.ZERO
var flags: int = 0

## Flag bits (data/world/perception_classes.json names them for VIS-03).
## A large entity at rest that shares the motionless token class (CRT-05 sets it on a sleeping Moth).
const FLAG_MOTIONLESS: int = 1


func tile() -> Vector2i:
	return WorldCoords.tile_at(position)


func cell() -> Vector2i:
	return WorldCoords.cell_of(tile())
