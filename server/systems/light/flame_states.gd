class_name FlameStates
extends SimSystem
## VIS-08 (Gameplay §5.7; stage LIGHT_PASS_2, just before VIS-02's second pass): every flame's real
## states each tick, from cause predicates only. Trembling: a creature whose tell trembles flames
## (the Moth awake or stirring) within its tell reach. Guttering: one whose tell gutters them (the
## Stythe in its active states, CRT-14) within its reach. Blue cap: a gauze flame on a firedamp tile
## (HAZ-04). Shrinking: blackdamp exposure (HAZ-05). The flare-up: set by HAZ-04 for its second.
## Reaches are straight-line (Proposed). Only guttering (x light.gutter_radius_mult) and shrinking
## (1 - light.shrink_rate_per_s x t) change the grid. Electric light, gob fires, flares, egg-glow,
## the flash and the emergency lamps are not flames here (VIS-02's FLAME / NO_FLAME_STATES flags).
## Every change is logged with its cause (the Inquiry, the soak's no-state-without-cause check).
## Nothing in the illusion stage or client prediction may reach this (check_module_deps).

signal changed(source: int, state: int, on: bool, cause: String)

## HAZ-04: a firedamp tile (the blue cap).
var firedamp_at: Callable = func(_tile: Vector2i) -> bool: return false
## HAZ-05: seconds a flame (source id, tile) has spent in blackdamp, 0 when outside it.
var blackdamp_s: Callable = func(_source: int, _tile: Vector2i) -> float: return 0.0
## Extra cause providers (CRT-14's Stythe until it is a Creature here, and tests):
## (run) -> Array of {state: FlameFlags bit, point: Vector2, reach: float, cause: String}.
var causes: Array[Callable] = []
## source -> its state bits now.
var flags: Dictionary = {}
## source -> the cause of each set bit: {bit: cause}.
var cause_of: Dictionary = {}
## Every change: {tick, source, owner, entity, state, on, cause}.
var changes: Array[Dictionary] = []
## Identity bits per entity (a miner's lamp-hand flame, a lamp lying or hanging), for NET-04.
var entity_bits: Dictionary = {}
## The owner's own-block bits per miner: their lamp hand's flame, or for a shuttered or slotted lamp
## only GUTTER (the sputter).
var own: Dictionary = {}
var _flare_until: Dictionary = {}
var _mult: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.LIGHT_PASS_2


func order() -> int:
	return 5


func system_name() -> String:
	return "flame_states"


## HAZ-04: a naked flame entering firedamp's edge flares tall and blue for hazards.firedamp_flare_up_s.
func set_flare_up(run: RunState, source: int, seconds: float) -> void:
	_flare_until[source] = run.tick + maxi(1, roundi(seconds * Tuning.f(&"net.tick_hz")))


func flags_of(source: int) -> int:
	return int(Variants.number(flags.get(source, 0)))


func tick(run: RunState) -> void:
	if run.light == null:
		return
	var grid: LbLightGrid = run.light.grid
	var tells: Array[Dictionary] = _tells(run)
	var ids: Array = Array(grid.flame_sources(Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)))
	ids.sort()
	var seen: Dictionary = {}
	for raw: Variant in ids:
		var id: int = int(Variants.number(raw))
		var info: Dictionary = grid.source_info(id)
		if info.is_empty() or (int(Variants.number(info.get("flags", 0))) & LbLightGrid.FLAG_NO_FLAME_STATES) != 0:
			continue
		seen[id] = true
		var at: Vector2 = info.get("position", Vector2.ZERO)
		var tile: Vector2i = Vector2i(floori(at.x), floori(at.y))
		var bits: int = 0
		var why: Dictionary = {}
		for t: Dictionary in tells:
			var bit: int = int(Variants.number(t["state"]))
			var point: Vector2 = t["point"]
			if (bits & bit) == 0 and at.distance_to(point) <= float(Variants.number(t["reach"])) + 1e-9:
				bits |= bit
				why[bit] = str(t["cause"])
		if str(info.get("kind", "")) == LampSystem.KIND and Variants.flag(firedamp_at.call(tile)):
			bits |= FlameFlags.CAP
			why[FlameFlags.CAP] = "firedamp"
		var exposure: float = float(Variants.number(blackdamp_s.call(id, tile)))
		if exposure > 0.0:
			bits |= FlameFlags.SHRINK
			why[FlameFlags.SHRINK] = "blackdamp"
		if run.tick < int(Variants.number(_flare_until.get(id, -1))):
			bits |= FlameFlags.FLARE_UP
			why[FlameFlags.FLARE_UP] = "firedamp_edge"
		_apply_bits(run, id, info, bits, why)
		var mult: float = (Tuning.f(&"light.gutter_radius_mult") if (bits & FlameFlags.GUTTER) != 0 else 1.0) \
			* maxf(0.0, 1.0 - Tuning.f(&"light.shrink_rate_per_s") * exposure)
		if not is_equal_approx(mult, float(Variants.number(_mult.get(id, 1.0)))):
			_mult[id] = mult
			grid.set_radius_modifier(id, mult, ", ".join(FlameFlags.names(bits & (FlameFlags.GUTTER | FlameFlags.SHRINK))))
	for raw: Variant in flags.keys().duplicate():
		if not seen.has(raw):
			flags.erase(raw)
			cause_of.erase(raw)
			_mult.erase(raw)
	for raw: Variant in _flare_until.keys().duplicate():
		if int(Variants.number(_flare_until[raw])) <= run.tick:
			_flare_until.erase(raw)
	_publish(run)


