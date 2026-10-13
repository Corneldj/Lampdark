class_name Rewind
extends SimSystem
## NET-06's lag compensation: a short history of every body's position, so an interaction is
## range-checked against where the presser saw its target, and a shot traced against bodies as
## the shooter saw them. For an input processed at tick T with stamp S (NET-03's shown tick) the
## rewind is min(T - S, net.rewind_max_ms). Only other bodies move back: the actor, every state
## and the geometry are current. Creature perception, pacing and illusions never read this
## (tools/build/check_module_deps.sh).

## The kinds that are bodies for a trace: miners (Hands and the fallen are miners), Bess and the
## creatures. CRT-01 narrows the Tapper to its arm out of the rock through radius_of.
const BODY_KINDS: Array[WorldIds.EntityKind] = [WorldIds.EntityKind.MINER, WorldIds.EntityKind.BESS,
	WorldIds.EntityKind.MOTH, WorldIds.EntityKind.TAPPER, WorldIds.EntityKind.TAPPER_ARM, WorldIds.EntityKind.STYTHE]

var depth: int = 10
var max_ticks: float = 3.0
var body_radius: float = 0.35
## CRT-01's body shapes: (entity: SimEntity) -> radius in tiles, 0 or less for no body now.
var radius_of: Callable = Callable()
## tick -> {entity id: Vector2}: positions at the end of that tick, as its frame showed them.
var history: Dictionary = {}
var _run: RunState = null


func _init() -> void:
	if Tuning.current.has_key(&"net.rewind_history_ticks"):
		depth = Tuning.i(&"net.rewind_history_ticks")
		max_ticks = Tuning.f(&"net.rewind_max_ms") / (1000.0 / Tuning.f(&"net.tick_hz"))
		body_radius = Tuning.f(&"movement.body_radius")


func stage() -> int:
	return StageTable.Stage.RECORD


func order() -> int:
	return 20


func system_name() -> String:
	return "Rewind"


func bind(run: RunState) -> void:
	_run = run


func tick(run: RunState) -> void:
	_run = run
	var now: Dictionary = {}
	for id: int in run.registry.ids():
		now[id] = run.registry.get_entity(id).position
	history[run.tick] = now
	for key: Variant in history.keys():
		if int(Variants.number(key)) <= run.tick - depth:
			history.erase(key)


## The time (in ticks) an input stamped `stamp` is judged at during this tick.
func rewind_time(stamp: float) -> float:
	var now: float = float(_now())
	return clampf(stamp, now - max_ticks, now)


## Every recorded body's position at `time` (ticks, with a fraction), interpolated between the
## frames either side; the current tick's live positions stand for "now".
func positions_at(time: float) -> Dictionary:
	var out: Dictionary = {}
	for id: int in _run.registry.ids():
		out[id] = position_of(id, time)
	return out


func position_of(id: int, time: float) -> Vector2:
	var live: Vector2 = _run.registry.get_entity(id).position if _run.registry.has(id) else Vector2.ZERO
	var now: int = _now()
	if time >= now:
		return live
	var k: int = floori(time)
	var oldest: int = now - depth
	if k < oldest:
		k = oldest
		time = float(k)
	var a: Vector2 = _at(id, k, live)
	var b: Vector2 = live if k + 1 >= now else _at(id, k + 1, live)
	return a.lerp(b, time - k)


## MNR-04, MNR-05, LFT-02 and the other interactions: the actor where it is now, the target
## where the actor's client showed it (stamp), centre to centre.
func in_range_at(actor: int, target: int, range_tiles: float, stamp: float) -> bool:
	var from: Vector2 = position_of(actor, float(_now()))
	var to: Vector2 = position_of(target, rewind_time(stamp))
	return from.distance_squared_to(to) <= range_tiles * range_tiles


