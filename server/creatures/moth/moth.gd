class_name Moth
extends Creature
## The Moth (Gameplay §7.2), CRT-03's part: its entity, its state shell and sleep. Asleep it is
## silent, tells nothing and is one more heap of coats in the fringe (the motionless token class,
## VIS-03). A stir lasts moth.stir_tell_s with its tell; at the end it wakes, or settles for
## moth.settle_s and sleeps again. Hunger and a marked miner raise it straight to Prowl with no
## stir and no rustle. Before sleeping it preens for moth.preen_s. Awake (Frenzy to Search) it
## hunts light: MothAwake, CRT-04. Everything here is server-only.

const SLEEPY: Array[StringName] = [&"asleep", &"settling", &"stirring"]
const HEAP_REPLY: String = "[a heap of coats]"

var sleep: MothSleep = MothSleep.new()
## Where it last went to sleep (the hoard counts as a roost).
var roost: Vector2i = Vector2i.ZERO
## Who or what woke it, known for moth.frenzy_waker_known_s: {cause, position, owner, until}.
var waker: Dictionary = {}
## Why Prowl was entered without a frenzy: "hunger", "marked" or "engine".
var rose_for: String = ""
var stir_tell: Tell = null
var settle_tell: Tell = null
## CRT-04: everything it does awake.
var awake: MothAwake = MothAwake.new()


func _init() -> void:
	kind = WorldIds.EntityKind.MOTH
	max_speed = Tuning.f(&"moth.retreat_speed")
	body_radius = Tuning.f(&"moth.hit_radius_tiles")


func define_states() -> Array[CreatureState]:
	return [
		CreatureState.make(&"asleep"),
		CreatureState.make(&"stirring", {"plays_tell": true}),
		CreatureState.make(&"settling"),
		CreatureState.make(&"preening"),
		CreatureState.make(&"frenzy"),
		CreatureState.make(&"prowl"),
		# Hunt through Search hold a place under the cap (§7.2's table).
		CreatureState.make(&"hunt", {"fills_cap_place": true}),
		CreatureState.make(&"windup", {"fills_cap_place": true}),
		CreatureState.make(&"smother", {"fills_cap_place": true}),
		CreatureState.make(&"linger", {"fills_cap_place": true}),
		CreatureState.make(&"last_spot", {"fills_cap_place": true}),
		CreatureState.make(&"search", {"fills_cap_place": true}),
	]


## Awake (a stir counts), the miner's light within its sight range, and a walkable path of
## creatures.guard_moth_path_tiles or less to the miner.
func guard_predicate() -> Callable:
	return func(run: RunState, miner: int) -> bool:
		if state == null or state.name == &"asleep" or state.name == &"settling" or system.nav == null:
			return false
		var at: Vector2 = run.registry.get_entity(miner).position
		if at.distance_to(position(run)) > CreatureTables.moth_sight_tiles(ring(run)):
			return false
		if run.light == null or run.light.light_at(Vector2i(floori(at.x), floori(at.y))) < Tuning.f(&"moth.see_level"):
			return false
		return system.nav.moth_path_within(tile(run), at)


func on_spawned(run: RunState) -> void:
	if run.light != null:
		run.light.grid.source_added.connect(sleep.on_source_added)
	fall_asleep(run)


func shift_timers(by: int) -> void:
	super(by)
	sleep.state_until = later(sleep.state_until, by)
	sleep.hunger_at = later(sleep.hunger_at, by)
	sleep._next_marked_check = later(sleep._next_marked_check, by)
	awake.until = later(awake.until, by)
	awake.search_min_until = later(awake.search_min_until, by)
	awake.prowl_since = later(awake.prowl_since, by)
	awake.perception.scanned_tick = later(awake.perception.scanned_tick, by)
	for l: MothMemory.Light in awake.memory.lights:
		l.tick = later(l.tick, by)


func is_sleeping() -> bool:
	return state != null and SLEEPY.has(state.name)


## VIS-08 trembles open flames and VIS-09 settles dust while this is true: the stir's 1.5 s, and
## every awake state (CRT-04).
func tell_active() -> bool:
	return (stir_tell != null and stir_tell.is_playing()) or awake.tell_active()


## VIS-08: open flames within moth.tell_reach_tiles tremble while the tell plays.
func flame_tell() -> int:
	return FlameFlags.TREMBLE if tell_active() else 0


func flame_tell_reach() -> float:
	return Tuning.f(&"moth.tell_reach_tiles")


## VIS-07: what feeling it reports while it sleeps; identical to a heap of coats.
func feel_reply() -> String:
	return HEAP_REPLY


## CRT-06's hatch and LFT-09's engine: a stir that always ends in waking (the engine to Prowl
## toward base camp, the hatch to Frenzy toward it). Ignored during a retreat's deep sleep, and
## by a Moth already awake. Returns whether it was taken.
func wake(run: RunState, why: MothSleep.Cause, waker_position: Vector2) -> bool:
	if is_retreating() or not is_sleeping():
		return false
	sleep.cause_position = waker_position
	if state.name == &"stirring":
		sleep.cause = why
	else:
		_stir(run, why)
	return true


## CRT-04 calls this at the roost it reached: preen moth.preen_s, awake and seeing, then sleep.
func begin_preen(run: RunState) -> void:
	enter(run, &"preening", "preen")
	sleep.state_until = run.tick + sleep.preen_ticks


