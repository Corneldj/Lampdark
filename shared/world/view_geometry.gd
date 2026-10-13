class_name ViewGeometry
extends RefCounted
## VIS-01: the camera's view geometry, shared by the client's camera (LampCamera) and the server's
## detail region (VIS-03, native seen_set's frame: the same tuning). The view is a fixed 30 x 16.875
## tiles (camera.view_tiles_wide/high), centred on the miner plus a lead along the facing: 3 tiles
## normally, 8 (camera.squint_lead_tiles) while squinting or aiming. Positions are in tiles.


static func view_size() -> Vector2:
	return Vector2(Tuning.f(&"camera.view_tiles_wide"), Tuning.f(&"camera.view_tiles_high"))


## The unit vector of a facing (0-65536 over 360 degrees, clockwise from east, y down).
static func facing_vector(facing: int) -> Vector2:
	var u: PackedFloat64Array = LbDetMath.unit(float(facing & 0xFFFF) / 65536.0)
	return Vector2(u[0], u[1])


static func view_rect(miner_pos: Vector2, facing: int, lead_tiles: float) -> Rect2:
	var size: Vector2 = view_size()
	return Rect2(miner_pos + facing_vector(facing) * lead_tiles - size / 2.0, size)


## The view at the full squint lead: what VIS-03 sends detail out to whether or not anyone squints.
static func full_squint_rect(miner_pos: Vector2, facing: int) -> Rect2:
	return view_rect(miner_pos, facing, Tuning.f(&"camera.squint_lead_tiles"))


## VIS-03's detail region: the full-squint view widened by vision.detail_widen_tiles each side.
static func detail_rect(miner_pos: Vector2, facing: int) -> Rect2:
	return full_squint_rect(miner_pos, facing).grow(Tuning.f(&"vision.detail_widen_tiles"))
