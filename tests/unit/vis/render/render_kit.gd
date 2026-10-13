extends RefCounted
## VIS-05 render-test helpers. Tests run with a real renderer only under
## tools/build/run_render_tests.sh (a headless gamescope); in the plain headless suite they are pending.
## A synthetic frame: tiles lit around the miner, the drawn set chosen by the test, the root viewport
## captured at the 1080p base (64 px a tile).

const ORIGIN: Vector2 = Vector2(0.0, 0.0)
const MINER: Vector2 = Vector2(15.0, 8.4375)


static func has_renderer() -> bool:
	return DisplayServer.get_name() != "headless" and not RenderingServer.get_video_adapter_name().is_empty()


## A view whose seen tiles are `tiles` (light 0-1 each), floor everywhere.
static func view_with(tiles: Dictionary) -> ReceivedView:
	var v: ReceivedView = ReceivedView.new()
	for raw: Variant in tiles.keys():
		var t: Vector2i = raw
		v.tiles[t] = PackedByteArray([roundi(float(Variants.number(tiles[raw])) * 255.0), 1, 0])
		v.geometry[t] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])
	v.own["position"] = MINER
	return v


## Every tile of the view lit to `light`.
static func all_lit(light: float) -> Dictionary:
	var out: Dictionary = {}
	for y: int in range(-1, 18):
		for x: int in range(-1, 31):
			out[Vector2i(x, y)] = light
	return out


static func drawn_from(view: ReceivedView) -> DrawnSet:
	var d: DrawnSet = DrawnSet.new()
	d.build(view, {"position": MINER, "facing": 0, "lamp": {}}, 0, -1)
	return d


## The screen pixel at a world point (tiles).
static func px(world: Vector2) -> Vector2i:
	var p: Vector2 = (world - ORIGIN) * Tuning.f(&"camera.tile_px_at_1080p")
	return Vector2i(floori(p.x), floori(p.y))


static func is_black(c: Color) -> bool:
	return c.r8 == 0 and c.g8 == 0 and c.b8 == 0
