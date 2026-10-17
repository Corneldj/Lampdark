class_name CreatureSystem
extends SimSystem
## CRT-01's creature registry, spawner and tick (stage 7, after the defender rule). One creature
## of each enabled kind per run, and no Tapper under Quiet Seam; nothing spawns a second. A
## creature never starts on a tile in any client's seen set or hidden margin: such a spawn waits
## and logs an error. It never teleports: a step past its speed limit in one tick is counted,
## logged and, in debug builds, reported as an error. Everything here is server-only.

## A listener-centred tell's cue for one client (SND-03 plays it): {tell, points}, nothing else.
signal tell_cue(slot: int, record: Dictionary)
## A creature entered the world (ServerSystems wires per-kind hooks, e.g. the Tapper's drop_lamp).
signal spawned(c: Creature)

const DOMAINS: Dictionary = {
	WorldIds.EntityKind.MOTH: HashDomain.CREATURES_MOTH,
	WorldIds.EntityKind.TAPPER: HashDomain.CREATURES_TAPPER,
	WorldIds.EntityKind.STYTHE: HashDomain.CREATURES_STYTHE,
}
const QUIET_SEAM: String = "quiet_seam"
const STEP_SLACK_TILES: float = 0.01

var creatures: Array[Creature] = []
var log: CreatureLog = CreatureLog.new()
var gate: HuntGate = HuntGate.new(log)
var guards: GuardRegistry = GuardRegistry.new()
## HAZ-07's draw of run conditions; "quiet_seam" means no Tapper.
var conditions: Array[String] = []
## RSC-03 releases a grabbed or carried miner: (creature, miner_entity) -> void.
var grab_release: Callable = Callable()
var tells: Array[Tell] = []
## CRT-02's navigation, when the run has a mine.
var nav: CreatureNav = null
var wind_ups: Array[CreatureWindUp] = []
var teleport_violations: int = 0
## [creature, tile] waiting for their start tile to leave every seen set and margin.
var deferred: Array[Array] = []
var _last: Dictionary = {}
## FND-08's freeze_ai: while set, no creature decides, moves, winds up, tells or ends a retreat;
## thawing moves every creature timer on by the frozen ticks (Creature.shift_timers). MOD-08's Hired
## Hands and Bess read it too.
var frozen: bool = false
var _frozen_at: int = -1
## FND-08's `creatures off`: kind -> [creature, position], out of the simulation, every perception
## and every hearing check until put back.
var suspended: Dictionary = {}
var _next_id: int = 1
var _retreat_ticks: int = 2400


func _init() -> void:
	if Tuning.current.has_key(&"creatures.retreat_s"):
		_retreat_ticks = roundi(Tuning.f(&"creatures.retreat_s") * Tuning.f(&"net.tick_hz"))


func stage() -> int:
	return StageTable.Stage.CREATURES


func order() -> int:
	return 20


func system_name() -> String:
	return "CreatureSystem"


## Wires the M1 defaults: crew count from the conscious miners (DIR-05 replaces it).
func bind(run: RunState) -> void:
	gate.crew_count = func() -> int: return conscious_miners(run)
	if run.mine != null:
		nav = CreatureNav.new(run.mine, run.light)
		run.mine.keep_loaded = func(cell: Vector2i) -> bool: return CreatureNav.keeps_loaded(run, cell)


func is_enabled(kind: WorldIds.EntityKind) -> bool:
	var flags: Dictionary = Tuning.table(&"creatures.enabled")
	return int(Variants.number(flags.get(str(WorldIds.EntityKind.find_key(kind)).to_lower(), 0))) == 1


func count_of(kind: WorldIds.EntityKind) -> int:
	var n: int = 0
	for c: Creature in creatures:
		if c.kind == kind:
			n += 1
	for d: Array in deferred:
		var c: Creature = d[0]
		if c.kind == kind:
			n += 1
	if suspended.has(kind):
		n += 1
	return n


