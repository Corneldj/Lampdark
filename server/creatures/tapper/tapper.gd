class_name Tapper
extends Creature
## The Tapper (Gameplay §7.3), CRT-08's part: it lives unseen in the rock (its body is never
## perceived: only its arm leaves a wall face, CRT-09), moves through rock and coal at
## tapper.rock_speed (beneath open floor too, never beneath brick-lined floor, CRT-02), hears only
## through the Road Graph, and remembers the crew's noise as heat on wall faces. Patrol goes
## toward the hottest face, or rests in rich rock when the map is cold; Attend holds 15-40 tiles
## from the highest-Pull miner at Pull 30 or more; a relax sends it into rich rock; the apex
## brings it to the rock beyond the arches. Hunting (CRT-09) is TapperHunt's. Server-only.

## VIS-09: each tap's wall points and those lit for dust.
signal tapped(points: Array[Vector2i], lit: Array[Vector2i])

## Creature listener ids sit above any player slot (SND-01's players are their slots).
const LISTENER_BASE: int = 100000
const MASS_SEARCH_TILES: int = 30
const MASS_SPACING_TILES: float = 6.0

## GEN-10's rich rock: (tile) -> bool. Default: rock or coal at least 4 tiles thick.
var rich_rock: Callable = Callable()
## MNR-06: (victim, face) -> void, the pinned miner's lamp falling at the wall (burning if open).
var drop_lamp: Callable = Callable()
var hunt: TapperHunt = TapperHunt.new()
## LFT-09: () -> Variant, the point at the brick arches to come to at the apex, or null.
var apex_point: Callable = func() -> Variant: return null
var hearing: TapperHearing = null
var heat: HeatMap = HeatMap.new()
var follower: NavFollower = NavFollower.new()
## The miner it attends (0: none), and the heard events of the last tick (CRT-09 reads them).
var attending: int = 0
var recent: Array[TapperHearing.HeardEvent] = []
var dwell_until: int = -1
var _listen_tile: Vector2i = Vector2i(2147483647, 0)
var _goal: Vector2i = Vector2i(2147483647, 0)


func _init() -> void:
	kind = WorldIds.EntityKind.TAPPER
	max_speed = Tuning.f(&"tapper.rock_speed")


## Only the arm is ever a body, and only in WindUp, Pin and ReStrike (its own entity, TAPPER_ARM).
## The hunting states hold a cap place; Patrol, Attend and Retreat do not.
func define_states() -> Array[CreatureState]:
	return [
		CreatureState.make(&"patrol", {"hittable": false}),
		CreatureState.make(&"attend", {"hittable": false}),
		CreatureState.make(&"approach", {"fills_cap_place": true, "chosen_entry": true, "plays_tell": true, "hittable": false}),
		CreatureState.make(&"listen", {"fills_cap_place": true, "hittable": false}),
		CreatureState.make(&"search", {"fills_cap_place": true, "plays_tell": true, "hittable": false}),
		CreatureState.make(&"windup", {"fills_cap_place": true}),
		CreatureState.make(&"pin", {"fills_cap_place": true}),
		CreatureState.make(&"restrike", {"fills_cap_place": true}),
		CreatureState.make(&"retreat", {"hittable": false}),
	]


## The Tapper's own entity, in the rock, is never hit; the arm is (CreatureSystem.body_radius_of).
func hit_body() -> float:
	return 0.0


func arm_radius() -> float:
	return Tuning.f(&"tapper.arm_hit_radius_tiles") if state != null and state.hittable and hunt.arm != 0 else 0.0


## A rock path of creatures.guard_tapper_rock_path_tiles or less to a usable face within its
## reach of the miner.
func guard_predicate() -> Callable:
	return func(run: RunState, miner: int) -> bool:
		return system.nav != null and system.nav.tapper_rock_path_within(tile(run), run.registry.get_entity(miner).position)


func shift_timers(by: int) -> void:
	super(by)
	dwell_until = later(dwell_until, by)
	hunt.until = later(hunt.until, by)
	hunt.taps.next_tick = later(hunt.taps.next_tick, by)
	hunt.pin.spoil_tick = later(hunt.pin.spoil_tick, by)
	hunt.pin.restrike_at = later(hunt.pin.restrike_at, by)
	for e: TapperHearing.HeardEvent in recent:
		e.tick = later(e.tick, by)
	for face: Variant in heat.faces.keys():
		for entry: Variant in Variants.array(heat.faces[face]):
			var pair: Array = Variants.array(entry)
			pair[0] = later(int(Variants.number(pair[0])), by)


func on_spawned(run: RunState) -> void:
	hearing = TapperHearing.new(run, LISTENER_BASE + entity_id)
	_listen(run)
	if run.holds != null:
		run.holds.grab_timed_out.connect(func(id: int) -> void:
			if id == hunt.pin.grab_id:
				run.holds.end_grab(run, id, GrabHold.Outcome.TIMED_OUT))


