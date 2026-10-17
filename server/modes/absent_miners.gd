class_name AbsentMiners
extends SimSystem
## MOD-05 (Gameplay §13.11, §3.5, A.10): a knocked-off run resumes with any subset of its crew. When it
## begins again, an absent player's conscious miner waits in base camp, out of the crew count and out
## of reach: off the map (Proposed: no entity in the world, so no creature, light or Road Graph
## reaches it), its lamp and belt laid on the bench for the crew. An absent player's unconscious or
## dead miner lies where it is, a body like any other. Every personal timer of a waiting miner (Hurt,
## rock-touched, and those `keepers` register: CRT-06's egg clock, HAZ-06's soot-lung) stays frozen
## until they return; everything else runs on with the run. A player who comes back has their miner
## stand up in base camp with an empty belt and no lamp, its marks as they were. Waiting miners are
## kept through every later save. An abnormal end's resume keeps NET-11's rule instead: a Hand
## holds each absent miner where it stands. Server-only.

## Absent players' miners waiting off the map: identity -> {slot, overlays, kept, since}.
var waiting: Dictionary = {}
## CRT-06, HAZ-06: [name, export (run, entity) -> Variant, import (run, entity, data, frozen_ticks)]
## for each personal timer a waiting miner keeps.
var keepers: Array[Array] = []
## Every miner parked and returned: {tick, identity, slot, what}.
var history: Array[Dictionary] = []
var _net: ServerNet = null


func stage() -> int:
	return StageTable.Stage.INPUTS


func order() -> int:
	return 7


func system_name() -> String:
	return "absent_miners"


## The waiting list is kept in every save; who waits shows in the registry itself (hashed).
func hashed() -> bool:
	return false


func bind(run: RunState, net: ServerNet) -> void:
	_net = net
	net.rejoined.connect(func(slot: int, identity: String) -> void: on_rejoined(run, slot, identity))


func register_keeper(name: String, export_fn: Callable, import_fn: Callable) -> void:
	keepers.append([name, export_fn, import_fn])


## As a knocked-off run begins again: every conscious miner whose player is not back waits off the
## map. Returns how many.
func park_absent(run: RunState) -> int:
	var n: int = 0
	var identities: Array = _net.seats.seats.keys()
	identities.sort()
	for raw: Variant in identities:
		var seat: SeatTable.Seat = _net.seats.seats[raw]
		if seat.state != SeatTable.State.RESERVED or seat.miner == 0 or not run.registry.has(seat.miner):
			continue
		if run.miner_state != null and run.miner_state.miner(seat.miner) != null \
				and run.miner_state.life(seat.miner) >= MinerTransitions.Life.UNCONSCIOUS:
			history.append({"tick": run.tick, "identity": str(raw), "slot": seat.slot, "what": "lies where it is"})
			continue
		park(run, str(raw), seat)
		n += 1
	return n


## One absent player's conscious miner: its lamp and belt to the bench, its load set down, its timers
## kept, then out of the world.
func park(run: RunState, identity: String, seat: SeatTable.Seat) -> void:
	var m: int = seat.miner
	if run.hands != null and run.hands.is_hand_driven(m):
		run.hands.hand_back(run, m)  # NET-11's restore held it as dropped; it waits instead
	if run.carry != null and run.carry.is_carrying(m):
		run.carry.set_down(run, m, FiremanCarry.DISCONNECTED)
	if run.loads != null and run.loads.carrying(m):
		run.loads.set_down(run, m, LoadCarry.DISCONNECTED)
	if run.inventory != null and run.inventory.actions.has(m):
		var a: TimedAction = run.inventory.actions[m]
		run.inventory.actions.erase(m)
		a.cancel(TimedAction.STARVED)
	_lay_on_bench(run, m)
	var kept: Dictionary = {}
	for k: Array in keepers:
		var export_fn: Callable = k[1]
		kept[str(k[0])] = export_fn.call(run, m)
	var overlays: Dictionary = run.miner_state.export_overlays(m, run.tick) if run.miner_state != null else {}
	if run.movement != null:
		run.movement.remove_miner(seat.slot)
	if run.vision != null:
		run.vision.unwatch(seat.slot)
	if run.miner_state != null:
		run.miner_state.remove_miner(m)
	if run.inventory != null:
		run.inventory.hands.erase(m)
	run.registry.destroy(m)
	waiting[identity] = {"slot": seat.slot, "overlays": overlays, "kept": kept, "since": run.tick}
	history.append({"tick": run.tick, "identity": identity, "slot": seat.slot, "what": "waits off the map"})
	Log.info("absent: %s's miner waits in base camp (slot %d), its lamp and belt on the bench" % [identity, seat.slot])