## Places a creature at `tile`. OK when placed, ERR_BUSY when its start tile is seen or in a
## margin (it waits and spawns once the tile is clear), or an error: a disabled kind, a Tapper
## under Quiet Seam, a second of a kind, or no guard predicate.
func spawn(run: RunState, c: Creature, at_tile: Vector2i) -> Error:
	var name: String = str(WorldIds.EntityKind.find_key(c.kind)).to_lower()
	if not DOMAINS.has(c.kind):
		push_error("CreatureSystem: %s is not a creature" % name)
		return ERR_INVALID_PARAMETER
	if not is_enabled(c.kind):
		log.add(run.tick, &"spawn_refused", {"creature": name, "reason": "disabled"})
		return ERR_UNAVAILABLE
	if c.kind == WorldIds.EntityKind.TAPPER and conditions.has(QUIET_SEAM):
		log.add(run.tick, &"spawn_refused", {"creature": name, "reason": "quiet seam"})
		return ERR_UNAVAILABLE
	if count_of(c.kind) >= Tuning.i(&"creatures.population_per_kind"):
		push_error("CreatureSystem: a second %s refused: one of each per run" % name)
		return ERR_ALREADY_EXISTS
	if not guards.register(c.kind, c.guard_predicate()):
		return ERR_INVALID_PARAMETER
	if _tile_watched(run, at_tile):
		push_error("CreatureSystem: %s's start tile %s is seen or in a margin; the spawn waits" % [name, at_tile])
		log.add(run.tick, &"spawn_deferred", {"creature": name, "tile": at_tile})
		deferred.append([c, at_tile])
		return ERR_BUSY
	_place(run, c, at_tile)
	return OK


## FND-08's console spawn: spawn's checks, but placed at once even on a seen tile.
func place_now(run: RunState, c: Creature, at_tile: Vector2i) -> Error:
	var name: String = str(WorldIds.EntityKind.find_key(c.kind)).to_lower()
	if not DOMAINS.has(c.kind):
		return ERR_INVALID_PARAMETER
	if not is_enabled(c.kind):
		return ERR_UNAVAILABLE
	if count_of(c.kind) >= Tuning.i(&"creatures.population_per_kind"):
		return ERR_ALREADY_EXISTS
	if not guards.register(c.kind, c.guard_predicate()):
		return ERR_INVALID_PARAMETER
	log.add(run.tick, &"spawn_forced", {"creature": name, "tile": at_tile})
	_place(run, c, at_tile)
	return OK


## FND-08's freeze_ai.
func set_frozen(run: RunState, on: bool) -> void:
	if on == frozen:
		return
	frozen = on
	if on:
		_frozen_at = run.tick
		log.add(run.tick, &"ai_frozen", {})
		return
	var by: int = run.tick - _frozen_at
	for c: Creature in creatures:
		c.shift_timers(by)
	for raw: Variant in suspended.values():
		var c: Creature = Variants.array(raw)[0]
		c.shift_timers(by)
	for w: CreatureWindUp in wind_ups:
		w.start_tick = Creature.later(w.start_tick, by)
		w.end_tick = Creature.later(w.end_tick, by)
	for t: Tell in tells:
		t.start_tick = Creature.later(t.start_tick, by)
		t.end_tick = Creature.later(t.end_tick, by)
	log.add(run.tick, &"ai_thawed", {"ticks": by})


## FND-08's `creatures off`: the creature leaves the simulation (its entity goes, so no perception,
## hearing or replication meets it) until resume(). Refused while it grabs or winds up.
func suspend(run: RunState, c: Creature) -> bool:
	if c.grabbing != 0 or c.wind_up != null:
		return false
	gate.stand_down(run, c, "suspended")
	suspended[c.kind] = [c, c.position(run)]
	creatures.erase(c)
	gate.creatures.erase(c)
	_last.erase(c.entity_id)
	run.registry.destroy(c.entity_id)
	log.add(run.tick, &"suspended", {"creature": c.kind_name()})
	return true


## FND-08's `creatures on`: back where it was, in the state it left, with a fresh entity.
func resume(run: RunState, kind: WorldIds.EntityKind) -> Creature:
	if not suspended.has(kind):
		return null
	var held: Array = suspended[kind]
	suspended.erase(kind)
	var c: Creature = held[0]
	var at: Vector2 = held[1]
	var e: SimEntity = run.registry.create(c.kind, at)
	c.entity_id = e.id
	creatures.append(c)
	gate.creatures.append(c)
	_last[c.entity_id] = at
	log.add(run.tick, &"resumed", {"creature": c.kind_name()})
	return c


