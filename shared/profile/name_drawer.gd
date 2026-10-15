class_name NameDrawer
extends RefCounted
## MOD-01 (Gameplay §13.2, GDD §2.6): names come only from the period list
## (data/text/names/period_names.json), never from the exclusion list (the 61 killed in the Breath,
## and any the consultant flags). A draw is uniform, without replacement, avoiding the names the
## roster already holds, from the profile's own stream (FND-06; never a run's seed).

const PERIOD: String = "res://data/text/names/period_names.json"
const EXCLUDED: String = "res://data/text/names/excluded_names.json"

static var _period: Array[Dictionary] = []
static var _excluded: Dictionary = {}


static func period_names() -> Array[Dictionary]:
	_load()
	return _period


static func is_excluded(name: Dictionary) -> bool:
	_load()
	return _excluded.has(full(name))


static func full(name: Dictionary) -> String:
	return "%s %s" % [str(name.get("given", "")), str(name.get("surname", ""))]


## `count` distinct names for `purpose` (0: the first roster; else the replaced miner's id), none of
## them excluded or in `taken` (full names).
static func draw(profile_seed: int, purpose: int, count: int, taken: Array[String]) -> Array[Dictionary]:
	_load()
	var rng: LbRng = LbRng.from_seed(LbHash.sub_seed(profile_seed, HashDomain.PROFILE_NAMES, PackedInt64Array([purpose]), 0))
	var pool: Array[int] = []
	for i: int in _period.size():
		var n: Dictionary = _period[i]
		if not _excluded.has(full(n)) and not taken.has(full(n)):
			pool.append(i)
	var out: Array[Dictionary] = []
	while out.size() < count and not pool.is_empty():
		var at: int = rng.range(0, pool.size() - 1)
		out.append(_period[pool[at]].duplicate())
		pool.remove_at(at)
	return out


static func _load() -> void:
	if not _period.is_empty():
		return
	for raw: Variant in Variants.array(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(PERIOD))).get("names", [])):
		_period.append(Variants.dict(raw))
	for raw: Variant in Variants.array(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(EXCLUDED))).get("names", [])):
		_excluded[full(Variants.dict(raw))] = true
