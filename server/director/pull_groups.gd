class_name PullGroups
extends RefCounted
## DIR-03's groups (Gameplay §10.5): conscious miners within movement.together_path_tiles (6) of each
## other by path, chained, so a strung-out line is one group while every gap stays in reach.
## GEN-01's path query with shut gates and closed air doors as walls. Only the Director's miners are
## grouped (Draught.conscious_humans): the fallen, Hired Hands and Bess are never company.
## Server-only.


## miner -> the size of their group (1: alone), for `miners`.
static func sizes(run: RunState, miners: Array[int]) -> Dictionary:
	var reach: float = Tuning.f(&"movement.together_path_tiles")
	var parent: Dictionary = {}
	for e: int in miners:
		parent[e] = e
	for i: int in miners.size():
		var a: SimEntity = run.registry.get_entity(miners[i])
		if a == null:
			continue
		for j: int in range(i + 1, miners.size()):
			var b: SimEntity = run.registry.get_entity(miners[j])
			if b == null or _root(parent, miners[i]) == _root(parent, miners[j]):
				continue
			# A walk is never shorter than the straight line (tile centre to centre).
			if a.position.distance_to(b.position) > reach + 1.5:
				continue
			if _within_by_path(run, a, b, reach):
				parent[_root(parent, miners[i])] = _root(parent, miners[j])
	var counts: Dictionary = {}
	for e: int in miners:
		var r: int = _root(parent, e)
		counts[r] = int(Variants.number(counts.get(r, 0))) + 1
	var out: Dictionary = {}
	for e: int in miners:
		out[e] = counts[_root(parent, e)]
	return out


static func _within_by_path(run: RunState, a: SimEntity, b: SimEntity, reach: float) -> bool:
	if run.mine == null:
		return a.position.distance_to(b.position) <= reach
	var path: Mine.PathAnswer = run.mine.path_distance(WorldCoords.tile_at(a.position), WorldCoords.tile_at(b.position), reach)
	return path.distance >= 0.0 and path.distance <= reach


static func _root(parent: Dictionary, e: int) -> int:
	var r: int = e
	while int(Variants.number(parent[r])) != r:
		r = int(Variants.number(parent[r]))
	parent[e] = r
	return r
