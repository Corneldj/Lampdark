class_name MothAwake
extends RefCounted
## CRT-04: the awake Moth (Gameplay §7.2): Frenzy, Prowl, Hunt, WindUp, Smother, Linger, LastSpot
## and Search. It sees light and nothing else (MothPerception, rescanned at moth.rescan_hz, the
## target checked every tick), hunts the brightest cluster, remembers recent lights (MothMemory)
## and smothers whoever carries the light it reaches after a moth.windup_s wind-up that a douse or
## a step into the dark defeats (CRT-01's wind-up, NET-06's defender rule). Its awake tell plays in
## every awake state. M1 stub until CRT-05: a smothered gauze lamp lies snuffed where it fell and
## the Moth lingers; laying is CRT-06's. Everything here is server-only and never sent.

## The states that hold a hunt (and fill a place under the cap).
const HUNTING: Array[StringName] = [&"hunt", &"windup", &"smother", &"linger", &"last_spot", &"search"]

var perception: MothPerception = MothPerception.new()
var memory: MothMemory = MothMemory.new()
var follower: NavFollower = NavFollower.new()
## Frenzy time left, in ticks: set at waking from the ring, drained only in Frenzy with no target.
var frenzy_left: int = 0
## What it hunts: {kind (&"carried", &"lit_miner", &"unheld", &"cover", &"waker"), miner, source,
## point, score, cannot_take}. Empty when it hunts nothing.
var target: Dictionary = {}
var last_spot: Vector2 = Vector2.ZERO
var until: int = -1
var waiting: bool = false
var search_points: Array[Vector2] = []
var search_min_until: int = -1
## The tick it last hunted, or entered Prowl (moth.prowl_without_hunt_s runs from it).
var prowl_since: int = 0
var heading_home: bool = false
## The source it covers in Linger, marked searched when the Linger ends (0: none).
var covering: int = 0
var awake_tell: Tell = null
var thrum: Tell = null
var _goal: Vector2i = Vector2i(2147483647, 0)
var _goal_mode: NavModes.Mode = NavModes.Mode.WALKER


## Called on every wake into Frenzy or Prowl (CRT-03's _wake_up and _rise).
func begin(run: RunState, m: Moth, frenzy: bool) -> void:
	frenzy_left = roundi(CreatureTables.moth_frenzy_s(m.ring(run)) * Tuning.f(&"net.tick_hz")) if frenzy else 0
	prowl_since = run.tick
	heading_home = false
	target = {}
	perception.scanned_tick = -1
	if awake_tell == null or not awake_tell.is_playing():
		awake_tell = m.system.begin_tell(run, m, &"moth_awake", Tuning.f(&"moth.tell_reach_tiles"))


## Asleep again (or retreating deep): the awake tell stops.
func end(run: RunState, m: Moth) -> void:
	if awake_tell != null and awake_tell.is_playing():
		m.system.end_tell(run, awake_tell)
	if thrum != null and thrum.is_playing():
		m.system.end_tell(run, thrum)
	follower.stop()
	target = {}


func tell_active() -> bool:
	return awake_tell != null and awake_tell.is_playing()


func tick(run: RunState, m: Moth) -> void:
	memory.prune(run.tick)
	var every: int = maxi(1, roundi(Tuning.f(&"net.tick_hz") / Tuning.f(&"moth.rescan_hz")))
	if perception.scanned_tick < 0 or run.tick - perception.scanned_tick >= every:
		_scan(run, m)
	var name: StringName = m.state.name
	# A chosen hunt the relax ended (HuntGate stands it down): back to Prowl.
	if HUNTING.has(name) and name != &"windup" and not m.system.gate.is_hunting(m):
		_to_prowl(run, m, "hunt ended")
		return
	match name:
		&"frenzy":
			_frenzy(run, m)
		&"prowl":
			_prowl(run, m)
		&"hunt":
			_hunt(run, m)
		&"linger":
			if run.tick >= until:
				if covering != 0:
					perception.mark_searched(covering, run.tick)
					covering = 0
				_to_search(run, m)
		&"last_spot":
			_wait_at(run, m, last_spot, Tuning.f(&"moth.last_spot_s"))
			if waiting and run.tick >= until:
				_to_search(run, m)
		&"search":
			_search(run, m)