## NET-11's rejoin: a waiting miner stands up in base camp, belt empty, no lamp, its marks and frozen
## timers as they were.
func on_rejoined(run: RunState, slot: int, identity: String) -> void:
	if not waiting.has(identity):
		return
	var w: Dictionary = waiting[identity]
	waiting.erase(identity)
	var tile: Vector2i = _free_tile(run)
	var e: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(tile) + Vector2(0.5, 0.5))
	if run.movement != null:
		run.movement.add_miner(slot, e.id, e.position, 0)
	if run.miner_state != null:
		run.miner_state.add_miner(e.id, slot)
		run.miner_state.import_overlays(e.id, Variants.dict(w.get("overlays", {})), run.tick)
	if run.vision != null:
		run.vision.watch(slot, e.id, 0)
	if run.inventory != null:
		var seated: CrewSeating.Seat = _net.crew.of_slot(slot)
		run.inventory.hands_of(e.id, seated.lamp_number if seated != null else 0)
	var frozen: int = run.tick - int(Variants.number(w.get("since", run.tick)))
	var kept: Dictionary = Variants.dict(w.get("kept", {}))
	for k: Array in keepers:
		var import_fn: Callable = k[2]
		if kept.has(str(k[0])):
			import_fn.call(run, e.id, kept[str(k[0])], frozen)
	var seat: SeatTable.Seat = _net.seats.seat_of(identity)
	if seat != null:
		seat.miner = e.id
	history.append({"tick": run.tick, "identity": identity, "slot": slot, "what": "back at %s" % tile})
	Log.info("absent: %s is back; their miner stands up in base camp at %s" % [identity, tile])


func is_waiting(identity: String) -> bool:
	return waiting.has(identity)


## The lamp in hand (or on its hook), the free hand and every belt slot, laid on the bench's tile.
func _lay_on_bench(run: RunState, miner: int) -> void:
	if run.inventory == null or run.base_camp == null:
		return
	var at: Vector2 = Vector2(run.base_camp.bench_tile()) + Vector2(0.5, 0.5)
	var h: HandsAndBelt = run.inventory.hands_of(miner)
	var w: ItemWorld = run.inventory.world
	if h.lamp_hand != null:
		var lamp: Item = h.lamp_hand
		h.lamp_hand = null
		h.hooked = false
		w.put(run, lamp, at, &"put", miner)
	if h.free_hand != null:
		var it: Item = h.free_hand
		h.free_hand = null
		w.put(run, it, at, &"put", miner)
	for i: int in h.slots.size():
		if h.slots[i] != null:
			var it: Item = h.slots[i]
			h.slots[i] = null
			w.put(run, it, at, &"put", miner)
	h.two_handed = false
	run.inventory.changed.emit(miner)


## A walkable tile of base camp's floor (not the cage deck) a tile from every miner, in order.
func _free_tile(run: RunState) -> Vector2i:
	if run.base_camp == null:
		return Vector2i.ZERO
	var deck: Rect2i = Basecamp.deck_rect(run.base_camp.seed_value, run.base_camp.side)
	var tiles: Array[Vector2i] = []
	for raw: Variant in run.base_camp.inside_tiles.keys():
		var t: Vector2i = raw
		if not deck.has_point(t) and (run.mine == null or run.mine.native.is_walkable(t)):
			tiles.append(t)
	tiles.sort()
	for t: Vector2i in tiles:
		var c: Vector2 = Vector2(t) + Vector2(0.5, 0.5)
		var taken: bool = false
		for id: int in run.registry.ids():
			var e: SimEntity = run.registry.get_entity(id)
			if e.kind == WorldIds.EntityKind.MINER and e.position.distance_to(c) < 1.0:
				taken = true
				break
		if not taken:
			return t
	return tiles[0] if not tiles.is_empty() else Vector2i.ZERO


func save_state() -> Dictionary:
	return {"waiting": waiting.duplicate(true)}


func load_state(_r: RunState, state: Dictionary) -> void:
	waiting = Variants.dict(state.get("waiting", {})).duplicate(true)
