class_name EdgeGlow
extends RefCounted
## VIS-06 (GDD §14.3): seen lit tiles in the cone beyond the screen show as direction and colour only.
## Two sources: received seen tiles off screen at the current lead (inside the full-squint view), and
## NET-04's edge-glow buckets beyond the detail region (vision.edge_glow_bucket_deg wide, across the
## cone from its left edge). Each becomes a strip light.edge_glow_strip_tiles deep where its bearing
## from the miner meets the view's border, coloured by class, at one fixed strength: no distance or
## brightness cue. It draws inside the view (never in the bars), after the darkness composite.

## Marks: {at (Vector2 tiles, on the border), side (0 top, 1 right, 2 bottom, 3 left), colour}
static func layout(view: Rect2, miner: Vector2, facing: int, glow_mask: int, glow_colour: PackedByteArray,
		offscreen: Dictionary) -> Array[Dictionary]:
	var marks: Dictionary = {}
	var cone: float = Tuning.f(&"vision.cone_deg")
	var step: float = Tuning.f(&"vision.edge_glow_bucket_deg")
	var facing_deg: float = facing / 65536.0 * 360.0
	var n: int = maxi(1, roundi(cone / step))
	for b: int in n:
		if (glow_mask >> b) & 1 == 0:
			continue
		var bearing: float = facing_deg - cone * 0.5 + (b + 0.5) * step
		_mark(marks, view, miner, Vector2.from_angle(deg_to_rad(bearing)), glow_colour[b] if b < glow_colour.size() else 0)
	for raw: Variant in offscreen.keys():
		var t: Vector2i = raw
		var centre: Vector2 = Vector2(t) + Vector2(0.5, 0.5)
		if view.has_point(centre):
			continue
		_mark(marks, view, miner, (centre - miner).normalized(), int(Variants.number(offscreen[raw])))
	var out: Array[Dictionary] = []
	var keys: Array = marks.keys()
	keys.sort()
	for k: Variant in keys:
		out.append(marks[k])
	return out


static func _mark(marks: Dictionary, view: Rect2, miner: Vector2, dir: Vector2, colour: int) -> void:
	var hit: Dictionary = border_hit(view, miner, dir)
	if hit.is_empty():
		return
	var at: Vector2 = hit["at"]
	var key: Vector2i = Vector2i(roundi(at.x * 2.0), roundi(at.y * 2.0))
	if not marks.has(key):
		marks[key] = {"at": at, "side": hit["side"], "colour": colour}


## Where a ray from `from` (inside the view) along `dir` leaves it: {at, side}, or {}.
static func border_hit(view: Rect2, from: Vector2, dir: Vector2) -> Dictionary:
	var best: float = INF
	var side: int = -1
	if dir.y < -1e-9:
		var t: float = (view.position.y - from.y) / dir.y
		if t < best:
			best = t
			side = 0
	if dir.x > 1e-9:
		var t: float = (view.end.x - from.x) / dir.x
		if t < best:
			best = t
			side = 1
	if dir.y > 1e-9:
		var t: float = (view.end.y - from.y) / dir.y
		if t < best:
			best = t
			side = 2
	if dir.x < -1e-9:
		var t: float = (view.position.x - from.x) / dir.x
		if t < best:
			best = t
			side = 3
	if side < 0:
		return {}
	return {"at": from + dir * best, "side": side}
