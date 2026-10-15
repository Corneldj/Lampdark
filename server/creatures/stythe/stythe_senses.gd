class_name StytheSenses
extends RefCounted
## CRT-13 (Gameplay §7.4, §7.1): what the Stythe senses. Only unlit miners, on tiles below its
## threshold, within its ring's range by walkable path (CreatureTables.stythe_senses_tiles: 8-16,
## or 20 in its territory); sound reaches it only through the unheard timer (SND-09). It remembers
## the last 1 + crew count places it sensed someone, for stythe.memory_s. Distances to the lair (the
## territory, stythe.territory_tiles, and the hunting range, stythe.hunting_range_tiles) are by path,
## cached per tile for a second. Server-only: nothing here is ever sent.

## Sensed this tick: [{miner, tile, distance}], in entity order.
var sensed: Array[Dictionary] = []
## Remembered places, newest last: [{tile, tick}].
var memory: Array[Dictionary] = []
## tile -> [tick, path distance to the lair or -1]
var _lair_cache: Dictionary = {}


## The miners it senses now from `from`, and their places remembered.
func update(run: RunState, st: StytheCreature) -> void:
	sensed.clear()
	var from: Vector2i = st.tile(run)
	var reach: float = range_at(run, st)
	for id: int in StytheSenses.miners(run):
		var e: SimEntity = run.registry.get_entity(id)
		if not st.unlit(run, e.tile()) or not StytheSenses.awake(run, id):
			continue
		if Vector2(from).distance_to(Vector2(e.tile())) > reach + 1.0:
			continue
		var answer: Mine.PathAnswer = run.mine.path_distance(from, e.tile(), reach) if run.mine != null else null
		if answer == null or answer.distance < 0.0 or answer.distance > reach + 1e-6:
			continue
		sensed.append({"miner": id, "tile": e.tile(), "distance": answer.distance})
		remember(run, e.tile(), run.crew.count if run.crew != null else 1)
	_forget(run)


## Its sense range now: its ring's, or the territory's.
func range_at(run: RunState, st: StytheCreature) -> float:
	return CreatureTables.stythe_senses_tiles(st.ring(run), in_territory(run, st, st.tile(run)))


func senses(miner: int) -> bool:
	for s: Dictionary in sensed:
		if int(Variants.number(s["miner"])) == miner:
			return true
	return false


## A place sensed: kept as the newest, the oldest dropped beyond 1 + crew count.
func remember(run: RunState, tile: Vector2i, crew_count: int) -> void:
	for i: int in memory.size():
		if memory[i]["tile"] == tile:
			memory.remove_at(i)
			break
	memory.append({"tile": tile, "tick": run.tick})
	while memory.size() > CreatureTables.stythe_memory_places(crew_count):
		memory.remove_at(0)


func _forget(run: RunState) -> void:
	var keep: int = roundi(Tuning.f(&"stythe.memory_s") * Tuning.f(&"net.tick_hz"))
	var still: Array[Dictionary] = []
	for m: Dictionary in memory:
		if run.tick - int(Variants.number(m["tick"])) < keep:
			still.append(m)
	memory = still


## Path distance from the lair to `tile` (-1: beyond the hunting range or unreachable).
func lair_distance(run: RunState, st: StytheCreature, tile: Vector2i) -> float:
	var c: Array = _lair_cache.get(tile, [])
	if not c.is_empty() and run.tick - int(Variants.number(c[0])) < roundi(Tuning.f(&"net.tick_hz")):
		return float(Variants.number(c[1]))
	var d: float = -1.0
	if run.mine != null:
		var limit: float = Tuning.f(&"stythe.hunting_range_tiles")
		if Vector2(st.lair).distance_to(Vector2(tile)) <= limit + 1e-6:
			var answer: Mine.PathAnswer = run.mine.path_distance(st.lair, tile, limit)
			d = answer.distance if answer.distance >= 0.0 and answer.distance <= limit + 1e-6 else -1.0
	_lair_cache[tile] = [run.tick, d]
	return d


func in_territory(run: RunState, st: StytheCreature, tile: Vector2i) -> bool:
	var d: float = lair_distance(run, st, tile)
	return d >= 0.0 and d <= Tuning.f(&"stythe.territory_tiles") + 1e-6


func in_hunting_range(run: RunState, st: StytheCreature, tile: Vector2i) -> bool:
	return lair_distance(run, st, tile) >= 0.0


## GEN-01 swapped tiles (a fall): every cached distance is stale.
func on_tiles_changed() -> void:
	_lair_cache.clear()


## Every miner entity (humans and Hands), in id order.
static func miners(run: RunState) -> Array[int]:
	var out: Array[int] = []
	for id: int in run.registry.ids():
		if run.registry.get_entity(id).kind == WorldIds.EntityKind.MINER:
			out.append(id)
	out.sort()
	return out


## Upright or Caught: a miner the Stythe can hunt (a fallen one is Collect's, CRT-14).
static func awake(run: RunState, miner: int) -> bool:
	if run.miner_state == null or run.miner_state.miner(miner) == null:
		return true
	var life: int = run.miner_state.life(miner)
	return life == MinerTransitions.Life.UPRIGHT or life == MinerTransitions.Life.CAUGHT
