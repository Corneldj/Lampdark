class_name OwnLampBlend
extends RefCounted
## VIS-06: the own lamp drawn at once. For each drawn tile:
##   display = clamp(server_total - server_own + predicted_own, 0, 1)
## where server_own is the own lamp as the server last had it (its own block: position and effective
## radius) and predicted_own NET-05's predicted lamp, both with VIS-02's shared falloff and a held
## wall standing between as a shadow. A wick step or the shutter shows before the server answers;
## when it does, the two terms cancel and nothing moves by more than a quantisation step. A
## provisional tile (not yet sent) shows the predicted own light alone. It never adds a tile: only
## VIS-05's drawn set is blended.


## {tile: light 0-1} for every tile of `drawn`. `server_lamp` / `predicted_lamp`: {position, radius}
## (radius 0 or {} for none).
static func lights(drawn: DrawnSet, view: ReceivedView, server_lamp: Dictionary, predicted_lamp: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in drawn.tiles.keys():
		var t: Vector2i = raw
		var d: Dictionary = drawn.tiles[raw]
		var centre: Vector2 = Vector2(t) + Vector2(0.5, 0.5)
		var predicted: float = own_light(view, predicted_lamp, centre)
		if Variants.flag(d["provisional"]):
			out[t] = predicted
			continue
		var total: float = float(Variants.number(d["light"]))
		out[t] = clampf(total - own_light(view, server_lamp, centre) + predicted, 0.0, 1.0)
	return out


## A lamp's light at a point (0-1): VIS-02's falloff, shadowed by held solid tiles.
static func own_light(view: ReceivedView, lamp: Dictionary, at: Vector2) -> float:
	var radius: float = float(Variants.number(lamp.get("radius", 0.0)))
	if radius <= 0.0:
		return 0.0
	var from: Vector2 = lamp["position"]
	if MarginReveal._shadowed(view.geometry, from, at):
		return 0.0
	return LbLightMath.falloff_milli(from.distance_to(at), radius, 1.0, Tuning.f(&"light.core_fraction"),
		Tuning.f(&"light.core_value"), Tuning.f(&"light.edge_value")) / 1000.0
