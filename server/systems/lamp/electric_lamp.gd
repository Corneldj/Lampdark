class_name ElectricLamps
extends SimSystem
## MNR-08 (stage MINERS, after the gauze lamps): the electric hand lamp (Gameplay §4.4, §5.4).
## Rare: radius 6 (lamp.electric_radius, core by light.core_fraction) while on, switched by the
## shutter key after lamp.shutter_time; no flame, so no flame states, no guttering, no naked flame,
## never ignites gas and burns on in blackdamp, warning of nothing. Its battery (lamp.electric_battery,
## 6 minutes) is spent only while on, a tick at a time, and does not read the seam's drink; at empty
## it switches off and gives no light. In a belt slot it is off; on the belt hook during a two-handed
## action it stays as switched at lamp.electric_hook_radius (Proposed 2.5). On the floor it lights
## as it was left.
##
## It is never snuffed and never taken (its source is CANNOT_TAKE; CRT-04's Moth covers it). Each
## Stythe snuff aimed at it drains stythe.electric_snuff_drain_s instead (`drain_source`), never
## below empty, never putting it Out or moving it; one switched off is no target (Proposed). Only
## base camp's battery rack adds battery (`charge`, LFT-01), and anything else calling it fails in
## debug builds. The battery reaches only its holder's Check Lamp, in 5 s steps (Proposed).
## Its state is the item's: "lit" (on) and "battery_ticks". Server-only.

const KIND: String = "electric_lamp"

## uid -> light source id, for the lamps giving light now.
var sources: Dictionary = {}
## uid -> [owner, flags] of its source.
var _source_meta: Dictionary = {}
## miner -> the lamp bits of its last input (switches are edges of the shutter bit).
var _last_bits: Dictionary = {}
## uid -> {due, on}: a switch pressed, landing after lamp.shutter_time.
var _pending: Dictionary = {}
## SND-12: (uid) -> bool, dark this tick in a HELP signal's blink (still on, battery still spent).
var dark_now: Callable = func(_uid: int) -> bool: return false
## Every switch: {tick, uid, on, cause}.
var switches: Array[Dictionary] = []
## Every drain: {tick, uid, seconds, left_ticks}.
var drains: Array[Dictionary] = []
## Every charge: {tick, uid, seconds, left_ticks}.
var charges: Array[Dictionary] = []
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 31


func system_name() -> String:
	return "electric_lamps"


func bind(run: RunState) -> void:
	_run = run
	if run.diff_log != null:
		run.diff_log.items.advances[ItemKinds.Kind.ELECTRIC_LAMP] = advance_lying


static func full_ticks() -> int:
	return roundi(Tuning.f(&"lamp.electric_battery") * Tuning.f(&"net.tick_hz"))


## A new electric lamp (GEN-10's placement, tests): off, its battery full unless given.
static func make(run: RunState, battery: int = -1, on: bool = false) -> Item:
	return run.inventory.world.make(ItemKinds.Kind.ELECTRIC_LAMP, 1,
		{"lit": on, "battery_ticks": battery if battery >= 0 else full_ticks()})


static func is_on(it: Item) -> bool:
	return it != null and it.kind == ItemKinds.Kind.ELECTRIC_LAMP and Variants.flag(it.state.get("lit", false))


static func battery_ticks(it: Item) -> int:
	return int(Variants.number(it.state.get("battery_ticks", full_ticks())))


## CRT-04, CRT-05: never taken.
static func can_be_taken() -> bool:
	return false


## Switches it on or off now; refused on at empty. True when it changed.
func switch(run: RunState, it: Item, on: bool, cause: String = "input") -> bool:
	if on == is_on(it) or (on and battery_ticks(it) <= 0):
		return false
	it.state["lit"] = on
	switches.append({"tick": run.tick, "uid": it.uid, "on": on, "cause": cause})
	_pending.erase(it.uid)
	return true