func creature_of(entity: int) -> Creature:
	for c: Creature in creatures:
		if c.entity_id == entity:
			return c
	return null


func creature_of_kind(kind: WorldIds.EntityKind) -> Creature:
	for c: Creature in creatures:
		if c.kind == kind:
			return c
	return null


## NET-06's body shapes for a shot: a creature's hit body, or a miner's (or Bess's) circle.
func body_radius_of(e: SimEntity) -> float:
	var c: Creature = creature_of(e.id)
	if c != null:
		return c.hit_body()
	if e.kind == WorldIds.EntityKind.TAPPER_ARM:
		var tapper: Tapper = creature_of_kind(WorldIds.EntityKind.TAPPER) as Tapper
		return tapper.arm_radius() if tapper != null and tapper.hunt.arm == e.id else 0.0
	return Tuning.f(&"movement.body_radius")


## The only way a creature moves (CRT-02 calls it along its path).
func move_to(run: RunState, c: Creature, to: Vector2) -> void:
	run.registry.move(c.entity_id, to)


## A wind-up of `duration_s` (refused below creatures.windup_min_s) on a miner; `condition` is
## the reach (and whatever else) that must still hold at the end.
func begin_wind_up(run: RunState, c: Creature, slot: int, miner: int, duration_s: float, condition: Callable) -> CreatureWindUp:
	var w: CreatureWindUp = CreatureWindUp.make(c, run, slot, miner, duration_s, condition)
	if not w.valid:
		return w
	w.id = _next_id
	_next_id += 1
	c.wind_up = w
	wind_ups.append(w)
	log.add(run.tick, &"wind_up_started", {"id": w.id, "creature": c.kind_name(), "target": miner, "start": w.start_tick, "end": w.end_tick})
	return w


## A tell reaching beyond creatures.tell_min_reach_tiles (refused otherwise).
func begin_tell(run: RunState, c: Creature, kind: StringName, reach_tiles: float, form: Tell.Form = Tell.Form.LISTENER_CENTRED) -> Tell:
	var t: Tell = Tell.make(c, run, kind, reach_tiles, form)
	if not t.valid:
		return t
	t.id = _next_id
	_next_id += 1
	tells.append(t)
	log.add(run.tick, &"tell", {"id": t.id, "creature": c.kind_name(), "kind": kind, "start": run.tick,
		"origin": c.position(run), "reach": reach_tiles, "form": int(form)})
	_send_tell(run, t)
	return t


func end_tell(run: RunState, t: Tell) -> void:
	if t.end_tick >= 0:
		return
	t.end_tick = run.tick
	tells.erase(t)
	log.add(run.tick, &"tell_ended", {"id": t.id, "creature": t.creature.kind_name(), "end": run.tick})


## LFT-10: moves a creature where it cannot walk (the Tapper into the shaft's rock beside the
## riding cage, and back below at the brick): logged, and never counted as a teleport.
func relocate(run: RunState, c: Creature, at: Vector2) -> void:
	run.registry.move(c.entity_id, at)
	_last[c.entity_id] = at
	if c is Tapper:
		(c as Tapper).follower.stop()
	log.add(run.tick, &"relocated", {"creature": c.kind_name(), "to": at})


## The revolver's threshold, or a flare on the Moth while it lays or carries a lamp home: for
## creatures.retreat_s the wind-up is cancelled, any grab drops and the hunt stands down.
func begin_retreat(run: RunState, c: Creature, cause: String) -> void:
	if c.wind_up != null and c.wind_up.is_running():
		c.wind_up.cancel(run, "retreat")
	if c.grabbing != 0:
		var miner: int = c.grabbing
		if grab_release.is_valid():
			grab_release.call(c, miner)
		c.grabbing = 0
		log.add(run.tick, &"grab_dropped", {"creature": c.kind_name(), "miner": miner, "cause": cause})
		c.on_grab_dropped(run)
	gate.stand_down(run, c, "retreat")
	c.retreat_until = run.tick + _retreat_ticks
	log.add(run.tick, &"retreat", {"creature": c.kind_name(), "cause": cause, "until": c.retreat_until})
	c.on_retreat_started(run, cause)


