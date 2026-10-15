class_name M1Arrival
extends RefCounted
## QA-01's minimal M1 arrival (user decision 2026-10-15; MOD-04's cold open and roll call replace
## it). No server gave a joining player a miner (GEN-03: MOD and LFT own spawning), so the kill test
## had nobody to play. A real server with a map gives each newly welcomed identity a miner on a free
## tile of base camp's cage deck, else on base camp's floor, with empty hands and an unlit world as
## the cold open finds it. A returning identity gets no second miner: NET-11 hands back the first.
## The scenario kit places its own miners and never installs this.

## Two miners never arrive closer than this (tiles).
const SPACING: float = 1.0
## No free tile.
const NONE: Vector2i = Vector2i(-1048576, -1048576)

var run: RunState = null
var mine: Mine = null
## identity -> miner entity
var miners: Dictionary = {}
var _tiles: Array[Vector2i] = []


func _init(of_run: RunState, of_mine: Mine) -> void:
	run = of_run
	mine = of_mine
	_tiles = arrival_tiles()


## The tiles a miner may arrive on, in order: the cage deck's walkable tiles, then the rest of base
## camp's floor (sorted, so arrival is deterministic).
func arrival_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if run.base_camp == null:
		return out
	var deck: Rect2i = Basecamp.deck_rect(run.base_camp.seed_value, run.base_camp.side)
	var deck_tiles: Array[Vector2i] = []
	var floor_tiles: Array[Vector2i] = []
	for raw: Variant in run.base_camp.inside_tiles.keys():
		var t: Vector2i = raw
		if not mine.native.is_walkable(t):
			continue
		if deck.has_point(t):
			deck_tiles.append(t)
		else:
			floor_tiles.append(t)
	deck_tiles.sort()
	floor_tiles.sort()
	out.append_array(deck_tiles)
	out.append_array(floor_tiles)
	return out


## ServerNet's welcomed: a miner for a new identity.
## NET-09: a resumed run's miners, by their players' identities, so a returning player retakes theirs.
func adopt(seats: SeatTable) -> void:
	for raw: Variant in seats.seats.keys():
		var s: SeatTable.Seat = seats.seats[raw]
		if s.miner != 0:
			miners[str(raw)] = s.miner


func on_welcomed(slot: int, identity: String) -> void:
	if miners.has(identity):
		Log.info("arrival: %s is back (slot %d); NET-11 hands its miner back" % [identity, slot])
		return
	var tile: Vector2i = _free_tile()
	if tile == NONE:
		Log.warn("arrival: no free tile in base camp for %s" % identity)
		return
	var e: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(tile) + Vector2(0.5, 0.5))
	if run.movement != null:
		run.movement.add_miner(slot, e.id, e.position, 0)
	if run.miner_state != null:
		run.miner_state.add_miner(e.id, slot)
	if run.vision != null:
		run.vision.watch(slot, e.id, 0)
	miners[identity] = e.id
	Log.info("arrival: slot %d's miner at %s" % [slot, tile])


func _free_tile() -> Vector2i:
	for t: Vector2i in _tiles:
		var centre: Vector2 = Vector2(t) + Vector2(0.5, 0.5)
		var taken: bool = false
		for id: int in run.registry.ids():
			var e: SimEntity = run.registry.get_entity(id)
			if e.kind == WorldIds.EntityKind.MINER and e.position.distance_to(centre) < SPACING:
				taken = true
				break
		if not taken:
			return t
	return NONE