func _scan(run: RunState, m: Moth) -> void:
	perception.scan(run, m.tile(run), CreatureTables.moth_sight_tiles(m.ring(run)))
	var capacity: int = CreatureTables.moth_memory_lights(int(Variants.number(m.system.gate.crew_count.call())))
	for c: MothPerception.Cluster in perception.clusters:
		memory.remember(c.centroid, c.score, run.tick, capacity)


## The best target now: the brightest cluster (in a frenzy, a lit miner standing in it), or in a
## frenzy the waker while it is still known. Outside a frenzy it never targets a miner.
func best_target(run: RunState, m: Moth, frenzy: bool) -> Dictionary:
	var c: MothPerception.Cluster = perception.brightest()
	if c != null:
		# In the brightest cluster: the nearest carrier of a light first; in a frenzy a lit miner;
		# then the nearest unheld light it can take; else it covers a light it cannot take.
		var here: Vector2 = m.position(run)
		var t: Dictionary = {"source": c.source, "score": c.score, "cannot_take": c.cannot_take(), "miner": 0,
			"point": c.source_position, "centroid": c.centroid}
		var carrier: Array = _nearest_carrier(run, c, here)
		var unheld: int = _nearest_unheld(c, here)
		if not carrier.is_empty():
			t["kind"] = &"carried"
			t["miner"] = carrier[0]
			t["source"] = carrier[1]
			t["cannot_take"] = MothPerception.cannot_take_info(Variants.dict(c.sources[carrier[1]]))
		elif frenzy and _lit_miner_in(run, m, c) != 0:
			t["kind"] = &"lit_miner"
			t["miner"] = _lit_miner_in(run, m, c)
		elif unheld != 0:
			t["kind"] = &"unheld"
			t["source"] = unheld
			t["cannot_take"] = false
			t["point"] = Variants.dict(c.sources[unheld]).get("position", c.source_position)
		else:
			t["kind"] = &"cover"
			t["point"] = _nearest_tile_centre(c, here)
		return t
	if frenzy and not m.waker.is_empty() and run.tick < int(Variants.number(m.waker.get("until", 0))):
		var owner: int = int(Variants.number(m.waker.get("owner", 0)))
		var at: Vector2 = m.waker.get("position", m.position(run))
		return {"kind": &"waker", "miner": owner, "source": 0, "score": 0.0, "cannot_take": false, "point": at, "centroid": at}
	return {}


func _frenzy(run: RunState, m: Moth) -> void:
	var t: Dictionary = best_target(run, m, true)
	if not t.is_empty() and m.system.gate.request_commit(run, m, int(Variants.number(t["miner"])), false):
		_to_hunt(run, m, t, "frenzy")
		return
	frenzy_left -= 1
	_wander(run, m)
	if frenzy_left <= 0:
		_to_prowl(run, m, "frenzy spent")


func _prowl(run: RunState, m: Moth) -> void:
	var gate: HuntGate = m.system.gate
	var relaxed: bool = Variants.flag(gate.relax_active.call()) and not Variants.flag(gate.apex_on.call())
	if not relaxed and not heading_home:
		var t: Dictionary = best_target(run, m, false)
		if not t.is_empty() and gate.request_commit(run, m, int(Variants.number(t["miner"])), true):
			_to_hunt(run, m, t, "prowl")
			return
	var speed: float = Tuning.f(&"moth.prowl_speed")
	if m.rose_for != "engine" and (heading_home or run.tick - prowl_since >= roundi(Tuning.f(&"moth.prowl_without_hunt_s") * Tuning.f(&"net.tick_hz"))):
		heading_home = true
		_go(run, m, m.roost, NavModes.Mode.CRAWLER)
		if m.tile(run) == m.roost or follower.tick(run, m.system.nav, m, speed) == NavFollower.Status.ARRIVED \
				or follower.status == NavFollower.Status.BLOCKED:
			end(run, m)
			m.begin_preen(run)
		return
	if relaxed:
		_go(run, m, m.roost, NavModes.Mode.CRAWLER)
	elif m.rose_for == "engine":
		_go(run, m, _base_camp(run), NavModes.Mode.CRAWLER)
	else:
		var marked: int = _marked_miner(run, m)
		if marked != 0:
			_go(run, m, run.registry.get_entity(marked).tile(), NavModes.Mode.CRAWLER)
		else:
			_wander(run, m)
			return
	follower.tick(run, m.system.nav, m, speed)