func fall_asleep(run: RunState) -> void:
	awake.end(run, self)
	roost = tile(run)
	sleep.clear_clock()
	sleep.draw_hunger(run, rng, system.conditions.has("restless_moth"))
	enter(run, &"asleep", "sleep")


func think(run: RunState) -> void:
	var e: SimEntity = run.registry.get_entity(entity_id)
	if e != null:
		var still: bool = is_sleeping() or state.name == &"preening"
		e.flags = (e.flags | SimEntity.FLAG_MOTIONLESS) if still else (e.flags & ~SimEntity.FLAG_MOTIONLESS)
	if is_retreating():
		sleep.pending.clear()
		return
	match state.name:
		&"asleep", &"settling":
			var light: int = sleep.sample(run, tile(run))
			var why: MothSleep.Cause = sleep.trigger(run, position(run), light)
			if why != MothSleep.Cause.NONE:
				_stir(run, why)
			elif state.name == &"settling" and run.tick >= sleep.state_until:
				if settle_tell != null:
					system.end_tell(run, settle_tell)
				enter(run, &"asleep", "settled")
			elif state.name == &"asleep" and run.tick >= sleep.hunger_at:
				_rise(run, "hunger")
			elif state.name == &"asleep" and sleep.marked_near(run, system.gate, Vector2(roost) + Vector2(0.5, 0.5)):
				_rise(run, "marked")
		&"stirring":
			var light: int = sleep.sample(run, tile(run))
			var why: MothSleep.Cause = sleep.trigger(run, position(run), light)
			if why != MothSleep.Cause.NONE and why != MothSleep.Cause.CLOCK and sleep.cause == MothSleep.Cause.CLOCK:
				sleep.cause = why
			if run.tick >= sleep.state_until:
				system.end_tell(run, stir_tell)
				if sleep.wakes_at_end(light):
					_wake_up(run, light)
				else:
					_settle(run)
		&"preening":
			sleep.pending.clear()
			if run.tick >= sleep.state_until:
				fall_asleep(run)
		_:
			sleep.pending.clear()
			awake.tick(run, self)


func on_wind_up_finished(run: RunState, w: CreatureWindUp) -> void:
	awake.on_wind_up_finished(run, self, w)


func _stir(run: RunState, why: MothSleep.Cause) -> void:
	if settle_tell != null and settle_tell.is_playing():
		system.end_tell(run, settle_tell)
	sleep.cause = why
	sleep.clear_clock()
	sleep.state_until = run.tick + sleep.stir_ticks
	enter(run, &"stirring", str(MothSleep.Cause.keys()[why]).to_lower())
	stir_tell = system.begin_tell(run, self, &"moth_stir", Tuning.f(&"moth.tell_reach_tiles"))
	_log_light(run, why)


func _settle(run: RunState) -> void:
	# Light seen during the stir is spent: only a fresh trigger starts a new one.
	sleep.clear_clock()
	enter(run, &"settling", "light gone")
	sleep.state_until = run.tick + sleep.settle_ticks
	settle_tell = system.begin_tell(run, self, &"moth_settle", Tuning.f(&"moth.tell_reach_tiles"))


func _wake_up(run: RunState, light: int) -> void:
	var why: MothSleep.Cause = sleep.cause
	var at: Vector2 = sleep.cause_position
	var owner: int = 0
	if why == MothSleep.Cause.CLOCK or why == MothSleep.Cause.BRIGHT:
		var src: Dictionary = run.light.grid.brightest_source(tile(run))
		at = src.get("position", position(run))
		owner = int(Variants.number(src.get("owner", 0)))
	waker = {"cause": str(MothSleep.Cause.keys()[why]).to_lower(), "position": at, "owner": owner,
		"until": run.tick + roundi(Tuning.f(&"moth.frenzy_waker_known_s") * Tuning.f(&"net.tick_hz")), "light": light / 1000.0}
	if why == MothSleep.Cause.ENGINE:
		rose_for = "engine"
		enter(run, &"prowl", "engine")
		awake.begin(run, self, false)
	else:
		rose_for = ""
		enter(run, &"frenzy", str(waker["cause"]))
		awake.begin(run, self, true)


func _rise(run: RunState, why: String) -> void:
	rose_for = why
	system.log.add(run.tick, &"moth_rise", {"why": why})
	enter(run, &"prowl", why)
	awake.begin(run, self, false)


## For the Inquiry (RSC-07): the light on the Moth at the stir, the brightest source and each
## miner's own share, with that miner's lamp state and wick (MNR-06).
func _log_light(run: RunState, why: MothSleep.Cause) -> void:
	if run.light == null:
		return
	var t: Vector2i = tile(run)
	var shares: Dictionary = {}
	var lamps: Dictionary = {}
	for id: int in run.registry.ids():
		if run.registry.get_entity(id).kind == WorldIds.EntityKind.MINER:
			var v: int = run.light.grid.value_from(t, PackedInt64Array([id]))
			if v > 0:
				shares[id] = v / 1000.0
				# MNR-06: the lamp's state and wick, so RSC-07 can say 'your lamp at wick up'.
				if run.lamps != null and not run.lamps.describe(id).is_empty():
					lamps[id] = run.lamps.describe(id)
	system.log.add(run.tick, &"moth_stir", {"cause": str(MothSleep.Cause.keys()[why]).to_lower(),
		"light": run.light.grid.value(t) / 1000.0, "brightest": run.light.grid.brightest_source(t), "by_miner": shares,
		"lamps": lamps})
