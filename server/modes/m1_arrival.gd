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
## MOD-03: the seats (the lamp number each miner's check carries); null: none.
var crew: CrewSeating = null
## identity -> miner entity
var miners: Dictionary = {}
## MOD-03: the crew seated at the start has arrived; later joiners come to on base camp's floor.
var begun: bool = false
## MOD-08: (entity) -> void, a joiner took this filler Hand's place: its AI lets the body go.
## Default: nothing (no Hands yet).
var hand_leaves: Callable = func(_entity: int) -> void: pass
var _tiles: Array[Vector2i] = []
var _floor_first: Array[Vector2i] = []


func _init(of_run: RunState, of_mine: Mine, of_crew: CrewSeating = null) -> void:
	run = of_run
	mine = of_mine
	crew = of_crew
	_tiles = arrival_tiles()
	_floor_first = floor_first(_tiles)


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


## The arrival tiles with the cage deck's last: where a joiner in progress comes to.
func floor_first(tiles: Array[Vector2i]) -> Array[Vector2i]:
	if run.base_camp == null:
		return tiles.duplicate()
	var deck: Rect2i = Basecamp.deck_rect(run.base_camp.seed_value, run.base_camp.side)
	var out: Array[Vector2i] = []
	var later: Array[Vector2i] = []
	for t: Vector2i in tiles:
		if deck.has_point(t):
			later.append(t)
		else:
			out.append(t)
	out.append_array(later)
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
	var hand: int = filler_hand_in(slot)
	if hand != 0:
		take_hand_place(slot, identity, hand)
		return
	var tile: Vector2i = _free_tile(_floor_first if begun else _tiles)
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
	var lamp: int = _lamp_number(slot)
	if run.inventory != null and lamp > 0:
		run.inventory.hands_of(e.id, lamp)
	miners[identity] = e.id
	Log.info("arrival: slot %d's miner at %s%s" % [slot, tile, " (joining in progress)" if begun else ""])


## MOD-03: the crew seated at the Pithead arrives as the run begins (a hosted run's).
func arrive_crew(sessions: Array[Sessions.Session]) -> void:
	for session: Sessions.Session in sessions:
		on_welcomed(session.slot, session.identity)
	begun = true


## MOD-08: Hired Hands in the empty places (MOD-03's hands_fill, as the run begins): each place with
## no miner gets a filler Hand on a free tile of the cage deck, beside the crew. Returns how many.
func arrive_hands(hands: HandController, places: int) -> int:
	var n: int = 0
	for slot: int in places:
		if run.movement == null or run.movement.miner(slot) != null:
			continue
		var tile: Vector2i = _free_tile(_tiles)
		if tile == NONE:
			break
		if hands.fill_place(run, slot, Vector2(tile) + Vector2(0.5, 0.5)) != 0:
			n += 1
	return n


## A filler Hired Hand holding `slot`'s place (MOD-08's Hand in that place, not a dropped player's
## miner), or 0.
func filler_hand_in(slot: int) -> int:
	if run.movement == null or run.crew == null:
		return 0
	var m: MovementSystem.Miner = run.movement.miner(slot)
	if m == null or not Variants.flag(run.crew.is_hired_hand.call(m.entity_id)):
		return 0
	return m.entity_id


## The joiner's miner takes the Hand's place where it stands: its body, lamp and belt (Proposed:
## MOD-03's open question), with the joiner's own lamp check; the Hand leaves.
func take_hand_place(slot: int, identity: String, hand: int) -> void:
	hand_leaves.call(hand)
	if run.vision != null:
		run.vision.watch(slot, hand, run.movement.miner(slot).state.facing if run.movement != null else 0)
	if run.inventory != null:
		run.inventory.hands_of(hand).lamp_check = _lamp_number(slot)
		run.inventory.changed.emit(hand)
	miners[identity] = hand
	Log.info("arrival: %s takes a Hired Hand's place in slot %d at %s" % [identity, slot, run.registry.get_entity(hand).position])


func _lamp_number(slot: int) -> int:
	if crew == null:
		return 0
	var s: CrewSeating.Seat = crew.of_slot(slot)
	return s.lamp_number if s != null else 0


func _free_tile(order: Array[Vector2i]) -> Vector2i:
	for t: Vector2i in order:
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
