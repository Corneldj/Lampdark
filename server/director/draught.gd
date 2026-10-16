class_name Draught
extends SimSystem
## DIR-01: the Draught (Gameplay §10.1–10.2, §A.7; GDD §C.7). A hidden intensity, 0 to
## director.intensity_max, for every conscious miner (Upright, Caught or Grabbed), the operator
## included, kept in thousandths and updated every tick from the true world only. Hired Hands,
## Bess, the unconscious and the dead hold none, and a miner who comes round starts again at 0.
## Each tick, every row applies on its own and they sum, then the value is held to its range:
## - the intake's events (IntensityIntake): grabs, traps, falls heard, blasts;
## - a real creature coming into sight within director.creature_seen_range_tiles: a shape, the
##   Stythe's bite, the Tapper's arm, a lit Moth; the same one again after
##   director.creature_reseen_after_s unseen;
## - alone in the dark: the miner's tile below director.dark_light_below, no lit lamp in hand and no
##   conscious human within director.dark_teammate_range_tiles by path; up to
##   director.dark_gain_cap, renewed in light of director.lit_at and when a relax begins;
## - drains: lit with no creature in sight, in a relax, inside a shut base camp.
## It runs the cycle (DraughtCycle) that tells creatures when they may choose to hunt (CRT-01's hunt
## gate). It never spawns, moves, steers or strengthens a creature and never forces a peak. Nothing
## outside the server sees it: no client, no meter, no creature (the gate reads only the phase).
## Stage 16 (RECORD), after perception (stage 12), the rescue systems (stage 9) and MNR-03's life
## changes (16/0): creatures read the phase the next tick, a 50 ms lag. Server-only.

## Stand-in providers for scenarios (the defaults read the run): (tile) -> float light, 0 to 1;
## (miner) -> bool, a lit lamp in hand (open and burning, or an electric lamp on).
var light_at: Callable = Callable()
var lit_lamp_in_hand: Callable = Callable()

## The tick's numbers, read from tuning once a tick (thousandths of intensity, ticks, tiles).
class Params:
	extends RefCounted
	var hz: float = 20.0
	var max_value: int = 100000
	var lit_at: float = 0.30
	var lit_drain: int = 0
	var relax_drain: int = 0
	var home_drain: int = 0
	var seen_reach: float = 6.0
	var seen_gain: int = 0
	var reseen_ticks: int = 0
	var dark_below: float = 0.12
	var dark_gain: int = 0
	var dark_cap: int = 0
	var company_reach: float = 8.0
	var threshold: int = 70000
	var light_scale: float = 1000.0

	static func read() -> Params:
		var p: Params = Params.new()
		p.hz = Tuning.f(&"net.tick_hz")
		p.max_value = roundi(Tuning.f(&"director.intensity_max") * 1000.0)
		p.lit_at = Tuning.f(&"director.lit_at")
		p.lit_drain = roundi(Tuning.f(&"director.lit_drain_per_s") * 1000.0 / p.hz)
		p.relax_drain = roundi(Tuning.f(&"director.relax_drain_per_s") * 1000.0 / p.hz)
		p.home_drain = roundi(Tuning.f(&"director.home_drain_per_s") * 1000.0 / p.hz)
		p.seen_reach = Tuning.f(&"director.creature_seen_range_tiles")
		p.seen_gain = roundi(Tuning.f(&"director.gain_creature_seen") * 1000.0)
		p.reseen_ticks = roundi(Tuning.f(&"director.creature_reseen_after_s") * p.hz)
		p.dark_below = Tuning.f(&"director.dark_light_below")
		p.dark_gain = roundi(Tuning.f(&"director.dark_gain_per_s") * 1000.0 / p.hz)
		p.dark_cap = roundi(Tuning.f(&"director.dark_gain_cap") * 1000.0)
		p.company_reach = Tuning.f(&"director.dark_teammate_range_tiles")
		p.threshold = roundi(Tuning.f(&"director.peak_threshold") * 1000.0)
		p.light_scale = float(Tuning.i(&"light.value_scale"))
		return p

