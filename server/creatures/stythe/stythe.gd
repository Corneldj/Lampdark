class_name StytheCreature
extends Creature
## The Stythe (Gameplay §7.4), CRT-13's part: the entity, its states, its senses, whom it may hunt,
## how it moves, Lurk, circling and the snuff. Light is walls: tiles lit to stythe.wall_level (the
## Thin, CRT-17: thin_wall_level) are rock to it, light reaching its tile pushes it into the dark,
## and it opens no air door or gate. It senses only unlit miners by path (StytheSenses), hunts by
## StytheEligibility's table, moves by dark A* replanned at 4 Hz (StytheMove), and in its active
## states snuffs a flame every 2.0 or 1.6 s (StytheSnuff). Lurk waits in dark dead ends and side
## roads within its hunting range, moving on every stythe.lurk_move_s (Proposed), toward remembered
## places, else the highest marked Pull. The hunting states' behaviour (Hunt, WindUp, Drag, Collect,
## Flee, Circle's timing, Check, Retreat) is CRT-14's, Keep CRT-15's, Shadow CRT-16's; they are
## defined here so the state machine is whole. In the fringe it is a miner-sized token like any
## miner; lit to 0.30, a faceless figure (VIS-06); it casts no shadow (VIS-09). Server-only: its
## senses, memory, target and timers are never sent.

## CRT-15's trail: every tile a dragged victim enters, with the drag's heading (0-7; -1 the grab).
signal drag_tile_crossed(tile: Vector2i, dir: int)

## The lair (CRT-15, GEN-10 place it): where its territory and hunting range are measured from.
var lair: Vector2i = Vector2i.ZERO
## CRT-17's Thin: every 0.30 in its rules reads 0.50.
var thin: bool = false
## DIR-06's staged run 1: it never leaves its territory.
var staged: Callable = func() -> bool: return false
## LFT-09's apex: () -> Variant, the point at the gates to lurk near while the engine runs, or null.
var apex_point: Callable = func() -> Variant: return null
## CRT-15: the bodies it keeps (entity ids). CRT-14 adds a victim brought home.
var kept: Array[int] = []
## MNR-08: (run, source, seconds) -> bool, an electric lamp drained instead of snuffed.
var electric_drain: Callable = func(_r: RunState, _source: int, _seconds: float) -> bool: return false
var senses: StytheSenses = StytheSenses.new()
var move: StytheMove = StytheMove.new()
var snuff: StytheSnuff = StytheSnuff.new()
var hunt: StytheHunt = StytheHunt.new()
var drag: StytheDrag = StytheDrag.new()
var _breath: Tell = null
## Moving off a lit tile this tick (no wind-up, no snuff).
var pushed: bool = false
## The light circled (Circle), and until when (CRT-14 sets it).
var circle_seed: Vector2i = Vector2i(2147483647, 0)
var circle_until: int = -1
## Lurk's spot and when it moves on.
var lurk_spot: Vector2i = Vector2i(2147483647, 0)
var lurk_until: int = -1


func _init() -> void:
	kind = WorldIds.EntityKind.STYTHE
	max_speed = Tuning.f(&"stythe.speed")


## The active states (plays_tell) hold a cap place and snuff; Lurk, Shadow, Circle, Check, Keep,
## Flee and Retreat do not snuff.
func define_states() -> Array[CreatureState]:
	return [
		CreatureState.make(&"lurk", {}),
		CreatureState.make(&"shadow", {}),
		CreatureState.make(&"hunt", {"fills_cap_place": true, "chosen_entry": true, "plays_tell": true}),
		CreatureState.make(&"windup", {"fills_cap_place": true, "plays_tell": true}),
		# A drag holds its hunt's cap place through the hunt itself; one after a Collect holds none
		# (Proposed), and Collect never does (§10.8).
		CreatureState.make(&"drag", {"plays_tell": true}),
		CreatureState.make(&"collect", {"plays_tell": true}),
		CreatureState.make(&"keep", {}),
		CreatureState.make(&"flee", {}),
		CreatureState.make(&"circle", {}),
		CreatureState.make(&"check", {}),
		CreatureState.make(&"retreat", {}),
	]


## A dark path of creatures.guard_stythe_dark_path_tiles or less to a tile within its reach of
## the miner.
func guard_predicate() -> Callable:
	return func(run: RunState, miner: int) -> bool:
		return system.nav != null and system.nav.stythe_dark_path_within(tile(run), run.registry.get_entity(miner).position, -1.0, thin)