func _apply_bits(run: RunState, id: int, info: Dictionary, bits: int, why: Dictionary) -> void:
	var was: int = flags_of(id)
	if was == bits:
		cause_of[id] = why
		return
	var owner: int = int(Variants.number(info.get("owner", 0)))
	for raw: Variant in FlameFlags.NAMES.keys():
		var bit: int = int(Variants.number(raw))
		if (was & bit) == (bits & bit):
			continue
		var on: bool = (bits & bit) != 0
		var cause: String = str(why.get(bit, "")) if on else str(Variants.dict(cause_of.get(id, {})).get(bit, ""))
		changes.append({"tick": run.tick, "source": id, "owner": owner, "state": FlameFlags.NAMES[raw], "on": on, "cause": cause})
		changed.emit(id, bit, on, cause)
	flags[id] = bits
	cause_of[id] = why


## The causes this tick: creatures whose tell moves flames, then the extra providers.
func _tells(run: RunState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if run.creatures != null:
		for c: Creature in run.creatures.creatures:
			var bit: int = c.flame_tell()
			if bit != 0:
				out.append({"state": bit, "point": c.position(run), "reach": c.flame_tell_reach(), "cause": "%s#%d" % [c.kind_name(), c.entity_id]})
	for p: Callable in causes:
		for raw: Variant in Variants.array(p.call(run)):
			out.append(Variants.dict(raw))
	return out


## Which entity shows each flame's states, and what each owner gets for their own flame.
func _publish(run: RunState) -> void:
	entity_bits.clear()
	own.clear()
	if run.lamps == null:
		return
	var item_entity: Dictionary = {}
	if run.inventory != null:
		for raw: Variant in run.inventory.world.items.keys():
			var it: Item = run.inventory.world.items[raw]
			item_entity[it.uid] = int(Variants.number(raw))
	for uid: int in run.lamps.sorted_uids():
		var l: GauzeLamp = run.lamps.lamps[uid]
		if l.source == 0 or not flags.has(l.source):
			continue
		var bits: int = flags_of(l.source)
		var hidden: bool = l.shutter_closed or l.place == LampRules.Place.SLOT
		match l.place:
			LampRules.Place.HAND, LampRules.Place.HOOK, LampRules.Place.SLOT:
				if l.holder == 0:
					continue
				# Others see an open flame's states; a shuttered or slotted one reacts unseen.
				if not hidden and l.place != LampRules.Place.SLOT:
					entity_bits[l.holder] = int(Variants.number(entity_bits.get(l.holder, 0))) | bits
				var mine: int = (bits & FlameFlags.GUTTER) if hidden else bits
				own[l.holder] = int(Variants.number(own.get(l.holder, 0))) | mine
			_:
				var e: int = int(Variants.number(item_entity.get(uid, 0)))
				if e != 0 and not hidden:
					entity_bits[e] = bits
	# Flames that are not gauze lamps (candles, MNR-09) show on their owner.
	for raw: Variant in flags.keys():
		var id: int = int(Variants.number(raw))
		var info: Dictionary = run.light.grid.source_info(id)
		if str(info.get("kind", "")) == LampSystem.KIND:
			continue
		var owner: int = int(Variants.number(info.get("owner", 0)))
		if owner != 0:
			entity_bits[owner] = int(Variants.number(entity_bits.get(owner, 0))) | flags_of(id)
			own[owner] = int(Variants.number(own.get(owner, 0))) | flags_of(id)


func entity_flags(entity: int) -> int:
	return int(Variants.number(entity_bits.get(entity, 0)))


func own_flags(miner: int) -> int:
	return int(Variants.number(own.get(miner, 0)))


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = flags.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(flags_of(int(Variants.number(raw))))
	writer.put_i64(changes.size())
