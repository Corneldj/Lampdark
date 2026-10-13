class_name ViewFit
extends RefCounted
## VIS-01: fitting the fixed view (camera.view_tiles_wide x camera.view_tiles_high tiles, 64 px a tile
## at 1080p) to any window: scaled to the largest size that fits, never widened, with pure-black bars
## on the spare sides (letterbox or pillarbox). The project's stretch settings (canvas_items, aspect
## keep, base 1920x1080, a black clear colour) make Godot do exactly this; `fit` states the numbers.

## Pure black is reserved for "no data": letterbox bars included (GDD §14.1).
const BAR_COLOUR: Color = Color(0, 0, 0, 1)


## The base canvas: the view at camera.tile_px_at_1080p.
static func base_px() -> Vector2:
	return ViewGeometry.view_size() * Tuning.f(&"camera.tile_px_at_1080p")


## {tile_px, visible (px of world shown), bars (px on each side: x left/right, y top/bottom)}.
static func fit(window: Vector2i) -> Dictionary:
	var base: Vector2 = base_px()
	var scale: float = minf(window.x / base.x, window.y / base.y)
	var visible: Vector2 = base * scale
	var bars: Vector2 = (Vector2(window) - visible) / 2.0
	return {"tile_px": Tuning.f(&"camera.tile_px_at_1080p") * scale, "visible": visible, "bars": bars,
		"visible_tiles": visible / (Tuning.f(&"camera.tile_px_at_1080p") * scale)}
