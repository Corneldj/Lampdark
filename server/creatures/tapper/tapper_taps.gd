class_name TapperTaps
extends RefCounted
## CRT-09's hunting taps: every tapper.tap_interval_s (2-4 s, from the creatures.tapper stream),
## tapper.tap_points usable faces within tapper.tap_radius_tiles of the Tapper (Search:
## tapper.search_tap_radius_tiles), none within tapper.tap_min_offset_tiles of its true face, as
## one tapper.tap_np rock-tap event (SND-02). The Tapper's own hearing ignores it (a creature made
## it) and it makes nobody heard. Dust goes to VIS-09 for the points whose open floor is lit.

var next_tick: int = -1
## The last tap's points, and those lit (dust).
var last_points: Array[Vector2i] = []
var last_lit: Array[Vector2i] = []


func reset() -> void:
	next_tick = -1


func tick(run: RunState, t: Tapper, radius: float) -> bool:
	var hz: float = Tuning.f(&"net.tick_hz")
	var gap: Vector2 = Tuning.range_f(&"tapper.tap_interval_s")
	if next_tick < 0:
		next_tick = run.tick + t.rng.range(roundi(gap.x * hz), roundi(gap.y * hz))
		return false
	if run.tick < next_tick:
		return false
	next_tick = run.tick + t.rng.range(roundi(gap.x * hz), roundi(gap.y * hz))
	var points: Array[Vector2i] = pick(run, t, radius)
	if points.size() < Tuning.i(&"tapper.tap_points"):
		return false
	run.noise.emit(NoiseTypes.Type.ROCK_TAP, points[0], {"origins": points, "level_np": Tuning.f(&"tapper.tap_np"), "source": t.entity_id})
	last_points = points
	last_lit = []
	for p: Vector2i in points:
		if _lit(run, p):
			last_lit.append(p)
	t.tapped.emit(points, last_lit)
	t.system.log.add(run.tick, &"tapper_taps", {"points": points, "dust": last_lit})
	return true


## Distinct usable faces in range, away from the true face, drawn from the creature's stream.
func pick(run: RunState, t: Tapper, radius: float) -> Array[Vector2i]:
	var own: Vector2i = t.tile(run)
	var away: float = Tuning.f(&"tapper.tap_min_offset_tiles")
	var pool: Array[Vector2i] = []
	for f: Vector2i in t.system.nav.native.usable_faces_within(t.position(run), radius):
		if Vector2(f).distance_to(Vector2(own)) >= away:
			pool.append(f)
	var out: Array[Vector2i] = []
	while out.size() < Tuning.i(&"tapper.tap_points") and not pool.is_empty():
		out.append(pool.pop_at(t.rng.range(0, pool.size() - 1)))
	return out


## A face is dusted when the open floor beside it is seen-lit (vision.seen_light_min).
static func _lit(run: RunState, face: Vector2i) -> bool:
	if run.light == null:
		return false
	for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if run.mine.native.is_walkable(face + n) and run.light.light_at(face + n) >= Tuning.f(&"vision.seen_light_min"):
			return true
	return false
