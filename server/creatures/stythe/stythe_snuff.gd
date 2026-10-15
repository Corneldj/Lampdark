class_name StytheSnuff
extends RefCounted
## CRT-13 (Gameplay §7.4): in its active states (Hunt, WindUp, Drag, Collect: those that play its
## tell) the Stythe snuffs the nearest flame within stythe.snuff_reach_tiles in its line of sight,
## shuttered or not, candles and dropped lamps included, every CreatureTables.stythe_snuff_interval_s
## (2.0 s; 1.6 s at crew count 3 or more and always in its territory). Through FlameSnuff, which
## refuses anything beyond it (flares); emergency lamps, egg-glow and gob fires are no flames. An
## electric lamp (MNR-08's "electric_lamp" source) loses stythe.electric_snuff_drain_s of battery
## instead, through `electric_drain`. Never while pushed off light, lurking, circling or shadowing.
## Each snuff is logged for the Inquiry. Server-only.

const ELECTRIC_KIND: String = "electric_lamp"

## The tick the next snuff is due (-1: not timing, outside the active states).
var next_due: int = -1
## Every snuff: {tick, source, kind, owner, done}.
var history: Array[Dictionary] = []


## One tick: due in an active state, and not pushed off light.
func tick(run: RunState, st: StytheCreature, active: bool) -> void:
	if not active:
		next_due = -1
		return
	var interval: int = interval_ticks(run, st)
	if next_due < 0:
		next_due = run.tick + interval
		return
	if run.tick < next_due:
		return
	next_due = run.tick + interval
	if not st.pushed:
		snuff_nearest(run, st)


func interval_ticks(run: RunState, st: StytheCreature) -> int:
	var crew: int = run.crew.count if run.crew != null else 1
	var s: float = CreatureTables.stythe_snuff_interval_s(crew, st.senses.in_territory(run, st, st.tile(run)))
	return maxi(1, roundi(s * Tuning.f(&"net.tick_hz")))


## Snuffs (or drains) the nearest target in reach and sight; its source, or 0 if none.
func snuff_nearest(run: RunState, st: StytheCreature) -> int:
	var target: Dictionary = nearest(run, st)
	if target.is_empty():
		return 0
	var source: int = int(Variants.number(target["source"]))
	var done: bool
	if str(target["kind"]) == ELECTRIC_KIND:
		done = Variants.flag(st.electric_drain.call(run, source, Tuning.f(&"stythe.electric_snuff_drain_s")))
	else:
		done = FlameSnuff.snuff(run, source, "stythe")
	var row: Dictionary = {"tick": run.tick, "source": source, "kind": target["kind"], "owner": target["owner"], "done": done}
	history.append(row)
	if st.system != null:
		st.system.log.add(run.tick, &"stythe_snuff", {"creature": st.kind_name(), "source": source, "kind": target["kind"],
			"owner": target["owner"], "done": done})
	return source


## The nearest flame or electric lamp within reach and line of sight: {source, kind, owner}.
func nearest(run: RunState, st: StytheCreature) -> Dictionary:
	if run.light == null:
		return {}
	var at: Vector2 = st.position(run)
	var reach: float = Tuning.f(&"stythe.snuff_reach_tiles")
	var rect: Rect2 = Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	var ids: Array = Array(run.light.grid.flame_sources(rect))
	for id: int in _electric_ids(run, rect):
		ids.append(id)
	ids.sort()
	var best: Dictionary = {}
	var best_d: float = INF
	for raw: Variant in ids:
		var id: int = int(Variants.number(raw))
		var info: Dictionary = run.light.grid.source_info(id)
		if info.is_empty():
			continue
		var kind: String = str(info.get("kind", ""))
		var flags: int = int(Variants.number(info.get("flags", 0)))
		if kind != ELECTRIC_KIND and ((flags & LbLightGrid.FLAG_FLAME) == 0 or (flags & LbLightGrid.FLAG_BEYOND_SNUFF) != 0):
			continue
		var p: Vector2 = info.get("position", Vector2.ZERO)
		var d: float = p.distance_to(at)
		if d > reach + 1e-9 or d >= best_d - 1e-9:
			continue
		if not MothSleep.line_of_sight(run, at, p):
			continue
		best_d = d
		best = {"source": id, "kind": kind, "owner": int(Variants.number(info.get("owner", 0)))}
	return best


## MNR-08's electric lamps among every source (none until that ticket lands).
func _electric_ids(run: RunState, rect: Rect2) -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in electric_sources.call(run):
		var id: int = int(Variants.number(raw))
		var info: Dictionary = run.light.grid.source_info(id)
		var p: Vector2 = info.get("position", Vector2(INF, INF))
		if rect.grow(0.01).has_point(p):
			out.append(id)
	return out


## MNR-08: (run) -> Array of electric lamp source ids (switched on).
var electric_sources: Callable = func(_r: RunState) -> Array: return []
