class_name DrawnSet
extends RefCounted
## VIS-05: what the client may draw this frame, and nothing else. The union of (1) the tiles in the
## latest server frame's seen set; (2) margin records VIS-04 has revealed (MarginReveal); and (3) held
## tiles inside the predicted cone where the predicted own light reaches vision.seen_light_min,
## provisional until the server frame acknowledging the input that carried the new facing (NET-05),
## or while the predicted own lamp outreaches the server's (VIS-06's wick step):
## from then on only what the server lists stays. Entities come only from (1) and (2): a level 3
## record is never drawn before its reveal. An entity the server stops sending is gone at once.

## Vector2i -> {light (0-1), material, state, provisional (bool)}
var tiles: Dictionary = {}
## Tokens drawn this frame (fringe tokens, identities, revealed margin records), ascending.
var entities: Array[int] = []
var provisional_count: int = 0
var reveal: MarginReveal = MarginReveal.new()


## `predicted`: {position (Vector2 tiles), facing (u16), lamp: {position, radius}}. `facing_seq`: the
## input seq that last changed the facing (-1 none); `input_ack`: the newest seq the server applied.
func build(view: ReceivedView, predicted: Dictionary, input_ack: int, facing_seq: int) -> void:
	tiles.clear()
	entities.clear()
	provisional_count = 0
	if view == null:
		return
	var held: Dictionary = HeldGeometryCache.tiles(view)
	for raw: Variant in view.tiles.keys():
		var t: Vector2i = raw
		var b: PackedByteArray = view.tiles[raw]
		var g: PackedByteArray = held.get(t, PackedByteArray([WorldIds.TileMaterial.FLOOR, 0]))
		# VIS-10: the colour byte's top bit is the egg-glow hatch tell, never a colour class.
		tiles[t] = {"light": b[0] / 255.0, "colour": b[1] & ~TileBits.COLOUR_HATCH_BIT, "hatch": (b[1] & TileBits.COLOUR_HATCH_BIT) != 0,
			"material": g[0], "state": g[1], "provisional": false}
	# Provisional while the server has not yet answered a turn, or while the predicted own lamp is
	# larger than the server's (a wick step up, the shutter opening: VIS-06 draws the pool at once).
	var lamp_ahead: bool = float(Variants.number(Variants.dict(predicted.get("lamp", {})).get("radius", 0.0))) \
		> float(Variants.number(view.own.get("lamp_radius", 0.0))) + 1e-6
	if (facing_seq >= 0 and InputPacket.seq_diff(facing_seq, input_ack) > 0) or lamp_ahead:
		_add_provisional(view, held, predicted)
	var from: Vector2 = predicted.get("position", Vector2.ZERO)
	var facing: int = int(Variants.number(predicted.get("facing", 0)))
	var lamp: Dictionary = Variants.dict(predicted.get("lamp", {}))
	var revealed: Array[int] = reveal.revealed(view, lamp, from, facing) if not lamp.is_empty() else ([] as Array[int])
	for raw: Variant in view.entities.keys():
		var token: int = int(Variants.number(raw))
		var level: int = int(Variants.number(Variants.dict(view.entities[raw])["level"]))
		if level == 1 or level == 2 or (level == MarginReveal.HIDDEN and revealed.has(token)):
			entities.append(token)
	entities.sort()


## Held tiles the predicted own light shows inside the predicted cone, before the server says so.
func _add_provisional(view: ReceivedView, held: Dictionary, predicted: Dictionary) -> void:
	var lamp: Dictionary = Variants.dict(predicted.get("lamp", {}))
	var radius: float = float(Variants.number(lamp.get("radius", 0.0)))
	if radius <= 0.0:
		return
	var at: Vector2 = lamp["position"]
	var from: Vector2 = predicted["position"]
	var facing: int = int(Variants.number(predicted["facing"]))
	var seen_milli: int = roundi(Tuning.f(&"vision.seen_light_min") * 1000.0)
	for raw: Variant in held.keys():
		var t: Vector2i = raw
		if tiles.has(t):
			continue
		var centre: Vector2 = Vector2(t) + Vector2(0.5, 0.5)
		if not in_cone(from, facing, centre):
			continue
		var light: int = LbLightMath.falloff_milli(at.distance_to(centre), radius, 1.0, Tuning.f(&"light.core_fraction"),
			Tuning.f(&"light.core_value"), Tuning.f(&"light.edge_value"))
		if light < seen_milli or MarginReveal._shadowed(view.geometry, at, centre):
			continue
		var g: PackedByteArray = held[raw]
		tiles[t] = {"light": light / 1000.0, "colour": 1, "material": g[0], "state": g[1], "provisional": true}
		provisional_count += 1


## The analytic cone (vision.cone_deg), straight edges from the miner; the miner's own point is in it.
static func in_cone(from: Vector2, facing: int, p: Vector2) -> bool:
	var v: Vector2 = p - from
	var len_sq: float = v.length_squared()
	if len_sq < 1e-8:
		return true
	var f: Vector2 = ViewGeometry.facing_vector(facing)
	var d: float = v.x * f.x + v.y * f.y
	var c: float = LbDetMath.cos_deg(Tuning.f(&"vision.cone_deg") * 0.5)
	return d >= 0.0 and d * d >= c * c * len_sq
