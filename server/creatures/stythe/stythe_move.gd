class_name StytheMove
extends RefCounted
## CRT-13 (Gameplay §7.4): how the Stythe moves. Light is walls: CRT-02's DARK mode at its threshold
## (closed air doors and gates are walls too; base camp's 0.6 always). It moves at stythe.speed,
## its path replanned at stythe.replan_hz and the same tick a tile on it lights (NavFollower checks
## the rest of its path every tick); with no dark path it goes to the reachable dark tile nearest its
## goal (NavFollower's DARK fallback). Light reaching its tile pushes it to the nearest dark tile
## (`pushed`: no wind-up, no snuff meanwhile). Circling paces CRT-02's light_edge_ring round a light
## at stythe.circle_speed (Proposed). Server-only.

var follower: NavFollower = NavFollower.new()
## The goal it was last sent toward (-huge: none).
var goal: Vector2i = Vector2i(2147483647, 0)
var _last_plan: int = -1
var _ring: Array[Vector2i] = []
var _ring_at: int = -1
var _ring_seed: Vector2i = Vector2i(2147483647, 0)


func params(st: StytheCreature) -> Dictionary:
	return NavModes.dark(st.thin)


## Heads for `to` through the dark (a no-op while already heading there).
func head_for(run: RunState, st: StytheCreature, to: Vector2i) -> void:
	if to == goal and follower.status != NavFollower.Status.IDLE and follower.status != NavFollower.Status.BLOCKED:
		return
	goal = to
	_plan(run, st)


func stop() -> void:
	follower.stop()
	goal = Vector2i(2147483647, 0)
	_ring.clear()
	_ring_at = -1
	_ring_seed = Vector2i(2147483647, 0)


## One tick at `speed`: replanned at stythe.replan_hz while moving.
func tick(run: RunState, st: StytheCreature, speed: float) -> NavFollower.Status:
	var every: int = maxi(1, roundi(Tuning.f(&"net.tick_hz") / Tuning.f(&"stythe.replan_hz")))
	if follower.status == NavFollower.Status.MOVING and _last_plan >= 0 and run.tick - _last_plan >= every:
		_plan(run, st)
	return follower.tick(run, st.system.nav, st, speed)


## Pushed off light: the nearest dark tile, if its own tile is lit to its threshold.
func push_off_light(run: RunState, st: StytheCreature) -> bool:
	if st.unlit(run, st.tile(run)):
		return false
	var to: Variant = st.system.nav.native.nearest_dark_tile(st.position(run), st.light_threshold(), 12)
	if to != null:
		var t: Vector2i = to
		head_for(run, st, t)
	return true


## Circling a light round `seed` (a lit tile): the dark floor at its edge, walked in order.
func circle(run: RunState, st: StytheCreature, seed: Vector2i) -> void:
	if seed != _ring_seed or _ring.is_empty():
		_ring_seed = seed
		_ring.clear()
		for raw: Variant in st.system.nav.native.light_edge_ring(seed, st.light_threshold(), 400):
			_ring.append(raw)
		var centre: Vector2 = Vector2(seed) + Vector2(0.5, 0.5)
		_ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var aa: float = (Vector2(a) + Vector2(0.5, 0.5) - centre).angle()
			var bb: float = (Vector2(b) + Vector2(0.5, 0.5) - centre).angle()
			return aa < bb if not is_equal_approx(aa, bb) else (a.y < b.y or (a.y == b.y and a.x < b.x)))
		_ring_at = -1
	if _ring.is_empty():
		return
	if _ring_at < 0:
		var here: Vector2 = st.position(run)
		var best: float = INF
		for i: int in _ring.size():
			var d: float = (Vector2(_ring[i]) + Vector2(0.5, 0.5)).distance_to(here)
			if d < best:
				best = d
				_ring_at = i
		head_for(run, st, _ring[_ring_at])
		return
	if follower.status == NavFollower.Status.ARRIVED or follower.status == NavFollower.Status.BLOCKED:
		_ring_at = (_ring_at + 3) % _ring.size()
		head_for(run, st, _ring[_ring_at])


func _plan(run: RunState, st: StytheCreature) -> void:
	_last_plan = run.tick
	follower.go(run, st.system.nav, st, goal, NavModes.Mode.DARK, params(st))
