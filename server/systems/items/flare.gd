class_name Flares
extends ItemFlame
## MNR-09 (stage MINERS, after the candles): magnesium flares (Gameplay §4.5, §5.4). Use on a flare
## slot strikes one in items.flare_strike_time (a timed use: let go early and nothing is spent), with
## a flare_strike event (16 np) at the striker. It is held in the free hand (which it then blocks)
## and burns items.flare_burn_time at items.flare_radius, then is gone: VIS-02 kind "flare", an
## open flame with no flame states and beyond the Stythe's snuff (only firedamp's flare-up puts it
## out, HAZ-04). Set down (MNR-04's set-down) it lies burning on the faced tile; its holder falling
## or grabbed drops it burning where they are (Proposed). While it burns every awake Moth has it as
## a beacon (CRT-04: seen from moth.flare_sight_tiles); CRT-03 wakes on the source's appearance.
## What each creature does about it is the creature tickets'. Server-only.

const KIND: String = "flare"
## Every drop: {tick, uid, miner, why}.
var drops: Array[Dictionary] = []


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 33


func system_name() -> String:
	return "flares"


func item_kind() -> ItemKinds.Kind:
	return ItemKinds.Kind.FLARE


func light_kind() -> String:
	return KIND


func colour() -> int:
	return LbLightGrid.COLOUR_PALE_AMBER


func extra_flags() -> int:
	return LbLightGrid.FLAG_NO_FLAME_STATES | LbLightGrid.FLAG_BEYOND_SNUFF


func radius() -> float:
	return Tuning.f(&"items.flare_radius")


func full_burn_ticks() -> int:
	return roundi(Tuning.f(&"items.flare_burn_time") * Tuning.f(&"net.tick_hz"))


func flame_cause() -> String:
	return "burning_flare"


func bind(run: RunState) -> void:
	_run = run
	if run.inventory != null:
		run.inventory.use_handlers[ItemKinds.Kind.FLARE] = func(r: RunState, entity: int, slot: int) -> void:
			var a: TimedAction = strike_action(r, entity, slot)
			if a != null:
				r.inventory.start_action(r, a)
	if run.falls != null:
		run.falls.fell.connect(func(record: Dictionary) -> void: drop_held(run, int(Variants.number(record.get("miner_id", 0))), "fell"))
	if run.holds != null:
		run.holds.grab_begun.connect(func(_id: int, _kind: GrabHold.Kind, _creature: int, victim: int) -> void:
			drop_held(run, victim, "grabbed"))


func tick(run: RunState) -> void:
	burn(run)
	_beacons(run)


## Striking the selected slot's flare: Use held for items.flare_strike_time with the free hand
## empty (no revolver, can or other flare in it) and a hand to strike with.
func strike_action(run: RunState, entity: int, _slot: int) -> TimedAction:
	var h: HandsAndBelt = run.inventory.hands_of(entity)
	var from_slot: int = h.selected
	var flare: Item = h.slots[from_slot]
	if flare == null or flare.kind != ItemKinds.Kind.FLARE or burning(flare):
		return null
	var a: TimedAction = TimedAction.make(entity, &"strike_flare", Tuning.f(&"items.flare_strike_time"), InputRecord.HOLD_USE)
	a.capability = &"belt"
	a.valid = func() -> bool:
		return h.slots[from_slot] == flare and h.free_hand == null and not h.two_handed and not run.inventory.free_hand_blocked(entity, &"strike")
	a.effect = func() -> void:
		var it: Item = lit_item(run, flare)
		if it == flare:
			h.slots[from_slot] = null
		h.free_hand = it
		run.inventory.world.note(run, &"struck", it, entity)
		run.inventory.changed.emit(entity)
		var tile: Vector2i = run.registry.get_entity(entity).tile()
		if run.noise != null:
			run.noise.emit(NoiseTypes.Type.FLARE_STRIKE, tile, {"source": entity})
		lit_at(run, it, tile, "strike")
	return a


## A burning flare in `miner`'s hands drops burning where they are (a fall, a grab).
func drop_held(run: RunState, miner: int, why: String) -> void:
	if run.inventory == null or not run.inventory.hands.has(miner):
		return
	for place: Dictionary in ItemPlaces.of_kind(run, ItemKinds.Kind.FLARE):
		if int(Variants.number(place["holder"])) != miner or StringName(str(place["where"])) == &"slot":
			continue
		var it: Item = place["item"]
		if burning(it):
			ItemPlaces.drop_at_holder(run, place, &"dropped")
			drops.append({"tick": run.tick, "uid": it.uid, "miner": miner, "why": why})


## The Stythe's snuff and any other is refused: a flare is beyond it (§7.4).
func snuff(_r: RunState, _it: Item, _cause: String) -> bool:
	return false


## CRT-04: every awake Moth sees a burning flare from moth.flare_sight_tiles.
func _beacons(run: RunState) -> void:
	if run.creatures == null or sources.is_empty():
		return
	for place: Dictionary in ItemPlaces.of_kind(run, ItemKinds.Kind.FLARE):
		var it: Item = place["item"]
		var source: int = source_of(it)
		if source == 0:
			continue
		var until: int = run.tick + int(Variants.number(it.state.get("burn_ticks", 0))) + 1
		for c: Creature in run.creatures.creatures:
			var moth: Moth = c as Moth
			if moth != null:
				moth.awake.perception.beacons[source] = {"kind": &"flare", "source": source, "until": until}