func _hunt(run: RunState, m: Moth) -> void:
	if not _target_holds(run, m):
		_to_last_spot(run, m, "target dark or unseen")
		return
	if perception.scanned_tick == run.tick:
		var better: Dictionary = best_target(run, m, frenzy_left > 0)
		if not better.is_empty() and float(Variants.number(better["score"])) > float(Variants.number(target["score"])) + 1e-9 \
				and int(Variants.number(better["source"])) != int(Variants.number(target["source"])):
			_retarget(run, m, better)
	var point: Vector2 = _target_point(run)
	last_spot = point
	var d: float = m.position(run).distance_to(point)
	var kind: StringName = target["kind"]
	if kind == &"cover":
		if d <= Tuning.f(&"moth.reach_tiles") or perception.cluster_at(m.tile(run)) != null:
			_to_cover(run, m)
			return
	elif d <= Tuning.f(&"moth.reach_tiles") and kind != &"waker":
		_begin_wind_up(run, m)
		return
	elif kind == &"waker" and d <= Tuning.f(&"moth.reach_tiles"):
		_to_last_spot(run, m, "the waker is not there")
		return
	_go(run, m, Vector2i(floori(point.x), floori(point.y)), NavModes.Mode.WALKER)
	follower.tick(run, m.system.nav, m, Tuning.f(&"moth.hunt_speed"))


## The target is still there to hunt: a carried light still open on its carrier and in sight, a lit
## miner still lit, an unheld light still burning, a light it covers still seen, a waker still known.
func _target_holds(run: RunState, m: Moth) -> bool:
	var miner: int = int(Variants.number(target.get("miner", 0)))
	var source: int = int(Variants.number(target.get("source", 0)))
	match target.get("kind", &""):
		&"carried":
			if run.light == null or not run.light.grid.has_source(source):
				return false
			if run.light.grid.owned_radius(miner) <= 0.0:
				return false
			return perception.scanned_tick != run.tick or _seen_near(run.registry.get_entity(miner).tile())
		&"lit_miner":
			var e: SimEntity = run.registry.get_entity(miner)
			return e != null and run.light.light_at(e.tile()) >= Tuning.f(&"moth.see_level") \
				and (perception.scanned_tick != run.tick or perception.lit_miners.has(miner))
		&"unheld":
			if not run.light.grid.has_source(source):
				return false
			var p: Vector2 = target["point"]
			return run.light.light_at(Vector2i(floori(p.x), floori(p.y))) >= Tuning.f(&"moth.see_level")
		&"cover":
			return perception.scanned_tick != run.tick or _seen_source(source)
		&"waker":
			return run.tick < int(Variants.number(m.waker.get("until", 0))) or not perception.clusters.is_empty()
	return false


func _seen_near(tile: Vector2i) -> bool:
	return perception.seen.has(tile)


func _seen_source(source: int) -> bool:
	return perception.cluster_with_source(source) != null


## The carrier nearest `from` among a cluster's carried lights: [miner, source], or [].
func _nearest_carrier(run: RunState, c: MothPerception.Cluster, from: Vector2) -> Array:
	var best: Array = []
	var best_d: float = INF
	for pair: Array in c.carriers():
		var who: int = pair[0]
		if not run.registry.has(who):
			continue
		var d: float = run.registry.get_entity(who).position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = pair
	return best


func _nearest_unheld(c: MothPerception.Cluster, from: Vector2) -> int:
	var best: int = 0
	var best_d: float = INF
	for id: int in c.unheld_sources():
		var p: Vector2 = Variants.dict(c.sources[id]).get("position", c.source_position)
		var d: float = p.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = id
	return best


func _target_point(run: RunState) -> Vector2:
	var miner: int = int(Variants.number(target.get("miner", 0)))
	var kind: StringName = target["kind"]
	if (kind == &"carried" or kind == &"lit_miner" or kind == &"waker") and miner != 0 and run.registry.has(miner):
		return run.registry.get_entity(miner).position
	return target["point"]


