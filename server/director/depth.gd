class_name Depth
extends RefCounted
## DIR-04: which ring counts, and the depth columns DIR-04 owns. Depth is straight-line distance
## from the shaft (FND-07's lookup); every rule reads the ring of its own entity's tile: a
## creature its own, the Pull and the relax's peaker the miner's, the seam's drink the lamp's.
## The Pull factor D and the relax lengths are data (depth.pull_factor, depth.relax_s). Holds no
## state: the relax reads its peaker's ring once, at the peak (DIR-01). Server-only.

const LEVEL_TEXT: String = "res://data/text/levels.json"


static func ring_of_entity(run: RunState, entity: int) -> int:
	var e: SimEntity = run.registry.get_entity(entity)
	return WorldCoords.ring_of_point(e.position) if e != null else 0


## A creature uses its own tile.
static func ring_for_creature(run: RunState, entity: int) -> int:
	return ring_of_entity(run, entity)


## A miner's own tile: the Pull, and the relax's peaker (read at the peak).
static func ring_for_miner(run: RunState, entity: int) -> int:
	return ring_of_entity(run, entity)


## The Stythe's unheard mark for a miner: read from the miner's own tile, since it measures the
## miner's silence (design ruling 2026-10-12, Gameplay §7.1).
static func unheard_mark_s(run: RunState, miner: int) -> float:
	return CreatureTables.stythe_unheard_mark_s(ring_for_miner(run, miner))


## A lamp's own tile (hung, carried or dropped): the seam's drink.
static func ring_for_lamp(run: RunState, entity: int) -> int:
	return ring_of_entity(run, entity)


static func pull_factor(ring: int) -> float:
	return Tuning.by_ring(&"depth.pull_factor", clampi(ring, 0, 4))


static func relax_s(ring: int) -> float:
	return Tuning.by_ring(&"depth.relax_s", clampi(ring, 0, 4))


## The text key naming a ring's Level (level.0-level.4); never the word "ring".
static func level_name_key(ring: int) -> String:
	return "level.%d" % clampi(ring, 0, 4)


## Placeholder English for a Level name until UI-07's localisation.
static func level_name(ring: int) -> String:
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(LEVEL_TEXT)))
	return str(Variants.dict(doc.get("strings", {})).get(level_name_key(ring), ""))