## CRT-13: a snuff drains `seconds` of battery (never below empty); empty, it goes dark. Returns
## the ticks drained.
func drain(run: RunState, it: Item, seconds: float) -> int:
	var before: int = battery_ticks(it)
	var after: int = maxi(0, before - roundi(seconds * Tuning.f(&"net.tick_hz")))
	it.state["battery_ticks"] = after
	drains.append({"tick": run.tick, "uid": it.uid, "seconds": seconds, "left_ticks": after})
	if after == 0:
		switch(run, it, false, "empty")
	return before - after


## The Stythe's `electric_drain`: the lamp behind a light source drains; false if none is.
func drain_source(run: RunState, source: int, seconds: float) -> bool:
	for raw: Variant in sources.keys():
		if int(Variants.number(sources[raw])) == source:
			var it: Item = _item_of(run, int(Variants.number(raw)))
			if it != null:
				drain(run, it, seconds)
				return true
	return false


## The Stythe's `electric_sources`: every electric lamp giving light now (its source ids).
func lit_sources(_r: RunState) -> Array:
	var out: Array = []
	var uids: Array = sources.keys()
	uids.sort()
	for raw: Variant in uids:
		out.append(sources[raw])
	return out


## LFT-01's battery rack alone adds battery: `seconds`, clamped at full. Anything else is refused
## (an error in debug builds).
func charge(run: RunState, it: Item, seconds: float, by: Object) -> bool:
	if not by is BatteryRack:
		if OS.is_debug_build():
			push_error("ElectricLamps.charge: only base camp's battery rack charges an electric lamp")
		return false
	var after: int = mini(full_ticks(), battery_ticks(it) + roundi(seconds * Tuning.f(&"net.tick_hz")))
	it.state["battery_ticks"] = after
	charges.append({"tick": run.tick, "uid": it.uid, "seconds": seconds, "left_ticks": after})
	return true


## MNR-07's Check Lamp for the electric lamp in `miner`'s hand: its battery in 5 s steps; {} if
## none is there.
func check_record(miner: int) -> Dictionary:
	if _run == null or _run.inventory == null or not _run.inventory.hands.has(miner):
		return {}
	var it: Item = _run.inventory.hands_of(miner).lamp_hand
	if it == null or it.kind != ItemKinds.Kind.ELECTRIC_LAMP:
		return {}
	var step: int = roundi(5.0 * Tuning.f(&"net.tick_hz"))
	return {"battery5": (battery_ticks(it) + step - 1) / step}


## GEN-13: one left on while its cell was gone spent its battery there, and is off once empty.
func advance_lying(state: Dictionary, _at: Vector2, from_tick: int, to_tick: int) -> Variant:
	if not Variants.flag(state.get("lit", false)) or to_tick <= from_tick:
		return state
	var left: int = maxi(0, int(Variants.number(state.get("battery_ticks", full_ticks()))) - (to_tick - from_tick))
	state["battery_ticks"] = left
	if left == 0:
		state["lit"] = false
	return state


func tick(run: RunState) -> void:
	_run = run
	_presses(run)
	var seen: Dictionary = {}
	for place: Dictionary in ItemPlaces.of_kind(run, ItemKinds.Kind.ELECTRIC_LAMP):
		var it: Item = place["item"]
		var where: StringName = StringName(str(place["where"]))
		seen[it.uid] = true
		if _pending.has(it.uid) and run.tick >= int(Variants.number(Variants.dict(_pending[it.uid])["due"])):
			var want: bool = Variants.flag(Variants.dict(_pending[it.uid])["on"])
			_pending.erase(it.uid)
			switch(run, it, want, "input")
		if where == &"slot" and is_on(it):
			switch(run, it, false, "slotted")
		# Each tick it gives light spends one tick of battery: a full one lights exactly its 6 minutes.
		if is_on(it):
			if battery_ticks(it) <= 0:
				switch(run, it, false, "empty")
			else:
				it.state["battery_ticks"] = battery_ticks(it) - 1
		_light(run, it, place)
	for raw: Variant in sources.keys():
		if not seen.has(raw):
			_unlight(run, int(Variants.number(raw)))