var intake: IntensityIntake = IntensityIntake.new()
var cycle: DraughtCycle = DraughtCycle.new()
## Tracked miner -> IntensityIntake.Record.
var records: Dictionary = {}
## The miners tracked last tick, to see a change.
var _tracked: Array[int] = []
## The tick's numbers, read again only when the tuning set changes.
var _params: Params = null
var _params_of: TuningSet = null
## Company by path: Vector4i(tile a, tile b) -> within reach; cleared when the mine changes.
var _paths: Dictionary = {}
var _run: RunState = null
var _footprints: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.RECORD


func order() -> int:
	return 25 # after the crew census (16/10) and the alone watch (16/12)


func system_name() -> String:
	return "Draught"


## Hooks the true world's events and the hunt gate. The run's systems must exist already.
func bind(run: RunState) -> void:
	_run = run
	cycle.rng = run.stream(HashDomain.DIRECTOR_PEAK_HOLD, PackedInt64Array())
	cycle.relax_begun.connect(_on_relax_begun)
	if run.holds != null:
		var on_grab: Callable = func(grab_id: int, _kind: GrabHold.Kind, _creature: int, victim: int) -> void:
			intake.grabbed(victim, grab_id)
		var on_caught: Callable = func(trap_id: int, _kind: CaughtHold.Kind, victim: int) -> void:
			intake.caught(victim, trap_id)
		run.holds.grab_begun.connect(on_grab)
		run.holds.caught_begun.connect(on_caught)
	if run.fall_audio != null:
		run.fall_audio.fall_heard.connect(func(miner: int, fall_id: int) -> void: intake.fall_heard(miner, fall_id))
	if run.creatures != null:
		run.creatures.gate.build_active = func() -> bool: return cycle.in_build()
		run.creatures.gate.relax_active = func() -> bool: return cycle.in_relax()
	if run.mine != null:
		run.mine.native.tiles_changed.connect(_forget_paths)
		run.mine.native.cell_loaded.connect(_forget_paths)
		run.mine.native.cell_unloading.connect(_forget_paths)
	_load_footprints()


## A relax begins: being alone in the dark renews for everyone.
func _on_relax_begun(_length: int, _ring: int) -> void:
	for raw: Variant in records.keys():
		var r: IntensityIntake.Record = records[raw]
		r.dark = 0


## HAZ-04: a firedamp explosion at `tile`.
func on_blast(tile: Vector2i, blast_id: int) -> void:
	intake.blast(tile, blast_id)


func in_relax() -> bool:
	return cycle.in_relax()


## A miner's intensity (0 to director.intensity_max), or -1 if they are not tracked.
func intensity_of(miner: int) -> float:
	var r: IntensityIntake.Record = records.get(miner, null)
	return r.value / 1000.0 if r != null else -1.0


## FND-08's set_intensity: a tracked miner's value, held to its range. False if not tracked.
func set_intensity(miner: int, value: float) -> bool:
	var r: IntensityIntake.Record = records.get(miner, null)
	if r == null:
		return false
	r.value = clampi(roundi(value * 1000.0), 0, _max())
	return true


## The miners tracked now, ascending: conscious and not Hand-driven.
func tracked_miners(run: RunState) -> Array[int]:
	var out: Array[int] = []
	var all: Array[int] = run.crew.miners(run) if run.crew != null else _miners(run)
	for e: int in all:
		if not CrewCensus.is_conscious(run, e):
			continue
		if run.crew != null and Variants.flag(run.crew.is_hand_driven.call(e)):
			continue
		out.append(e)
	return out


