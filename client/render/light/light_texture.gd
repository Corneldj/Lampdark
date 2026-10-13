class_name LightTexture
extends RefCounted
## VIS-06: the received light as a small texture over the view, one texel per tile: R the light
## (0-255, NET-04's quantisation, after the own-lamp blend), G the colour class, B 255 where the tile
## was sent (in the drawn set), A 255 for a solid tile. The light pool samples it with a custom
## bilinear that leaves unsent neighbours out (`sample` is the same rule on the CPU), so light never
## bleeds into an unsent tile: a bite stays a hard notch, a wall's shadow stays hard.

var image: Image = null
var origin: Vector2i = Vector2i.ZERO
var size: Vector2i = Vector2i.ZERO


## `lights`: tile -> light (0-1) for every drawn tile (OwnLampBlend's output).
func build(drawn: DrawnSet, lights: Dictionary, view_origin: Vector2, view_size: Vector2) -> void:
	origin = Vector2i(floori(view_origin.x) - 1, floori(view_origin.y) - 1)
	size = Vector2i(ceili(view_size.x) + 3, ceili(view_size.y) + 3)
	image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if drawn == null:
		return
	for raw: Variant in drawn.tiles.keys():
		var t: Vector2i = raw
		var p: Vector2i = t - origin
		if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y:
			continue
		var d: Dictionary = drawn.tiles[raw]
		var light: float = float(Variants.number(lights.get(t, d["light"])))
		var solid: bool = HeldGeometry.is_solid(int(Variants.number(d["material"])), int(Variants.number(d["state"])))
		image.set_pixel(p.x, p.y, Color8(clampi(roundi(light * 255.0), 0, 255), int(Variants.number(d.get("colour", 1))), 255, 255 if solid else 0))


## The light at a world point (tiles), as the light pool reads it: 0 in an unsent tile; otherwise
## bilinear between tile centres over sent neighbours only, renormalised.
func sample(world: Vector2) -> float:
	var own: Vector2i = Vector2i(floori(world.x), floori(world.y))
	if not _sent(own):
		return 0.0
	var f: Vector2 = world - Vector2(0.5, 0.5)
	var base: Vector2i = Vector2i(floori(f.x), floori(f.y))
	var frac: Vector2 = f - Vector2(base)
	var total: float = 0.0
	var weight: float = 0.0
	for dy: int in 2:
		for dx: int in 2:
			var t: Vector2i = base + Vector2i(dx, dy)
			if not _sent(t):
				continue
			var w: float = (frac.x if dx == 1 else 1.0 - frac.x) * (frac.y if dy == 1 else 1.0 - frac.y)
			total += w * _light(t)
			weight += w
	return total / weight if weight > 1e-9 else _light(own)


func _sent(t: Vector2i) -> bool:
	var p: Vector2i = t - origin
	return p.x >= 0 and p.y >= 0 and p.x < size.x and p.y < size.y and image.get_pixel(p.x, p.y).b8 == 255


func _light(t: Vector2i) -> float:
	var p: Vector2i = t - origin
	return image.get_pixel(p.x, p.y).r8 / 255.0