func _retarget(run: RunState, m: Moth, t: Dictionary) -> void:
	var gate: HuntGate = m.system.gate
	var miner: int = int(Variants.number(t["miner"]))
	if gate.target_of(m) != miner:
		var chosen: bool = frenzy_left <= 0
		var old: int = gate.target_of(m)
		gate.stand_down(run, m, "retarget")
		if not gate.request_commit(run, m, miner, chosen):
			gate.request_commit(run, m, old, false)
			return
	target = t
	m.system.log.add(run.tick, &"moth_target", {"kind": t["kind"], "source": t["source"], "score": t["score"]})


func _to_hunt(run: RunState, m: Moth, t: Dictionary, why: String) -> void:
	target = t
	prowl_since = run.tick
	heading_home = false
	m.enter(run, &"hunt", why)
	m.system.log.add(run.tick, &"moth_target", {"kind": t["kind"], "source": t["source"], "score": t["score"]})


func _begin_wind_up(run: RunState, m: Moth) -> void:
	follower.stop()
	var kind: StringName = target["kind"]
	var miner: int = int(Variants.number(target.get("miner", 0)))
	var source: int = int(Variants.number(target.get("source", 0)))
	var point: Vector2 = target["point"]
	var reach: float = Tuning.f(&"moth.reach_tiles")
	var see: float = Tuning.f(&"moth.see_level")
	var slot: int = _slot_of(run, miner)
	var condition: Callable
	if kind == &"unheld":
		condition = func(r: RunState) -> bool: return r.registry.has(m.entity_id) and m.position(r).distance_to(point) <= reach + 0.5
	else:
		condition = func(r: RunState) -> bool:
			return r.registry.has(miner) and m.position(r).distance_to(r.registry.get_entity(miner).position) <= reach
	m.enter(run, &"windup", str(kind))
	var w: CreatureWindUp = m.system.begin_wind_up(run, m, slot if kind != &"unheld" else -1, miner if kind != &"unheld" else 0,
		Tuning.f(&"moth.windup_s"), condition)
	if kind == &"unheld":
		w.at_end = func(r: RunState) -> bool:
			return r.light.grid.has_source(source) and r.light.light_at(Vector2i(floori(point.x), floori(point.y))) >= see
	else:
		var frenzy: bool = frenzy_left > 0
		w.lit = func(r: RunState, own_shutter_issued: bool) -> bool:
			return _lit_on(r, miner, kind, frenzy, own_shutter_issued)
	thrum = m.system.begin_tell(run, m, &"moth_thrum", Tuning.f(&"moth.tell_reach_tiles"), Tell.Form.CREATURE_PLACED)


## Some light still on the target at the wind-up's end. A carried light: their own lamp open (dark
## once its shutter was issued, NET-06) or, in a frenzy, standing in 0.30 of anyone's light.
func _lit_on(run: RunState, miner: int, kind: StringName, frenzy: bool, own_shutter_issued: bool) -> bool:
	if not run.registry.has(miner):
		return false
	var tile: Vector2i = run.registry.get_entity(miner).tile()
	var own: int = run.light.grid.value_from(tile, PackedInt64Array([miner]))
	var total: int = run.light.grid.value(tile)
	var others: int = total - own
	var see_milli: int = roundi(Tuning.f(&"moth.see_level") * 1000.0)
	if kind == &"carried":
		var own_open: bool = not own_shutter_issued and run.light.grid.owned_radius(miner) > 0.0
		return own_open or (frenzy and others >= see_milli)
	return (total if not own_shutter_issued else others) >= see_milli


func on_wind_up_finished(run: RunState, m: Moth, w: CreatureWindUp) -> void:
	if thrum != null and thrum.is_playing():
		m.system.end_tell(run, thrum)
	match w.outcome:
		CreatureWindUp.Outcome.LANDED:
			_smother(run, m)
		CreatureWindUp.Outcome.MISSED:
			_to_last_spot(run, m, "missed: %s" % w.reason)
		_:
			_to_prowl(run, m, "wind-up cancelled")


