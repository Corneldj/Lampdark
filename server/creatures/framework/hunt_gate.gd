class_name HuntGate
extends RefCounted
## CRT-01's gate on hunts. A hunt is on a miner from the moment a creature commits to them until
## it stands down. request_commit checks the relax (only for a chosen hunt, and never in the apex)
## then the cap; a committed hunter is never stood down by the cap. When a relax begins, chosen
## hunts end, once any wind-up or grab under way has finished. Providers stand in for the
## director until it exists (M1 defaults below).

signal hunt_started(creature: Creature, miner: int, chosen: bool)
signal hunt_ended(creature: Creature, miner: int, reason: String)

## DIR-01/02's relax: () -> bool. Default: never.
var relax_active: Callable = func() -> bool: return false
## LFT-09's apex: () -> bool, from the engine catching until the cage leaves. Default: never.
var apex_on: Callable = func() -> bool: return false
## DIR-05's cap: (crew_count) -> int places, negative for none. Default: never binds (Proposed).
var cap_for: Callable = func(_crew: int) -> int: return -1
## DIR-05's crew count: () -> int. Default: the conscious connected miners (set by the system).
var crew_count: Callable = func() -> int: return 1
## DIR-01's build (the Draught rising): () -> bool. Default: never.
var build_active: Callable = func() -> bool: return false
## DIR-03's Pull: (miner_entity) -> int. Default 0: nobody attended or marked.
var pull_of: Callable = func(_miner: int) -> int: return 0

## creature -> {"miner", "chosen", "tick"}
var hunts: Dictionary = {}
var creatures: Array[Creature] = []
var _relax_was: bool = false
var _relax_ending: Array[Creature] = []
var _log: CreatureLog = null


func _init(log: CreatureLog = null) -> void:
	_log = log


func is_hunting(c: Creature) -> bool:
	return hunts.has(c)


func target_of(c: Creature) -> int:
	return int(Variants.number(Variants.dict(hunts.get(c, {})).get("miner", 0)))


## Creatures holding a place under the cap: hunting, or in a state that fills one.
func active_count() -> int:
	var n: int = 0
	for c: Creature in creatures:
		if hunts.has(c) or (c.state != null and c.state.fills_cap_place):
			n += 1
	return n


func cap_full() -> bool:
	var cap: int = int(Variants.number(cap_for.call(int(Variants.number(crew_count.call())))))
	return cap >= 0 and active_count() >= cap


## Commits `c` to a hunt on `miner`. chosen: the creature chose it (the relax blocks it);
## otherwise a consequence the crew caused. Fails when the cap is full either way.
func request_commit(run: RunState, c: Creature, miner: int, chosen: bool) -> bool:
	if hunts.has(c):
		return target_of(c) == miner
	if chosen and Variants.flag(relax_active.call()) and not Variants.flag(apex_on.call()):
		return false
	if cap_full():
		return false
	hunts[c] = {"miner": miner, "chosen": chosen, "tick": run.tick}
	if _log != null:
		_log.add(run.tick, &"hunt_started", {"creature": c.kind_name(), "miner": miner, "chosen": chosen})
	hunt_started.emit(c, miner, chosen)
	return true


## It loses them, is driven off, retreats or its grab ends.
func stand_down(run: RunState, c: Creature, reason: String) -> void:
	if not hunts.has(c):
		return
	var miner: int = target_of(c)
	var started: int = int(Variants.number(Variants.dict(hunts[c]).get("tick", run.tick)))
	hunts.erase(c)
	_relax_ending.erase(c)
	if _log != null:
		_log.add(run.tick, &"hunt_ended", {"creature": c.kind_name(), "miner": miner, "started": started, "reason": reason})
	hunt_ended.emit(c, miner, reason)


## Each tick: follow the relax. Chosen hunts end when it begins, each once its wind-up or grab
## under way has finished; senses and memories keep counting (the creatures' business).
func tick(run: RunState) -> void:
	var relax: bool = Variants.flag(relax_active.call())
	if relax and not _relax_was:
		for c: Creature in creatures:
			c.on_relax_started(run)
			if hunts.has(c) and Variants.flag(Variants.dict(hunts[c]).get("chosen", false)) and not Variants.flag(apex_on.call()):
				_relax_ending.append(c)
	elif not relax and _relax_was:
		_relax_ending.clear()
		for c: Creature in creatures:
			c.on_relax_ended(run)
	_relax_was = relax
	for c: Creature in _relax_ending.duplicate():
		var busy: bool = (c.wind_up != null and c.wind_up.is_running()) or c.grabbing != 0
		if not busy:
			stand_down(run, c, "relax")