## MNR-16: a shot hit this entity. Over the threshold it retreats; under it, it flinches and
## nothing is cancelled. Returns false when there was nothing of it to hit.
func on_hit(run: RunState, entity: int, over_threshold: bool) -> bool:
	var c: Creature = creature_of(entity)
	if c == null and run.registry.has(entity) and run.registry.get_entity(entity).kind == WorldIds.EntityKind.TAPPER_ARM:
		c = creature_of_kind(WorldIds.EntityKind.TAPPER)
		if c != null and body_radius_of(run.registry.get_entity(entity)) <= 0.0:
			c = null
	elif c != null and c.hit_body() <= 0.0:
		c = null
	if c == null:
		return false
	log.add(run.tick, &"hit", {"creature": c.kind_name(), "over_threshold": over_threshold})
	if over_threshold:
		begin_retreat(run, c, "revolver")
	else:
		c.on_flinch(run)
	return true


## DIR-05's default crew count: the conscious miners (unconscious and dead left out).
func conscious_miners(run: RunState) -> int:
	var n: int = 0
	for id: int in run.registry.ids():
		var e: SimEntity = run.registry.get_entity(id)
		if e.kind != WorldIds.EntityKind.MINER:
			continue
		if run.miner_state != null and run.miner_state.miner(id) != null and run.miner_state.life(id) >= MinerTransitions.Life.UNCONSCIOUS:
			continue
		n += 1
	return n


func tick(run: RunState) -> void:
	for d: Array in deferred.duplicate():
		var c: Creature = d[0]
		var at: Vector2i = d[1]
		if not _tile_watched(run, at):
			deferred.erase(d)
			_place(run, c, at)
	if frozen:
		return
	for c: Creature in creatures:
		if c.retreat_until >= 0 and run.tick >= c.retreat_until:
			c.retreat_until = -1
			var toward_base: bool = Variants.flag(gate.apex_on.call())
			log.add(run.tick, &"retreat_ended", {"creature": c.kind_name(), "toward_base": toward_base})
			c.on_retreat_ended(run, toward_base)
	for w: CreatureWindUp in wind_ups.duplicate():
		w.tick(run)
		if not w.is_running():
			wind_ups.erase(w)
	for c: Creature in creatures:
		c.think(run)
	gate.tick(run)
	for t: Tell in tells:
		_send_tell(run, t)
	_check_steps(run)


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(_next_id)
	writer.put_i64(creatures.size())
	for c: Creature in creatures:
		writer.put_i64(c.kind)
		writer.put_i64(c.entity_id)
		writer.put_string(c.state.name if c.state != null else &"")
		writer.put_i64(c.retreat_until)
		writer.put_i64(c.grabbing)
		writer.put_i64(gate.target_of(c))
		writer.put_string(str(c.rng.get_state()) if c.rng != null else "")
	writer.put_i64(wind_ups.size())
	for w: CreatureWindUp in wind_ups:
		writer.put_i64(w.id)
		writer.put_i64(w.end_tick)
		writer.put_i64(w.outcome)
	writer.put_i64(deferred.size())


func _place(run: RunState, c: Creature, at_tile: Vector2i) -> void:
	var e: SimEntity = run.registry.create(c.kind, Vector2(at_tile) + Vector2(0.5, 0.5))
	c.entity_id = e.id
	c.system = self
	c.rng = run.stream(int(Variants.number(DOMAINS[c.kind])), PackedInt64Array([0]))
	c.states.clear()
	var defined: Array[CreatureState] = c.define_states()
	for s: CreatureState in defined:
		c.states[s.name] = s
	c.state = defined[0]
	creatures.append(c)
	gate.creatures.append(c)
	_last[c.entity_id] = e.position
	log.add(run.tick, &"spawn", {"creature": c.kind_name(), "tile": at_tile, "state": c.state.name})
	c.on_spawned(run)
	spawned.emit(c)


