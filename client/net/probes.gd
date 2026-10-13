class_name ClientProbes
extends RefCounted
## NET-12's client probes, measured from the client's side alone (bots and human sessions alike):
##   light-to-contents: a tile entering the predicted own light (VIS-02's falloff to 0.12, inside
##     the predicted cone, no held wall between: MarginReveal's rule) starts a sample; it ends when
##     an entity token stands on that tile (drawn: a hidden margin token is revealed by that same
##     light), at 0 if one already does. Tiles nothing stands on within WINDOW never resolve and
##     are not counted (only tiles with contents count).
##   about-turn: a turn of net.probe_about_turn_deg or more within the time the capped turn rate
##     needs for it plus 100 ms (movement.turn_rate_deg_s; 100 ms alone at no cap). Samples it
##     starts, until it ends, are tagged "turn"; it also counts the frames until the held geometry
##     of the tiles it lit is drawn (1: the next frame).
##   bandwidth: bytes down and up per lane (voice is its own lane), from the connection.
## Each frame costs well under 0.1 ms (`cost_usec`). Release builds keep only the summaries
## (`keep_samples` false): no tile or token is kept.

const TURN_SLACK_USEC: int = 100000
const WINDOW_USEC: int = 1000000
const SEEN_MILLI: int = 120

var keep_samples: bool = true
## {kind: "light" | "turn", ms, at_usec}
var samples: Array[Dictionary] = []
## Frames from each about-turn until its lit tiles' held geometry drew (1 = the next frame).
var turn_held_frames: Array[int] = []
var turns: int = 0
var unresolved: int = 0
var frames: int = 0
var cost_usec: int = 0
var cone_deg: float = 110.0
var turn_deg: float = 90.0
## How long an about-turn may take to count (from the turn rate), microseconds.
var turn_window_usec: int = TURN_SLACK_USEC
var core_fraction: float = 0.6
var core_value: float = 0.3
var edge_value: float = 0.12

var _lit: Dictionary = {}
## tile -> [start_usec, kind]
var _pending: Dictionary = {}
## [usec, facing] for the last 100 ms
var _facings: Array[Array] = []
var _last_turn_usec: int = -1000000000
## The current about-turn: {frame, tiles: {tile: first frame with geometry or -1}}
var _turn: Dictionary = {}
var _light_ms: Array[float] = []
var _turn_ms: Array[float] = []


func _init() -> void:
	if Tuning.current.has_key(&"vision.cone_deg"):
		cone_deg = Tuning.f(&"vision.cone_deg")
		core_fraction = Tuning.f(&"light.core_fraction")
		core_value = Tuning.f(&"light.core_value")
		edge_value = Tuning.f(&"light.edge_value")
	if Tuning.current.has_key(&"net.probe_about_turn_deg"):
		turn_deg = Tuning.f(&"net.probe_about_turn_deg")
	var rate: float = Tuning.f(&"movement.turn_rate_deg_s") if Tuning.current.has_key(&"movement.turn_rate_deg_s") else 0.0
	if rate > 0.0:
		turn_window_usec = roundi(turn_deg / rate * 1000000.0) + TURN_SLACK_USEC


## One client frame: the view as held now, the predicted own lamp ({position, radius}) and the
## predicted facing (u16).
func on_frame(now_usec: int, view: ReceivedView, lamp: Dictionary, facing: int) -> void:
	var t0: int = Time.get_ticks_usec()
	frames += 1
	var turned: bool = _note_facing(now_usec, facing)
	var lit: Dictionary = _predicted_lit(view, lamp, facing)
	var occupied: Dictionary = {}
	for raw: Variant in view.entities.values():
		var e: Dictionary = raw
		var p: Vector2 = e["position"]
		occupied[Vector2i(floori(p.x), floori(p.y))] = true
	var kind: String = "turn" if now_usec - _last_turn_usec <= turn_window_usec else "light"
	for raw: Variant in lit.keys():
		var tile: Vector2i = raw
		if _lit.has(tile):
			continue
		if occupied.has(tile):
			_sample(kind, 0.0, now_usec)
		else:
			_pending[tile] = [now_usec, kind]
	for raw: Variant in _pending.keys():
		var tile: Vector2i = raw
		var item: Array = _pending[tile]
		var start: int = item[0]
		if occupied.has(tile) and lit.has(tile):
			_sample(str(item[1]), (now_usec - start) / 1000.0, now_usec)
			_pending.erase(tile)
		elif not lit.has(tile) or now_usec - start > WINDOW_USEC:
			_pending.erase(tile)
			unresolved += 1
	if turned:
		turns += 1
		var tiles: Dictionary = {}
		for raw: Variant in lit.keys():
			if not _lit.has(raw):
				tiles[raw] = -1
		_turn = {"frame": frames, "tiles": tiles, "usec": now_usec}
	_follow_turn(view, now_usec)
	_lit = lit
	cost_usec += Time.get_ticks_usec() - t0