func tick(run: RunState) -> void:
	_run = run
	var tracked: Array[int] = tracked_miners(run)
	if tracked != _tracked or records.size() != tracked.size():
		var now: Dictionary = {}
		for e: int in tracked:
			now[e] = records[e] if records.has(e) else IntensityIntake.Record.new()
		records = now # whoever stopped being tracked starts again at 0
		_tracked = tracked
	intake.apply(run, records)
	if _params == null or _params_of != Tuning.current:
		_params = Params.read()
		_params_of = Tuning.current
	var p: Params = _params
	var slots: Dictionary = run.vision.slots_by_entity() if run.vision != null else {}
	var relaxing: bool = cycle.in_relax()
	var top: int = -1
	var who: int = 0
	for e: int in tracked:
		var r: IntensityIntake.Record = records[e]
		var me: SimEntity = run.registry.get_entity(e)
		var light: float = _light(run, p, WorldCoords.tile_at(me.position))
		var in_sight: bool = _sightings(run, p, int(Variants.number(slots.get(e, -1))), me, r)
		_dark(run, p, e, me, r, light, tracked)
		if light >= p.lit_at:
			r.dark = 0
			if not in_sight:
				r.value -= p.lit_drain
		if relaxing:
			r.value -= p.relax_drain
		if run.crew != null and Variants.flag(run.crew.is_sealed_inside.call(e)):
			r.value -= p.home_drain
		r.value = clampi(r.value, 0, p.max_value)
		if r.value > top:
			top = r.value
			who = e
	cycle.step(run, top, who, p.threshold)


## Sightings: +director.gain_creature_seen as a real creature comes into the miner's seen set within
## reach, and for the same one after director.creature_reseen_after_s unseen. True if any real
## creature is in sight at all, at any distance (the lit drain waits for none). Each creature is
## asked of VIS-03 by what of it can be seen: a Moth or the Stythe itself (asleep or awake), the
## Tapper only by its arm (it lives in the rock), and the Stythe's bite.
func _sightings(run: RunState, p: Params, slot: int, me: SimEntity, r: IntensityIntake.Record) -> bool:
	if run.vision == null or run.creatures == null or slot < 0:
		return false
	var in_sight: bool = false
	var near: Array[int] = []
	for c: Creature in run.creatures.creatures:
		var shown: int = c.entity_id
		if c is Tapper:
			var hunt: TapperHunt = (c as Tapper).hunt
			shown = hunt.arm if hunt != null else 0
		if shown == 0 or run.vision.native.sees_entity(slot, shown) == 0:
			continue
		in_sight = true
		var it: SimEntity = run.registry.get_entity(shown)
		if it != null and _nearest_tile_distance(me.position, it) <= p.seen_reach and not near.has(c.entity_id):
			near.append(c.entity_id)
	# The Stythe's bite: a tile the miner would have seen, taken while its tell plays.
	if not run.vision.bite_now.is_empty():
		var bite: float = run.vision.native.bite_seen_at(slot)
		var stythe: Creature = run.creatures.creature_of_kind(WorldIds.EntityKind.STYTHE) if bite >= 0.0 else null
		if stythe != null:
			in_sight = true
			if bite <= p.seen_reach and not near.has(stythe.entity_id):
				near.append(stythe.entity_id)
	near.sort()
	for creature: int in near:
		var last: int = int(Variants.number(r.last_seen.get(creature, -1)))
		if last < 0 or run.tick - last - 1 >= p.reseen_ticks:
			r.value += p.seen_gain
		r.last_seen[creature] = run.tick
	return in_sight


## Straight-line tiles from `from` to the centre of the nearest tile of the entity's footprint
## (VIS-03's square: a Moth's is 2 tiles a side).
func _nearest_tile_distance(from: Vector2, e: SimEntity) -> float:
	var f: int = int(Variants.number(_footprints.get(int(e.kind), 1)))
	var half: float = f * 0.5
	var lo: Vector2i = Vector2i(floori(e.position.x - half + 0.5), floori(e.position.y - half + 0.5))
	var best: float = INF
	for y: int in f:
		for x: int in f:
			best = minf(best, from.distance_to(Vector2(lo + Vector2i(x, y)) + Vector2(0.5, 0.5)))
	return best


## Alone in the dark with no lamp: +director.dark_gain_per_s up to director.dark_gain_cap.
func _dark(run: RunState, p: Params, miner: int, me: SimEntity, r: IntensityIntake.Record, light: float,
		tracked: Array[int]) -> void:
	if r.dark >= p.dark_cap or light >= p.dark_below:
		return
	if _lamp_lit(run, miner) or _has_company(run, p, miner, me, tracked):
		return
	var gain: int = mini(p.dark_gain, p.dark_cap - r.dark)
	r.dark += gain
	r.value += gain


