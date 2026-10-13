class_name ActiveCap
extends RefCounted
## DIR-05's active-hunter cap (CRT-01's CapProvider): at most director.active_hunter_cap
## creatures active at once by crew count (2 at crew count 1, 3 from 2; a count of 0 reads as 1).
## A full cap stops a creature committing, never perceiving; a committed hunter is never stood
## down. It binds every commit, chosen or consequence, and holds through the apex.

var census: CrewCensus
var gate: HuntGate


func _init(crew: CrewCensus, hunt_gate: HuntGate) -> void:
	census = crew
	gate = hunt_gate
	gate.cap_for = func(crew_count: int) -> int: return capacity_for(crew_count)
	gate.crew_count = func() -> int: return census.count


static func capacity_for(crew_count: int) -> int:
	return roundi(Tuning.by_crew(&"director.active_hunter_cap", clampi(crew_count, 1, 5)))


func capacity() -> int:
	return capacity_for(census.count)


## Creatures in a state that fills a place, or hunting (laying, homing, collecting never do).
func active_count() -> int:
	return gate.active_count()


func has_place() -> bool:
	return active_count() < capacity()