## The smother (§7.2): the carrier falls and their flame goes out (an electric lamp burns on); at an
## unheld light everyone in its core falls; a grabbed miner is beyond it, but a pinned miner's lamp
## is snuffed. Then it lingers (laying and homing are CRT-06's and CRT-05's).
func _smother(run: RunState, m: Moth) -> void:
	m.enter(run, &"smother", str(target["kind"]))
	var victims: Array[int] = []
	var kind: StringName = target["kind"]
	if kind == &"unheld":
		var source: int = int(Variants.number(target["source"]))
		var info: Dictionary = run.light.grid.source_info(source)
		var at: Vector2 = info.get("position", target["point"])
		var core: float = float(Variants.number(info.get("radius", 0.0))) * Tuning.f(&"light.core_fraction")
		var ids: Array = Array(run.registry.ids())
		ids.sort()
		for raw: Variant in ids:
			var e: SimEntity = run.registry.get_entity(int(Variants.number(raw)))
			if e.kind == WorldIds.EntityKind.MINER and e.position.distance_to(at) <= core and _can_fall(run, e.id):
				victims.append(e.id)
		var l: GauzeLamp = _lamp_with_source(run, source)
		if l != null and l.burning():
			run.lamps.snuff(run, l, "smother")
	else:
		var miner: int = int(Variants.number(target["miner"]))
		if run.holds != null and run.holds.grab_of(miner) != null:
			var held_lamp: GauzeLamp = run.lamps.lamp_in_hand(miner) if run.lamps != null else null
			if held_lamp != null and held_lamp.burning():
				run.lamps.snuff(run, held_lamp, "smother")
		elif _can_fall(run, miner):
			victims.append(miner)
	for v: int in victims:
		run.falls.fall_unconscious(run, v, FallCause.Cause.MOTH_SMOTHER, {"creature": m.entity_id})
	m.system.log.add(run.tick, &"moth_smother", {"kind": kind, "victims": victims, "source": target["source"]})
	covering = int(Variants.number(target["source"])) if Variants.flag(target.get("cannot_take", false)) else 0
	_to_linger(run, m)


func _can_fall(run: RunState, miner: int) -> bool:
	if run.miner_state == null or run.miner_state.miner(miner) == null:
		return false
	var life: int = run.miner_state.life(miner)
	return life == MinerTransitions.Life.UPRIGHT or life == MinerTransitions.Life.CAUGHT


func _to_cover(run: RunState, m: Moth) -> void:
	follower.stop()
	covering = int(Variants.number(target["source"]))
	m.system.log.add(run.tick, &"moth_cover", {"source": covering, "kind": target["kind"]})
	_to_linger(run, m)


func _to_linger(run: RunState, m: Moth) -> void:
	m.enter(run, &"linger", "over what it smothered" if covering == 0 else "covering")
	until = run.tick + roundi(Tuning.f(&"moth.linger_s") * Tuning.f(&"net.tick_hz"))


func _to_last_spot(run: RunState, m: Moth, why: String) -> void:
	follower.stop()
	waiting = false
	m.enter(run, &"last_spot", why)


func _to_search(run: RunState, m: Moth) -> void:
	search_points.clear()
	for l: MothMemory.Light in memory.nearest_first(m.position(run)):
		search_points.append(l.centroid)
	search_min_until = run.tick + roundi(CreatureTables.search_time_s(m.ring(run)) * Tuning.f(&"net.tick_hz"))
	waiting = false
	m.enter(run, &"search", "%d remembered lights" % search_points.size())


func _search(run: RunState, m: Moth) -> void:
	if perception.scanned_tick == run.tick:
		var t: Dictionary = best_target(run, m, frenzy_left > 0)
		if not t.is_empty():
			var miner: int = int(Variants.number(t["miner"]))
			var gate: HuntGate = m.system.gate
			if gate.target_of(m) == miner or _recommit(run, m, miner, frenzy_left <= 0):
				_to_hunt(run, m, t, "search saw light")
				return
	if not search_points.is_empty():
		_wait_at(run, m, search_points[0], Tuning.f(&"moth.search_per_light_s"))
		if waiting and run.tick >= until:
			search_points.pop_front()
			waiting = false
		return
	if run.tick < search_min_until:
		return
	if frenzy_left > 0:
		m.system.gate.stand_down(run, m, "search over")
		m.enter(run, &"frenzy", "frenzy time left")
	else:
		_to_prowl(run, m, "search over")


func _recommit(run: RunState, m: Moth, miner: int, chosen: bool) -> bool:
	var gate: HuntGate = m.system.gate
	var old: int = gate.target_of(m)
	gate.stand_down(run, m, "retarget")
	if gate.request_commit(run, m, miner, chosen):
		return true
	gate.request_commit(run, m, old, false)
	return false