## The holders' shutter presses: an edge of the shutter bit switches the lamp in hand after
## lamp.shutter_time (on when the shutter is wanted open).
func _presses(run: RunState) -> void:
	if run.movement == null or run.inventory == null:
		return
	for slot: int in run.movement.miner_slots():
		var m: int = run.movement.miner(slot).entity_id
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null:
			continue
		var bits: int = c.record.desired & InputRecord.DESIRED_LAMP_MASK
		var last: int = int(Variants.number(_last_bits.get(m, bits)))
		_last_bits[m] = bits
		if LampRules.wanted_closed(bits) == LampRules.wanted_closed(last) or not run.inventory.hands.has(m):
			continue
		var it: Item = run.inventory.hands_of(m).lamp_hand
		if it == null or it.kind != ItemKinds.Kind.ELECTRIC_LAMP:
			continue
		if run.miner_state != null and run.miner_state.miner(m) != null and not Variants.flag(run.miner_state.capabilities(m)["lamp"]):
			continue
		var due: int = run.tick + maxi(1, roundi(Tuning.f(&"lamp.shutter_time") * Tuning.f(&"net.tick_hz")))
		_pending[it.uid] = {"due": due, "on": not LampRules.wanted_closed(bits)}


## Its light where it is now: none when off or slotted; the hook's radius on a two-handed belt.
func _light(run: RunState, it: Item, place: Dictionary) -> void:
	var where: StringName = StringName(str(place["where"]))
	if run.light == null or not is_on(it) or where == &"slot":
		_unlight(run, it.uid)
		return
	var holder: int = int(Variants.number(place["holder"]))
	var held: bool = holder != 0
	var r: float = Tuning.f(&"lamp.electric_radius")
	if held and run.inventory.hands_of(holder).hooked:
		r = Tuning.f(&"lamp.electric_hook_radius")
	if Variants.flag(dark_now.call(it.uid)):
		r = 0.0
	var pos: Vector2 = place["position"]
	var owner: int = holder if held else 0
	var flags: int = (LbLightGrid.FLAG_CARRIED if held else LbLightGrid.FLAG_UNHELD) | LbLightGrid.FLAG_CANNOT_TAKE \
		| LbLightGrid.FLAG_NO_FLAME_STATES
	var meta: Array = _source_meta.get(it.uid, [])
	if sources.has(it.uid) and (meta.is_empty() or int(Variants.number(meta[0])) != owner):
		_unlight(run, it.uid)
	if not sources.has(it.uid):
		sources[it.uid] = run.light.grid.add_point(KIND, LbLightGrid.COLOUR_WHITE, owner, flags, r, 1.0, pos, 0)
		_source_meta[it.uid] = [owner, flags]
	else:
		var source: int = int(Variants.number(sources[it.uid]))
		if int(Variants.number(meta[1])) != flags:
			run.light.grid.set_flags(source, flags)
			_source_meta[it.uid] = [owner, flags]
		run.light.grid.update_point(source, pos, r, 1.0)


func _unlight(run: RunState, uid: int) -> void:
	if sources.has(uid) and run.light != null:
		run.light.grid.remove_source(int(Variants.number(sources[uid])))
	sources.erase(uid)
	_source_meta.erase(uid)


func _item_of(run: RunState, uid: int) -> Item:
	for place: Dictionary in ItemPlaces.of_kind(run, ItemKinds.Kind.ELECTRIC_LAMP):
		var it: Item = place["item"]
		if it.uid == uid:
			return it
	return null


func write_state(writer: SimStateWriter) -> void:
	var uids: Array = sources.keys()
	uids.sort()
	writer.put_i64(uids.size())
	for raw: Variant in uids:
		writer.put_i64(int(Variants.number(raw)))
	writer.put_i64(switches.size())
	writer.put_i64(drains.size())