## Every rule's light level: 0.30, or 0.50 for the Thin. Nothing else compares against it.
func light_threshold() -> float:
	return Tuning.f(&"stythe.thin_wall_level") if thin else Tuning.f(&"stythe.wall_level")


## Below its threshold: a tile it can stand on, and a miner there it can sense.
func unlit(run: RunState, t: Vector2i) -> bool:
	return run.light == null or run.light.light_at(t) < light_threshold() - 1e-9


func is_active() -> bool:
	return state != null and state.plays_tell


## CRT-14's tell: the flames within stythe.tell_reach_tiles gutter (VIS-08) in the active states.
func flame_tell() -> int:
	return FlameFlags.GUTTER if is_active() else 0


func flame_tell_reach() -> float:
	return Tuning.f(&"stythe.tell_reach_tiles")


## The tell plays (Hunt, WindUp, Drag, Collect): the gutter, the breath, the crackle, the bite.
func tell_active() -> bool:
	return is_active()


## Where its tell plays now: its position while active, else none (SND-08, VIS-10 read it).
func tell_points(run: RunState) -> Array:
	return [position(run)] if tell_active() else []


func keeps() -> bool:
	return not kept.is_empty()


## The breath (a diffuse tell all around) plays while an active state lasts.
func enter(run: RunState, state_name: StringName, reason: String = "") -> void:
	super(run, state_name, reason)
	if system == null:
		return
	if is_active() and _breath == null:
		_breath = system.begin_tell(run, self, &"stythe_breath", Tuning.f(&"stythe.tell_reach_tiles"))
	elif not is_active() and _breath != null:
		system.end_tell(run, _breath)
		_breath = null


func on_spawned(run: RunState) -> void:
	if lair == Vector2i.ZERO:
		lair = tile(run)
	if run.mine != null:
		run.mine.native.tiles_changed.connect(func(_cell: Vector2i, _rect: Rect2i, _reason: String) -> void: senses.on_tiles_changed())
	# SND-08's crackle and VIS-10's bite read where its tell plays: ServerSystems wires them to
	# tell_points() when it spawns (a creature reads only its own senses).


func on_wind_up_finished(run: RunState, w: CreatureWindUp) -> void:
	hunt.on_wind_up_finished(run, self, w)


func on_grab_ended(run: RunState, grab: GrabHold, outcome: GrabHold.Outcome) -> void:
	if drag.victim == grab.victim:
		drag.victim = 0
		drag.grab_id = -1
	super(run, grab, outcome)


func on_retreat_started(run: RunState, _cause: String) -> void:
	hunt.on_retreat(run, self)


func on_retreat_ended(run: RunState, _toward_base: bool) -> void:
	enter(run, &"lurk", "retreat over")


## Home with a victim (CRT-15 lays the body in its row): it keeps them, and guards.
func reached_lair(run: RunState) -> void:
	if drag.victim != 0 and not kept.has(drag.victim):
		kept.append(drag.victim)
	move.stop()
	hunt.target = 0
	if not drag.collected:
		system.gate.stand_down(run, self, "home")
	enter(run, &"keep", "lair reached")


func shift_timers(by: int) -> void:
	super(by)
	circle_until = later(circle_until, by)
	lurk_until = later(lurk_until, by)
	snuff.next_due = later(snuff.next_due, by)
	for m: Dictionary in senses.memory:
		m["tick"] = later(int(Variants.number(m["tick"])), by)


func think(run: RunState) -> void:
	senses.update(run, self)
	if state.name == &"drag":
		# Light on it breaks the drag (it flees); it is never merely pushed while dragging.
		hunt.tick(run, self)
		snuff.tick(run, self, is_active())
		return
	pushed = move.push_off_light(run, self)
	if pushed:
		move.tick(run, self, Tuning.f(&"stythe.speed"))
		snuff.tick(run, self, is_active())
		return
	hunt.tick(run, self)
	match state.name:
		&"lurk", &"keep":
			_lurk(run)
		&"circle":
			if circle_seed.x != 2147483647:
				move.circle(run, self, circle_seed)
	snuff.tick(run, self, is_active())
	if state.name != &"drag":
		move.tick(run, self, Tuning.f(&"stythe.circle_speed") if state.name == &"circle" else Tuning.f(&"stythe.speed"))