func _tile_watched(run: RunState, at_tile: Vector2i) -> bool:
	return run.vision != null and run.vision.native.is_seen_or_margin_of_any(at_tile)


## Every listener within reach of a playing listener-centred tell gets its cue, once.
func _send_tell(run: RunState, t: Tell) -> void:
	if t.form != Tell.Form.LISTENER_CENTRED or run.movement == null:
		return
	var from: Vector2 = t.creature.position(run)
	for slot: int in run.movement.miner_slots():
		if t.sent.has(slot):
			continue
		var m: MovementSystem.Miner = run.movement.miner(slot)
		var at: Vector2 = Vector2(m.state.x, m.state.y)
		if at.distance_to(from) > t.reach_tiles:
			continue
		var record: Dictionary = Tell.cue_record(t.tell_kind, Tell.points_around(run, t.creature.rng, at))
		t.sent[slot] = true
		tell_cue.emit(slot, record)


func _check_steps(run: RunState) -> void:
	var dt: float = 1.0 / Tuning.f(&"net.tick_hz")
	for c: Creature in creatures:
		var now: Vector2 = c.position(run)
		var was: Vector2 = _last.get(c.entity_id, now)
		var step: float = was.distance_to(now)
		if step > c.max_speed * dt + STEP_SLACK_TILES:
			teleport_violations += 1
			log.add(run.tick, &"teleport", {"creature": c.kind_name(), "step": step, "limit": c.max_speed * dt})
			if OS.is_debug_build():
				push_error("CreatureSystem: %s moved %.3f tiles in one tick (limit %.3f)" % [c.kind_name(), step, c.max_speed * dt])
		_last[c.entity_id] = now


## NET-09: every creature: its kind, its entity (the registry keeps it), the state it was in, its
## retreat, its random stream and its kind's own (Creature.save_extra).
func save_state() -> Dictionary:
	var out: Array = []
	for c: Creature in creatures:
		out.append({"kind": c.kind, "entity": c.entity_id, "state": c.state.name if c.state != null else &"",
			"retreat_until": c.retreat_until, "rng": c.rng.get_state() if c.rng != null else 0, "has_rng": c.rng != null, "extra": c.save_extra()})
	return {"creatures": out}


## Back on its own entity, calm (Creature.resume_state), its stream where it was.
func load_state(run: RunState, state: Dictionary) -> void:
	for raw: Variant in Variants.array(state.get("creatures", [])):
		var d: Dictionary = raw
		var c: Creature = make_kind(int(Variants.number(d["kind"])))
		var entity: int = int(Variants.number(d["entity"]))
		if c == null or not run.registry.has(entity):
			continue
		c.entity_id = entity
		c.system = self
		c.rng = run.stream(int(Variants.number(DOMAINS[c.kind])), PackedInt64Array([0]))
		if Variants.flag(d.get("has_rng", false)):
			c.rng.set_state(int(Variants.number(d["rng"])))
		c.states.clear()
		for s: CreatureState in c.define_states():
			c.states[s.name] = s
		c.state = c.states[c.state_order()[0]]
		creatures.append(c)
		gate.creatures.append(c)
		_last[c.entity_id] = run.registry.get_entity(entity).position
		guards.register(c.kind, c.guard_predicate())
		c.on_spawned(run)
		c.load_extra(run, Variants.dict(d.get("extra", {})))
		c.retreat_until = int(Variants.number(d.get("retreat_until", -1)))
		var want: StringName = c.resume_state(StringName(str(d["state"])))
		if c.states.has(want) and want != c.state.name:
			c.enter(run, want, "resumed")
		log.add(run.tick, &"resumed_from_save", {"creature": c.kind_name(), "state": c.state.name})
		spawned.emit(c)


## A new creature of `kind` (Moth, Tapper or Stythe), or null.
static func make_kind(kind: int) -> Creature:
	match kind:
		WorldIds.EntityKind.MOTH:
			return Moth.new()
		WorldIds.EntityKind.TAPPER:
			return Tapper.new()
		WorldIds.EntityKind.STYTHE:
			return StytheCreature.new()
	return null