func _note_facing(now_usec: int, facing: int) -> bool:
	_facings.append([now_usec, facing])
	while _facings.size() > 1 and now_usec - int(Variants.number(_facings[0][0])) > turn_window_usec:
		_facings.pop_front()
	if now_usec - _last_turn_usec <= turn_window_usec:
		return false
	var oldest: int = _facings[0][1]
	var d: int = absi(((facing - oldest + 32768) & 0xFFFF) - 32768)
	if d * 360.0 / 65536.0 >= turn_deg:
		_last_turn_usec = now_usec
		return true
	return false


## The tiles the predicted own lamp lights to 0.12 inside the predicted cone, past no held wall.
func _predicted_lit(view: ReceivedView, lamp: Dictionary, facing: int) -> Dictionary:
	var out: Dictionary = {}
	var radius: float = float(Variants.number(lamp.get("radius", 0.0)))
	if radius <= 0.0:
		return out
	var at: Vector2 = lamp["position"]
	var f: PackedFloat64Array = LbDetMath.unit(float(facing) / 65536.0)
	var cos_half: float = LbDetMath.cos_deg(cone_deg * 0.5)
	var r: int = ceili(radius)
	var centre: Vector2i = Vector2i(floori(at.x), floori(at.y))
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var tile: Vector2i = centre + Vector2i(dx, dy)
			var p: Vector2 = Vector2(tile) + Vector2(0.5, 0.5)
			if LbLightMath.falloff_milli(at.distance_to(p), radius, 1.0, core_fraction, core_value, edge_value) < SEEN_MILLI:
				continue
			var v: Vector2 = p - at
			var dot: float = v.x * f[0] + v.y * f[1]
			if v.length() > 0.5 and (dot < 0.0 or dot * dot < cos_half * cos_half * v.length_squared()):
				continue
			if MarginReveal._shadowed(view.geometry, at, p):
				continue
			out[tile] = true
	return out


func _follow_turn(view: ReceivedView, now_usec: int) -> void:
	if _turn.is_empty():
		return
	var tiles: Dictionary = _turn["tiles"]
	var since: int = frames - int(Variants.number(_turn["frame"]))
	var done: bool = true
	var worst: int = 0
	for raw: Variant in tiles.keys():
		var first: int = tiles[raw]
		if first < 0 and view.geometry.has(raw):
			first = maxi(1, since)
			tiles[raw] = first
		if first < 0:
			done = false
		else:
			worst = maxi(worst, first)
	if done or now_usec - int(Variants.number(_turn["usec"])) > WINDOW_USEC:
		if worst > 0:
			turn_held_frames.append(worst)
		_turn = {}


func _sample(kind: String, ms: float, at_usec: int) -> void:
	if kind == "turn":
		_turn_ms.append(ms)
	else:
		_light_ms.append(ms)
	if keep_samples:
		samples.append({"kind": kind, "ms": ms, "at_usec": at_usec})


## {light: {n, p50, p95, max}, turn: {...}, turn_held_frames_max, unresolved, turns, frames,
## cost_usec_per_frame}
func summary() -> Dictionary:
	var held_max: int = 0
	for f: int in turn_held_frames:
		held_max = maxi(held_max, f)
	return {"light": ProbeMath.stats(_light_ms), "turn": ProbeMath.stats(_turn_ms), "turn_held_frames_max": held_max,
		"unresolved": unresolved, "turns": turns, "frames": frames, "cost_usec_per_frame": cost_usec / maxf(1.0, frames)}
