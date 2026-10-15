class_name Candles
extends ItemFlame
## MNR-09 (stage MINERS, after the lamps): candles (Gameplay §4.5, §5.4). Use on a candle slot lights
## one in items.candle_light_time from any burning flame within touch range: a gauze lamp, another
## candle or a flare, never the electric lamp. It goes to an empty lamp hand, or is set down lit on
## the faced tile (Proposed). It burns items.candle_burn_time as a silent pool of items.candle_radius
## (VIS-02 kind "candle": a flame, held or unheld; the Moth smothers it but never takes it), and
## shows every flame state but the cap (VIS-08). Snuffed (`snuff`, the Stythe through FlameSnuff),
## it keeps its remaining time and lights again from the belt; burnt out, it is gone. A lit candle
## put on the belt goes out (Proposed). Server-only.

const KIND: String = "candle"


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 32


func system_name() -> String:
	return "candles"


func item_kind() -> ItemKinds.Kind:
	return ItemKinds.Kind.CANDLE


func light_kind() -> String:
	return KIND


func colour() -> int:
	return LbLightGrid.COLOUR_AMBER


func extra_flags() -> int:
	return LbLightGrid.FLAG_CANNOT_TAKE


func radius() -> float:
	return Tuning.f(&"items.candle_radius")


func full_burn_ticks() -> int:
	return roundi(Tuning.f(&"items.candle_burn_time") * Tuning.f(&"net.tick_hz"))


func flame_cause() -> String:
	return "lit_candle"


func bind(run: RunState) -> void:
	_run = run
	if run.diff_log != null:
		run.diff_log.items.advances[item_kind()] = advance_lying
	if run.inventory != null:
		run.inventory.use_handlers[ItemKinds.Kind.CANDLE] = func(r: RunState, entity: int, slot: int) -> void:
			var a: TimedAction = light_action(r, entity, slot)
			if a != null:
				r.inventory.start_action(r, a)


func tick(run: RunState) -> void:
	burn(run)


## A lit candle on the belt goes out, keeping its time (Proposed: no flame in a pocket).
func keep_burning(run: RunState, place: Dictionary) -> bool:
	if StringName(str(place["where"])) == &"slot":
		var it: Item = place["item"]
		snuff(run, it, "belt")
		return false
	return true


## Lighting the selected slot's candle: Use held for items.candle_light_time, with a burning flame
## in touch range all the while; none while the free hand is blocked or both hands are full.
func light_action(run: RunState, entity: int, slot: int) -> TimedAction:
	var h: HandsAndBelt = run.inventory.hands_of(entity)
	var from_slot: int = h.selected
	var candle: Item = h.slots[from_slot]
	if candle == null or candle.kind != ItemKinds.Kind.CANDLE or burning(candle):
		return null
	var a: TimedAction = TimedAction.make(entity, &"light_candle", Tuning.f(&"items.candle_light_time"), InputRecord.HOLD_USE)
	a.capability = &"belt"
	a.valid = func() -> bool:
		var me: SimEntity = run.registry.get_entity(entity)
		return h.slots[from_slot] == candle and not h.two_handed and not run.inventory.free_hand_blocked(entity, &"light") \
			and me != null and flame_near(run, me.position, entity)
	a.effect = func() -> void:
		var it: Item = lit_item(run, candle)
		if it == candle:
			h.slots[from_slot] = null
		var tile: Vector2i
		if h.lamp_hand == null:
			h.lamp_hand = it
			tile = run.registry.get_entity(entity).tile()
			run.inventory.world.note(run, &"lit", it, entity)
		else:
			tile = run.inventory.faced_tile(run, entity, slot)
			run.inventory.world.put(run, it, Vector2(tile) + Vector2(0.5, 0.5), &"lit", entity)
		run.inventory.changed.emit(entity)
		lit_at(run, it, tile, "light")
	return a


## A burning flame within vision.touch_range_tiles of `at`: a gauze lamp (never the electric lamp,
## which is not a flame), a candle or a flare. `holder`'s own lamp in hand counts.
func flame_near(run: RunState, at: Vector2, _holder: int) -> bool:
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	if run.lamps != null:
		for uid: int in run.lamps.sorted_uids():
			var l: GauzeLamp = run.lamps.lamps[uid]
			if not l.burning():
				continue
			var e: SimEntity = run.registry.get_entity(l.holder) if l.held() else null
			var p: Vector2 = e.position if e != null else l.at
			if p.distance_to(at) <= reach:
				return true
	if burning_near(run, at, reach):
		return true
	return run.flares != null and run.flares.burning_near(run, at, reach)


## Puts a burning candle out where it is, keeping its remaining time. False if it was not lit.
func snuff(run: RunState, it: Item, cause: String) -> bool:
	if not burning(it):
		return false
	it.state["lit"] = false
	history.append({"tick": run.tick, "uid": it.uid, "what": &"snuffed", "cause": cause})
	_unlight(run, it.uid)
	return true