func on_wind_up_finished(run: RunState, w: CreatureWindUp) -> void:
	hunt.on_wind_up_finished(run, self, w)


func on_grab_ended(run: RunState, _grab: GrabHold, outcome: GrabHold.Outcome) -> void:
	hunt.on_grab_ended(run, self, outcome)


## Retreat: the arm grinds back into the rock; deaf, silent and playing nothing for 120 s.
func on_retreat_started(run: RunState, _cause: String) -> void:
	hunt.reset(run)
	follower.stop()
	enter(run, &"retreat", "retreat")


func on_retreat_ended(run: RunState, _toward_base: bool) -> void:
	enter(run, &"patrol", "retreat over")


## A relax ends Approach, Listen and Search (a wind-up or pin under way finishes).
func on_relax_started(run: RunState) -> void:
	if state != null and [&"approach", &"listen", &"search"].has(state.name) and not Variants.flag(system.gate.apex_on.call()):
		hunt.end_hunt(run, self, "relax")


func is_rich(run: RunState, t: Vector2i) -> bool:
	if rich_rock.is_valid():
		return Variants.flag(rich_rock.call(t))
	return run.mine != null and run.mine.native.thickness(t) >= 4


func think(run: RunState) -> void:
	_listen(run)
	recent = hearing.take()
	if is_retreating():
		recent.clear()
		return
	for h: TapperHearing.HeardEvent in recent:
		heat.add(run, system.nav, h.apparent, h.energy_np, h.duration_s)
	heat.prune(run, run.crew.count if run.crew != null else 1)
	if TapperHunt.busy(self):
		hunt.tick(run, self, recent)
		follower.tick(run, system.nav, self, Tuning.f(&"tapper.rock_speed"))
		return
	var gate: HuntGate = system.gate
	var apex: Variant = apex_point.call()
	if apex != null:
		var at: Vector2 = apex
		_head_for(run, _rock_near(run, at, 12))
	elif Variants.flag(gate.relax_active.call()):
		_set_state(run, &"patrol", "relax")
		attending = 0
		if not is_rich(run, tile(run)):
			_head_for(run, _nearest_mass(run, []))
	else:
		attending = _highest_pull(run)
		if attending != 0:
			_set_state(run, &"attend", "pull")
			_attend(run)
		else:
			_set_state(run, &"patrol", "nobody attended")
			_patrol(run)
	hunt.consider(run, self, recent)
	follower.tick(run, system.nav, self, Tuning.f(&"tapper.rock_speed"))


func _set_state(run: RunState, name: StringName, why: String) -> void:
	if state == null or state.name != name:
		enter(run, name, why)


func _listen(run: RunState) -> void:
	if tile(run) != _listen_tile:
		_listen_tile = tile(run)
		hearing.listen_from(position(run))


func _patrol(run: RunState) -> void:
	var hot: Variant = heat.hottest()
	if hot != null:
		dwell_until = -1
		var face: Vector2i = hot
		_head_for(run, face)
		return
	# A cold map: rest in rich rock 30-90 s, then move to one of the three nearest masses.
	if follower.status == NavFollower.Status.MOVING:
		return
	if not is_rich(run, tile(run)):
		_head_for(run, _nearest_mass(run, []))
		return
	if dwell_until < 0:
		var dwell: Vector2 = Tuning.range_f(&"tapper.patrol_dwell_s")
		var hz: float = Tuning.f(&"net.tick_hz")
		dwell_until = run.tick + rng.range(roundi(dwell.x * hz), roundi(dwell.y * hz))
	elif run.tick >= dwell_until:
		dwell_until = -1
		var masses: Array[Vector2i] = _masses(run, 3, [tile(run)])
		if not masses.is_empty():
			_head_for(run, masses[rng.range(0, masses.size() - 1)])


## Stays tapper.attend_min_tiles to _max_tiles from the attended miner, aiming at _aim_tiles.
func _attend(run: RunState) -> void:
	var miner: Vector2 = run.registry.get_entity(attending).position
	var d: float = position(run).distance_to(miner)
	if d >= Tuning.f(&"tapper.attend_min_tiles") and d <= Tuning.f(&"tapper.attend_max_tiles"):
		# Inside the band it holds still; it moves only when the miner takes it outside.
		if follower.status == NavFollower.Status.MOVING:
			follower.stop()
		_goal = Vector2i(2147483647, 0)
		return
	var away: Vector2 = (position(run) - miner).normalized() if d > 0.01 else Vector2.RIGHT
	_head_for(run, _rock_near(run, miner + away * Tuning.f(&"tapper.attend_aim_tiles"), 8))