## MNR-16's shot: from `origin` along unit `dir`, at most `max_tiles`, against bodies rewound to
## the shooter's stamp and the current rock, closed air doors and shut gates. Returns the first
## thing on the line: {"entity": id, "distance", "point"}, {"wall": tile, "distance", "point"},
## or {} when nothing is in range. Seen or not makes no difference.
func trace_bodies(origin: Vector2, dir: Vector2, max_tiles: float, stamp: float, exclude: int = 0) -> Dictionary:
	var wall: Dictionary = _first_wall(origin, dir, max_tiles)
	var limit: float = Variants.number(wall.get("distance", max_tiles))
	var time: float = rewind_time(stamp)
	var best: Dictionary = {}
	var ids: Array = Array(_run.registry.ids())
	ids.sort()
	for raw: Variant in ids:
		var id: int = int(Variants.number(raw))
		if id == exclude:
			continue
		var e: SimEntity = _run.registry.get_entity(id)
		if not BODY_KINDS.has(e.kind):
			continue
		var r: float = Variants.number(radius_of.call(e)) if radius_of.is_valid() else body_radius
		if r <= 0.0:
			continue
		var t: float = _ray_circle(origin, dir, position_of(id, time), r)
		if t >= 0.0 and t <= limit and (best.is_empty() or t < Variants.number(best["distance"])):
			best = {"entity": id, "distance": t, "point": origin + dir * t}
	if not best.is_empty():
		return best
	return wall


func write_state(writer: SimStateWriter) -> void:
	var ticks: Array = history.keys()
	ticks.sort()
	writer.put_i64(ticks.size())
	for raw: Variant in ticks:
		writer.put_i64(int(Variants.number(raw)))
		var at: Dictionary = history[raw]
		var ids: Array = at.keys()
		ids.sort()
		writer.put_i64(ids.size())
		for id: Variant in ids:
			var p: Vector2 = at[id]
			writer.put_i64(int(Variants.number(id)))
			writer.put_f64(p.x)
			writer.put_f64(p.y)


func read_state(reader: SimStateReader) -> void:
	history.clear()
	for _i: int in reader.get_i64():
		var t: int = reader.get_i64()
		var at: Dictionary = {}
		for _j: int in reader.get_i64():
			var id: int = reader.get_i64()
			var x: float = reader.get_f64()
			at[id] = Vector2(x, reader.get_f64())
		history[t] = at


func _now() -> int:
	return _run.tick if _run != null else 0


func _at(id: int, tick_at: int, fallback: Vector2) -> Vector2:
	var at: Dictionary = Variants.dict(history.get(tick_at, {}))
	return at[id] if at.has(id) else fallback


## Distance along the ray to the circle, or -1. A ray starting inside it hits at 0.
static func _ray_circle(origin: Vector2, dir: Vector2, centre: Vector2, r: float) -> float:
	var oc: Vector2 = centre - origin
	var along: float = oc.dot(dir)
	var off2: float = oc.length_squared() - along * along
	if off2 > r * r:
		return -1.0
	var half: float = sqrt(r * r - off2)
	if along + half < 0.0:
		return -1.0
	return maxf(along - half, 0.0)


## The first tile that blocks a shot (not walkable: rock, a closed air door, a shut gate) along
## the ray within max_tiles, walked tile by tile; the tile the shot starts in never blocks.
func _first_wall(origin: Vector2, dir: Vector2, max_tiles: float) -> Dictionary:
	if _run == null or _run.mine == null:
		return {}
	var tile: Vector2i = Vector2i(floori(origin.x), floori(origin.y))
	var step: Vector2i = Vector2i(1 if dir.x > 0.0 else -1, 1 if dir.y > 0.0 else -1)
	var inf: float = 1e30
	var next_x: float = ((tile.x + (1 if dir.x > 0.0 else 0)) - origin.x) / dir.x if dir.x != 0.0 else inf
	var next_y: float = ((tile.y + (1 if dir.y > 0.0 else 0)) - origin.y) / dir.y if dir.y != 0.0 else inf
	var delta_x: float = absf(1.0 / dir.x) if dir.x != 0.0 else inf
	var delta_y: float = absf(1.0 / dir.y) if dir.y != 0.0 else inf
	while true:
		var t: float
		if next_x < next_y:
			t = next_x
			tile.x += step.x
			next_x += delta_x
		else:
			t = next_y
			tile.y += step.y
			next_y += delta_y
		if t > max_tiles:
			return {}
		if not _run.mine.native.is_walkable(tile):
			return {"wall": tile, "distance": t, "point": origin + dir * t}
	return {}