## Through the dark toward a miner (CRT-14's Hunt): never past its territory in a staged run.
func chase(run: RunState, miner: int) -> void:
	var e: SimEntity = run.registry.get_entity(miner)
	if e == null:
		return
	if Variants.flag(staged.call()) and not senses.in_territory(run, self, e.tile()):
		return
	move.head_for(run, self, e.tile())


## Starts circling the light round `seed` for stythe.circle_s (CRT-14 decides when).
func begin_circle(run: RunState, seed: Vector2i) -> void:
	circle_seed = seed
	circle_until = run.tick + roundi(Tuning.f(&"stythe.circle_s") * Tuning.f(&"net.tick_hz"))
	move.stop()
	enter(run, &"circle", "circling a light")


## The miner it would take now, most preferred (0: none).
func best_target(run: RunState) -> int:
	var all: Array[int] = StytheEligibility.ranked(run, self)
	return all[0] if not all.is_empty() else 0


## Lurk: a dark dead end or side road within its hunting range (its territory when staged), moved
## on every stythe.lurk_move_s: toward the newest remembered place, else the highest marked Pull.
func _lurk(run: RunState) -> void:
	# The engine (LFT-09): within stythe.apex_lurk_tiles of the gates, unless it keeps or retreats.
	var apex: Variant = apex_point.call()
	if apex != null and not keeps() and not is_retreating():
		var at: Vector2 = apex
		if position(run).distance_to(at) > Tuning.f(&"stythe.apex_lurk_tiles"):
			var near: Variant = system.nav.native.reachable_dark_tile_nearest(Vector2i(floori(at.x), floori(at.y)), tile(run), move.params(self))
			if near != null:
				var n: Vector2i = near
				move.head_for(run, self, n)
			return
	if lurk_until >= 0 and run.tick < lurk_until and lurk_spot.x != 2147483647:
		move.head_for(run, self, lurk_spot)
		return
	var span: Vector2 = Tuning.range_f(&"stythe.lurk_move_s")
	var hz: float = Tuning.f(&"net.tick_hz")
	lurk_until = run.tick + rng.range(roundi(span.x * hz), roundi(span.y * hz))
	var spots: Array[Vector2i] = lurk_spots(run)
	if spots.is_empty():
		return
	var toward: Variant = null
	if not senses.memory.is_empty():
		toward = senses.memory[senses.memory.size() - 1]["tile"]
	else:
		var marked: int = _highest_marked(run)
		if marked != 0:
			toward = run.registry.get_entity(marked).tile()
	if toward != null:
		var t: Vector2i = toward
		spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da: float = Vector2(a).distance_squared_to(Vector2(t))
			var db: float = Vector2(b).distance_squared_to(Vector2(t))
			return da < db if not is_equal_approx(da, db) else (a.y < b.y or (a.y == b.y and a.x < b.x)))
		lurk_spot = spots[0]
	else:
		lurk_spot = spots[rng.range(0, spots.size() - 1)]
	move.head_for(run, self, lurk_spot)


## Dark dead ends and side roads (floor with one or two open sides) reachable from where it stands,
## within its hunting range (its territory when staged), nearest first, at most LURK_SEARCH tiles.
const LURK_SEARCH: int = 3000


func lurk_spots(run: RunState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if run.mine == null:
		return out
	var staged_now: bool = Variants.flag(staged.call()) or keeps()
	var apex: Variant = apex_point.call() if not keeps() and not is_retreating() else null
	var start: Vector2i = tile(run)
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size() and seen.size() < LURK_SEARCH:
		var t: Vector2i = queue[head]
		head += 1
		var open: int = 0
		for d: Vector2i in dirs:
			var n: Vector2i = t + d
			if not run.mine.native.is_walkable(n, false):
				continue
			open += 1
			if not seen.has(n) and unlit(run, n):
				seen[n] = true
				queue.append(n)
		if open <= 2 and t != start and unlit(run, t):
			var ok: bool = senses.in_territory(run, self, t) if staged_now else senses.in_hunting_range(run, self, t)
			if apex != null:
				var ap: Vector2 = apex
				ok = ok and (Vector2(t) + Vector2(0.5, 0.5)).distance_to(ap) <= Tuning.f(&"stythe.apex_lurk_tiles")
			if ok:
				out.append(t)
	return out


func _highest_marked(run: RunState) -> int:
	var best: int = 0
	var best_pull: float = Tuning.f(&"pull.threshold_marked")
	for m: int in StytheSenses.miners(run):
		var p: float = StytheEligibility.pull_of(self, m)
		if p >= best_pull and (best == 0 or p > best_pull):
			best = m
			best_pull = p
	return best
