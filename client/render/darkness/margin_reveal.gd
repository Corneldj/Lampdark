class_name MarginReveal
extends RefCounted
## VIS-04 on the client: a hidden margin record (an entity token of level 3) stays hidden until
## the client's predicted own light at it reaches 0.12 inside the predicted cone, using VIS-02's
## falloff, NET-05's predicted lamp and a held wall standing between them as a shadow. A record the server stops sending is gone with the view.
## The renderer (VIS-05) never draws a hidden record that this has not revealed.

const HIDDEN: int = 3
const SEEN_MILLI: int = 120

var cone_deg: float = 110.0
var core_fraction: float = 0.6
var core_value: float = 0.3
var edge_value: float = 0.12


func _init() -> void:
	if Tuning.current.has_key(&"vision.cone_deg"):
		cone_deg = Tuning.f(&"vision.cone_deg")
		core_fraction = Tuning.f(&"light.core_fraction")
		core_value = Tuning.f(&"light.core_value")
		edge_value = Tuning.f(&"light.edge_value")


## The hidden tokens of `view` that the predicted lamp ({position, radius}) reveals for a miner
## at `from` facing `facing`.
func revealed(view: ReceivedView, lamp: Dictionary, from: Vector2, facing: int) -> Array[int]:
	var out: Array[int] = []
	var radius: float = float(Variants.number(lamp.get("radius", 0.0)))
	if radius <= 0.0:
		return out
	var at: Vector2 = lamp["position"]
	var f: PackedFloat64Array = LbDetMath.unit(float(facing) / 65536.0)
	var cos_half: float = LbDetMath.cos_deg(cone_deg * 0.5)
	for raw: Variant in view.entities.keys():
		var token: int = int(Variants.number(raw))
		var e: Dictionary = view.entities[raw]
		if int(Variants.number(e["level"])) != HIDDEN:
			continue
		var p: Vector2 = e["position"]
		var light: int = LbLightMath.falloff_milli(at.distance_to(p), radius, 1.0, core_fraction, core_value, edge_value)
		if light < SEEN_MILLI or _shadowed(view.geometry, at, p):
			continue
		var v: Vector2 = p - from
		var dot: float = v.x * f[0] + v.y * f[1]
		if v.length() <= 0.5 or (dot >= 0.0 and dot * dot >= cos_half * cos_half * v.length_squared()):
			out.append(token)
	out.sort()
	return out


## Whether a held solid tile stands on the line from the lamp to `to`, short of `to`'s own tile.
## Tiles the client does not hold count as open (HeldGeometry); the server sends a margin record
## only in line of sight, so this only keeps a reveal from leaking past a wall the client knows.
static func _shadowed(geometry: Dictionary, from: Vector2, to: Vector2) -> bool:
	var end: Vector2i = Vector2i(floori(to.x), floori(to.y))
	var steps: int = ceili(from.distance_to(to) * 4.0)
	for i: int in range(1, steps):
		var q: Vector2 = from.lerp(to, float(i) / steps)
		var t: Vector2i = Vector2i(floori(q.x), floori(q.y))
		if t == end:
			break
		if geometry.has(t):
			var g: PackedByteArray = geometry[t]
			if HeldGeometry.is_solid(g[0], g[1]):
				return true
	return false
