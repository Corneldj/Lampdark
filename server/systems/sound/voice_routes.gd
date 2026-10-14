class_name VoiceRoutes
extends RefCounted
## SND-07: who hears a speaker's voice frames, and how (Gameplay §6.2, A.3; GDD §15.5 step 4). A
## band's range runs by road (SND-01's VOICE mode: closed doors and shut gates are impassable) or,
## where it reaches further, along a rock line of at most voice.rock_line_max_rock_tiles solid
## tiles with no brick or door, within voice.rock_line_range_factor of the range, muffled and heard
## from the listener-side wall face. Gain falls linearly in dB from 0 at the source to
## voice.edge_gain_db at the range's edge. Each speaker has a route, set by its owning ticket:
## NORMAL; DRAGGED (CRT-14) and COMING_ROUND (RSC-04) at whisper range, muffled; FALL_SCREAM (SND-15)
## at shout range; CUT (SND-15) and ASIDE (SND-14) to nobody. Two primitives bypass range: direct
## lines (LFT-12's phones: telephone band) and shared channels (RSC-04's dream channel, RSC-06's
## Lamp Check: dry, unspatialised, to every member).

enum Route { NORMAL, DRAGGED, FALL_SCREAM, CUT, COMING_ROUND, ASIDE, FALL_MUFFLED }

const RANGE_KEYS: Array[StringName] = [&"", &"voice.whisper_range_tiles", &"voice.talk_range_tiles",
	&"voice.shout_range_tiles", &"voice.scream_range_tiles"]


## The band's range by road, tiles (0 for silent).
static func range_tiles(band: int) -> float:
	if band <= 0 or band > 4:
		return 0.0
	return Tuning.f(RANGE_KEYS[band])


## The band and muffling a route imposes: [range band, forced muffle, reaches anyone].
static func route_band(route: Route, band: int) -> Array:
	match route:
		Route.DRAGGED, Route.COMING_ROUND:
			return [1, true, true]
		Route.FALL_SCREAM:
			return [3, false, true]
		Route.FALL_MUFFLED:
			return [1, true, true]  # SND-15: a drag victim's scream, muffled at whisper range
		Route.CUT, Route.ASIDE:
			return [band, false, false]
	return [band, false, true]


## One listener's delivery from `from` (tile, position) at `band`: {} when out of reach, else
## {gain_db, muffled, position (apparent, tiles), via ("road" or "rock"), distance, range}: SND-08
## measures the rock line's distance against its own range (half the band's).
static func reach(graph: LbRoadGraph, from_tile: Vector2i, from_pos: Vector2, to_tile: Vector2i, band: int, key: int) -> Dictionary:
	var range_t: float = range_tiles(band)
	if range_t <= 0.0:
		return {}
	# No road is shorter than the straight line, and the rock line is shorter still: out of range
	# without a search.
	if Vector2(from_tile).distance_to(Vector2(to_tile)) > range_t + 1e-6:
		return {}
	var edge: float = Tuning.f(&"voice.edge_gain_db")
	var d: Dictionary = graph.deliver(from_tile, range_t, to_tile, LbRoadGraph.MODE_VOICE, 0.0, 1.0, key)
	if not d.is_empty():
		var path: float = float(Variants.number(d.get("path_tiles", 0.0)))
		var apparent: Vector2 = d.get("apparent", from_pos)
		return {"gain_db": edge * clampf(path / range_t, 0.0, 1.0), "muffled": false, "position": apparent, "via": "road",
			"distance": path, "range": range_t}
	var rock_range: float = range_t * Tuning.f(&"voice.rock_line_range_factor")
	var line: Dictionary = graph.rock_line(from_tile, to_tile)
	if line.is_empty() or Variants.flag(line.get("brick", false)) or Variants.flag(line.get("door", false)):
		return {}
	var solid: int = int(Variants.number(line.get("solid_tiles", 0)))
	var dist: float = float(Variants.number(line.get("distance", INF)))
	if solid < 1 or solid > roundi(Tuning.f(&"voice.rock_line_max_rock_tiles")) or dist > rock_range + 1e-6 \
			or not Variants.flag(line.get("has_face", false)):
		return {}
	var face: Vector2i = line.get("listener_face", to_tile)
	return {"gain_db": edge * clampf(dist / range_t, 0.0, 1.0), "muffled": true, "position": Vector2(face) + Vector2(0.5, 0.5),
		"via": "rock", "distance": dist, "range": rock_range}
