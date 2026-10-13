class_name Tell
extends RefCounted
## CRT-01's tell: every hunt opens with a diffuse cue from several wall points, reaching beyond
## creatures.tell_min_reach_tiles (6), that says which creature is near, never where.
##  - Listener-centred (the Moth's rustle, the Stythe's breath): each listener within reach gets
##    the cue from three or more wall points chosen around the listener, on bearings drawn from
##    the creature's stream (never from its position), so their mean says nothing of its bearing. The record
##    holds the tell's kind and the points: no origin, no creature position, no entity ID.
##  - Creature-placed (the Tapper's taps): real sounds from three wall points within 15 tiles of
##    the Tapper, never its true tile; CRT-09 emits them so the dust agrees for everyone.

enum Form { LISTENER_CENTRED = 0, CREATURE_PLACED = 1 }

const POINTS: int = 3
## How far from the listener the points lie, tiles, and how far each moves to reach rock.
const POINT_MIN_TILES: float = 4.0
const POINT_MAX_TILES: float = 7.0
const SNAP_TILES: float = 2.0
const PLACED_WITHIN_TILES: float = 15.0

var id: int = 0
var creature: Creature = null
var tell_kind: StringName = &""
var reach_tiles: float = 0.0
var form: Form = Form.LISTENER_CENTRED
var start_tick: int = 0
var end_tick: int = -1
var valid: bool = true
## slot -> record sent, so each listener gets the cue once per tell.
var sent: Dictionary = {}


## Refuses (valid = false, an error) a reach of creatures.tell_min_reach_tiles or less.
static func make(c: Creature, run: RunState, kind: StringName, reach: float, tell_form: Form = Form.LISTENER_CENTRED) -> Tell:
	var t: Tell = Tell.new()
	t.creature = c
	t.tell_kind = kind
	t.reach_tiles = reach
	t.form = tell_form
	t.start_tick = run.tick
	if reach <= Tuning.f(&"creatures.tell_min_reach_tiles"):
		push_error("Tell: a reach of %.1f tiles is not beyond %.0f" % [reach, Tuning.f(&"creatures.tell_min_reach_tiles")])
		t.valid = false
	return t


func is_playing() -> bool:
	return valid and end_tick < 0


## The cue for one listener: the kind and the wall points around them. Nothing else.
static func cue_record(kind: StringName, points: Array[Vector2i]) -> Dictionary:
	return {"tell": kind, "points": points}


## Three or more wall points around `centre`: each at a distance drawn between POINT_MIN_TILES and
## POINT_MAX_TILES on its own bearing, all drawn from `rng`, then moved to the nearest rock tile
## within SNAP_TILES. Equal-length vectors on independent bearings make the direction of their mean
## uniformly random, whatever the walls around (bearings to the first wall would lean the mean
## toward open ground, where creatures are). With no rock that near, the point stays in the dark.
static func points_around(run: RunState, rng: LbRng, centre: Vector2, count: int = POINTS) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r: float = POINT_MIN_TILES + rng.unit_double() * (POINT_MAX_TILES - POINT_MIN_TILES)
	for k: int in count:
		var u: PackedFloat64Array = LbDetMath.unit(rng.unit_double())
		var p: Vector2 = centre + Vector2(u[0], u[1]) * r
		out.append(_nearest_rock(run, Vector2i(floori(p.x), floori(p.y))))
	return out


## The nearest rock tile within SNAP_TILES (ties by y, then x), or the tile itself.
static func _nearest_rock(run: RunState, at: Vector2i) -> Vector2i:
	if run.mine == null:
		return at
	var best: Vector2i = at
	var best_d2: int = -1
	var reach: int = ceili(SNAP_TILES)
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			var d2: int = dx * dx + dy * dy
			if float(d2) > SNAP_TILES * SNAP_TILES or (best_d2 >= 0 and d2 >= best_d2):
				continue
			var t: Vector2i = at + Vector2i(dx, dy)
			if not run.mine.native.is_walkable(t):
				best = t
				best_d2 = d2
	return best


## Three distinct wall faces (rock beside open floor) within PLACED_WITHIN_TILES of `centre`,
## never its own tile, drawn from `rng` (the Tapper's taps).
static func placed_points(run: RunState, rng: LbRng, centre: Vector2, count: int = POINTS) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if run.mine == null:
		return out
	var own: Vector2i = Vector2i(floori(centre.x), floori(centre.y))
	var r: int = floori(PLACED_WITHIN_TILES)
	for attempt: int in 400:
		if out.size() >= count:
			break
		var t: Vector2i = own + Vector2i(rng.range(-r, r), rng.range(-r, r))
		if t == own or out.has(t) or Vector2(t).distance_to(Vector2(own)) > PLACED_WITHIN_TILES:
			continue
		if run.mine.native.is_walkable(t):
			continue
		for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if run.mine.native.is_walkable(t + n):
				out.append(t)
				break
	return out