func _head_for(run: RunState, goal: Variant) -> void:
	if goal == null:
		return
	var g: Vector2i = goal
	if g == _goal and follower.status != NavFollower.Status.BLOCKED and follower.status != NavFollower.Status.IDLE:
		return
	_goal = g
	follower.go(run, system.nav, self, g, NavModes.Mode.ROCK)


func _highest_pull(run: RunState) -> int:
	var best: int = 0
	var best_pull: float = Tuning.f(&"pull.threshold_attend")
	for id: int in run.registry.ids():
		if run.registry.get_entity(id).kind != WorldIds.EntityKind.MINER:
			continue
		var pull: float = Variants.number(system.gate.pull_of.call(id))
		if pull >= best_pull and (best == 0 or pull > best_pull):
			best = id
			best_pull = pull
	return best


## The rock tile (one it may stand in) nearest a point, within `radius` tiles; ties tile order.
func _rock_near(run: RunState, p: Vector2, radius: int) -> Variant:
	var c: Vector2i = Vector2i(floori(p.x), floori(p.y))
	var best: Variant = null
	var best_d: float = 1e30
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var t: Vector2i = c + Vector2i(dx, dy)
			if not system.nav.native.passable(NavModes.Mode.ROCK, t):
				continue
			var m: int = run.mine.native.effective_material(t)
			if m == WorldIds.TileMaterial.FLOOR:
				continue
			var d: float = (Vector2(t) + Vector2(0.5, 0.5)).distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = t
	return best


func _nearest_mass(run: RunState, exclude: Array[Vector2i]) -> Variant:
	var masses: Array[Vector2i] = _masses(run, 1, exclude)
	return masses[0] if not masses.is_empty() else null


## Up to `count` rich-rock tiles nearest it, each at least MASS_SPACING_TILES from the others and
## from `exclude` (so they are different masses), within MASS_SEARCH_TILES.
func _masses(run: RunState, count: int, exclude: Array[Vector2i]) -> Array[Vector2i]:
	var here: Vector2 = position(run)
	var c: Vector2i = tile(run)
	var found: Array[Array] = []
	for dy: int in range(-MASS_SEARCH_TILES, MASS_SEARCH_TILES + 1):
		for dx: int in range(-MASS_SEARCH_TILES, MASS_SEARCH_TILES + 1):
			var t: Vector2i = c + Vector2i(dx, dy)
			if is_rich(run, t) and system.nav.native.passable(NavModes.Mode.ROCK, t):
				found.append([(Vector2(t) + Vector2(0.5, 0.5)).distance_squared_to(here), t])
	found.sort_custom(func(a: Array, b: Array) -> bool:
		var da: float = a[0]
		var db: float = b[0]
		var ta: Vector2i = a[1]
		var tb: Vector2i = b[1]
		return da < db or (da == db and (ta.y < tb.y or (ta.y == tb.y and ta.x < tb.x))))
	var out: Array[Vector2i] = []
	for f: Array in found:
		var t: Vector2i = f[1]
		var apart: bool = true
		for other: Vector2i in out + exclude:
			if Vector2(t).distance_to(Vector2(other)) < MASS_SPACING_TILES:
				apart = false
				break
		if apart:
			out.append(t)
			if out.size() >= count:
				break
	return out


## GEN-10's start: a rich-rock tile in rings tapper.start_rings (staged run 1: rings 0-1),
## drawn from the creatures.tapper stream; null when the loaded mine has none.
static func start_tile(run: RunState, rings: Vector2 = Vector2(-1, -1), rich: Callable = Callable()) -> Variant:
	if rings.x < 0:
		rings = Tuning.range_f(&"tapper.start_rings")
	var options: Array[Vector2i] = []
	for raw: Variant in run.mine.native.loaded_cells():
		var cell: Vector2i = raw
		for y: int in WorldIds.CELL_TILES:
			for x: int in WorldIds.CELL_TILES:
				var t: Vector2i = cell * WorldIds.CELL_TILES + Vector2i(x, y)
				var is_rich_tile: bool = Variants.flag(rich.call(t)) if rich.is_valid() else run.mine.native.thickness(t) >= 4
				var ring: int = WorldCoords.ring_of_tile(t)
				if is_rich_tile and ring >= roundi(rings.x) and ring <= roundi(rings.y):
					options.append(t)
	if options.is_empty():
		return null
	options.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var rng: LbRng = run.stream(HashDomain.CREATURES_TAPPER, PackedInt64Array([1]))
	return options[rng.range(0, options.size() - 1)]


## Retreating it goes on retreating; else it patrols (NET-09, Proposed).
func resume_state(saved: StringName) -> StringName:
	return &"retreat" if saved == &"retreat" else &"patrol"
