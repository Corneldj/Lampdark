class_name HeatMap
extends RefCounted
## CRT-08's memory: heat on wall faces from what the Tapper heard, over the window
## tapper.heat_window_s_by_crew (90-135 s by crew count). Each heard event adds heat at the usable
## face nearest its apparent position, weighted by the energy that reached the Tapper times the
## event's duration (GDD §15.4). Server-only.

const FACE_SEARCH_TILES: int = 4

## face (Vector2i) -> Array of [tick, weight]
var faces: Dictionary = {}


func add(run: RunState, nav: CreatureNav, apparent: Vector2, energy_np: float, duration_s: float) -> Variant:
	var face: Variant = nav.native.nearest_usable_face(apparent, FACE_SEARCH_TILES)
	if face == null:
		return null
	var entries: Array = faces.get(face, [])
	entries.append([run.tick, maxf(energy_np, 0.0) * maxf(duration_s, 0.0)])
	faces[face] = entries
	return face


## Drops entries older than the window for this crew count.
func prune(run: RunState, crew_count: int) -> void:
	var oldest: int = run.tick - window_ticks(crew_count)
	for raw: Variant in faces.keys():
		var kept: Array = []
		for e: Variant in Variants.array(faces[raw]):
			var entry: Array = Variants.array(e)
			if int(Variants.number(entry[0])) > oldest:
				kept.append(entry)
		if kept.is_empty():
			faces.erase(raw)
		else:
			faces[raw] = kept


static func window_ticks(crew_count: int) -> int:
	return roundi(CreatureTables.tapper_heat_window_s(crew_count) * Tuning.f(&"net.tick_hz"))


func heat_of(face: Vector2i) -> float:
	var sum: float = 0.0
	for e: Variant in Variants.array(faces.get(face, [])):
		sum += Variants.number(Variants.array(e)[1])
	return sum


## The face with the most heat in the window (ties: tile order), or null when cold.
func hottest() -> Variant:
	var best: Variant = null
	var best_heat: float = 0.0
	var keys: Array = faces.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for raw: Variant in keys:
		var f: Vector2i = raw
		var h: float = heat_of(f)
		if h > best_heat:
			best_heat = h
			best = f
	return best


func is_cold() -> bool:
	return faces.is_empty()
