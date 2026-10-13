class_name GuardRegistry
extends RefCounted
## CRT-01's guard predicates for the illusions' contract (Gameplay §9.2): each creature answers
## "could I begin a wind-up on this miner within 6 s?". Each creature ticket registers its own;
## registering without one is an error. The neighbourhood is straight-line, which over-includes
## and so is safe.

const NEAR_TILES: float = 10.0

## kind -> (run: RunState, miner_entity: int) -> bool
var predicates: Dictionary = {}


func register(kind: WorldIds.EntityKind, predicate: Callable) -> bool:
	if not predicate.is_valid():
		push_error("GuardRegistry: %s registered without a guard predicate" % WorldIds.EntityKind.find_key(kind))
		return false
	predicates[kind] = predicate
	return true


func unregister(kind: WorldIds.EntityKind) -> void:
	predicates.erase(kind)


func holds(run: RunState, kind: WorldIds.EntityKind, miner_entity: int) -> bool:
	var p: Callable = predicates.get(kind, Callable())
	return p.is_valid() and Variants.flag(p.call(run, miner_entity))


## True when any creature's predicate holds for the miner or anyone within `radius_tiles`.
func any_holds_near(run: RunState, miner_entity: int, radius_tiles: float = NEAR_TILES) -> bool:
	var centre: SimEntity = run.registry.get_entity(miner_entity)
	if centre == null:
		return false
	var kinds: Array = predicates.keys()
	kinds.sort()
	for id: int in run.registry.ids():
		var e: SimEntity = run.registry.get_entity(id)
		if e.kind != WorldIds.EntityKind.MINER or e.position.distance_squared_to(centre.position) > radius_tiles * radius_tiles:
			continue
		for kind: Variant in kinds:
			var p: Callable = predicates[kind]
			if Variants.flag(p.call(run, id)):
				return true
	return false