## A conscious human teammate (Hands never count) within director.dark_teammate_range_tiles by path.
## A pair of tiles keeps its answer until the mine's tiles or cells change.
func _has_company(run: RunState, p: Params, miner: int, me: SimEntity, tracked: Array[int]) -> bool:
	var reach: float = p.company_reach
	var from: Vector2i = WorldCoords.tile_at(me.position)
	for other: int in tracked:
		if other == miner:
			continue
		var it: SimEntity = run.registry.get_entity(other)
		if it == null or me.position.distance_to(it.position) > reach + 1.5:
			continue # a walk is never shorter than the straight line (tile centre to centre)
		if run.mine == null:
			return true
		var to: Vector2i = WorldCoords.tile_at(it.position)
		var key: Vector4i = Vector4i(from.x, from.y, to.x, to.y) if from < to else Vector4i(to.x, to.y, from.x, from.y)
		if not _paths.has(key):
			if _paths.size() >= 4096:
				_paths.clear()
			var path: Mine.PathAnswer = run.mine.path_distance(from, to, reach)
			_paths[key] = path.distance >= 0.0 and path.distance <= reach
		if Variants.flag(_paths[key]):
			return true
	return false


func _forget_paths(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	_paths.clear()


## The light at a tile, 0 to 1 (VIS-02's grid; a scenario's stand-in when set).
func _light(run: RunState, p: Params, tile: Vector2i) -> float:
	if light_at.is_valid():
		return float(Variants.number(light_at.call(tile)))
	return run.light.grid.value(tile) / p.light_scale if run.light != null else 1.0


## A lit lamp in hand: a gauze lamp open and burning (shuttered, slotted or hooked is none), or an
## electric lamp switched on.
func _lamp_lit(run: RunState, miner: int) -> bool:
	if lit_lamp_in_hand.is_valid():
		return Variants.flag(lit_lamp_in_hand.call(miner))
	if run.lamps != null:
		var lamp: GauzeLamp = run.lamps.lamp_in_hand(miner)
		if lamp != null and lamp.state() == GauzeLamp.State.OPEN:
			return true
	if run.inventory != null and run.inventory.hands.has(miner):
		var h: HandsAndBelt = run.inventory.hands[miner]
		return ElectricLamps.is_on(h.lamp_hand)
	return false


func _max() -> int:
	return roundi(Tuning.f(&"director.intensity_max") * 1000.0)


static func _miners(run: RunState) -> Array[int]:
	var out: Array[int] = []
	for id: int in run.registry.ids():
		if run.registry.get_entity(id).kind == WorldIds.EntityKind.MINER:
			out.append(id)
	return out


func _load_footprints() -> void:
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/world/perception_classes.json")))
	var classes: Dictionary = Variants.dict(doc.get("classes", {}))
	for name: Variant in classes.keys():
		var kind: int = WorldIds.EntityKind.get(str(name), -1)
		if kind >= 0:
			_footprints[kind] = int(Variants.number(Variants.dict(classes[name]).get("footprint", 1)))


func write_state(writer: SimStateWriter) -> void:
	cycle.write_state(writer)
	var keys: Array = records.keys()
	keys.sort()
	writer.put_i64(keys.size())
	for raw: Variant in keys:
		writer.put_i64(int(Variants.number(raw)))
		var r: IntensityIntake.Record = records[raw]
		r.write_state(writer)


## NET-09: values, accumulators, the once-only sets and the cycle (the peak stream's state rides
## with the run's streams).
func save_state() -> Dictionary:
	var miners: Dictionary = {}
	for raw: Variant in records.keys():
		var r: IntensityIntake.Record = records[raw]
		miners[str(raw)] = r.save()
	return {"miners": miners, "cycle": cycle.save()}


func load_state(_r: RunState, state: Dictionary) -> void:
	records.clear()
	var miners: Dictionary = Variants.dict(state.get("miners", {}))
	for raw: Variant in miners.keys():
		records[int(str(raw))] = IntensityIntake.Record.from(Variants.dict(miners[raw]))
	cycle.load(Variants.dict(state.get("cycle", {})))