## Goes to `point`, then waits `seconds` there (or where it is stuck).
func _wait_at(run: RunState, m: Moth, point: Vector2, seconds: float) -> void:
	if waiting:
		return
	_go(run, m, Vector2i(floori(point.x), floori(point.y)), NavModes.Mode.WALKER)
	var status: NavFollower.Status = follower.tick(run, m.system.nav, m, Tuning.f(&"moth.hunt_speed"))
	if m.position(run).distance_to(point) <= 0.75 or status == NavFollower.Status.ARRIVED or status == NavFollower.Status.BLOCKED:
		follower.stop()
		waiting = true
		until = run.tick + roundi(seconds * Tuning.f(&"net.tick_hz"))


func _to_prowl(run: RunState, m: Moth, why: String) -> void:
	m.system.gate.stand_down(run, m, why)
	follower.stop()
	target = {}
	prowl_since = run.tick
	m.enter(run, &"prowl", why)


func _go(run: RunState, m: Moth, to: Vector2i, how: NavModes.Mode) -> void:
	if to != _goal or how != _goal_mode or follower.status == NavFollower.Status.IDLE:
		_goal = to
		_goal_mode = how
		follower.go(run, m.system.nav, m, to, how)


## A seeded wander along the walls at prowl pace: a new walkable goal within 12 tiles on arrival.
func _wander(run: RunState, m: Moth) -> void:
	if follower.status == NavFollower.Status.IDLE or follower.status == NavFollower.Status.ARRIVED \
			or follower.status == NavFollower.Status.BLOCKED:
		var here: Vector2i = m.tile(run)
		for _try: int in 8:
			var t: Vector2i = here + Vector2i(m.rng.range(-12, 12), m.rng.range(-12, 12))
			if run.mine != null and run.mine.native.is_walkable(t, false) and t != here:
				_goal = t
				_goal_mode = NavModes.Mode.CRAWLER
				follower.go(run, m.system.nav, m, t, NavModes.Mode.CRAWLER)
				break
	follower.tick(run, m.system.nav, m, Tuning.f(&"moth.prowl_speed"))


## The highest-Pull marked miner within moth.marked_drift_tiles, or 0.
func _marked_miner(run: RunState, m: Moth) -> int:
	var best: int = 0
	var best_pull: int = -1
	var reach: float = Tuning.f(&"moth.marked_drift_tiles")
	var threshold: float = Tuning.f(&"pull.threshold_marked")
	var ids: Array = Array(run.registry.ids())
	ids.sort()
	for raw: Variant in ids:
		var e: SimEntity = run.registry.get_entity(int(Variants.number(raw)))
		if e.kind != WorldIds.EntityKind.MINER or e.position.distance_to(m.position(run)) > reach:
			continue
		var pull: int = int(Variants.number(m.system.gate.pull_of.call(e.id)))
		if pull >= threshold and pull > best_pull:
			best = e.id
			best_pull = pull
	return best


func _base_camp(run: RunState) -> Vector2i:
	if run.base_camp != null:
		return Basecamp.deck_rect(run.base_camp.seed_value, run.base_camp.side).get_center()
	return Vector2i(WorldIds.CELL_TILES / 2, WorldIds.CELL_TILES / 2)


func _lit_miner_in(run: RunState, m: Moth, c: MothPerception.Cluster) -> int:
	var best: int = 0
	var best_d: float = INF
	for miner: int in perception.lit_miners:
		var e: SimEntity = run.registry.get_entity(miner)
		if e == null or not c.tiles.has(e.tile()) or not _can_fall(run, miner):
			continue
		var d: float = e.position.distance_to(m.position(run))
		if d < best_d:
			best_d = d
			best = miner
	return best


func _nearest_tile_centre(c: MothPerception.Cluster, from: Vector2) -> Vector2:
	var best: Vector2 = c.centroid
	var best_d: float = INF
	for t: Vector2i in c.tiles:
		var p: Vector2 = Vector2(t) + Vector2(0.5, 0.5)
		var d: float = p.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = p
	return best


func _lamp_with_source(run: RunState, source: int) -> GauzeLamp:
	if run.lamps == null:
		return null
	for raw: Variant in run.lamps.lamps.keys():
		var l: GauzeLamp = run.lamps.lamps[raw]
		if l.source == source:
			return l
	return null


func _slot_of(run: RunState, miner: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == miner:
			return slot
	return -1
