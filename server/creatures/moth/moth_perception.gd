class_name MothPerception
extends RefCounted
## CRT-04: what the awake Moth sees (Gameplay §7.2). Light only: tiles lit to moth.see_level in
## its line of sight (VIS-03's caster, no cone; rock, a shut gate and a closed air door block it)
## within its ring's sight, grouped into clusters of 8-connected tiles scored by their summed light
## (Proposed); egg-glow at any level makes clusters of its own. Beacons (a flare, MNR-09; a lamp
## signal, SND-12) are seen further: moth.flare_sight_tiles and moth.signal_sight_tiles. Searched
## lights drop out of its view for moth.searched_s. In a frenzy it also sees miners standing in
## 0.30. Never sound, illusions, other creatures or client data; never rewound. Server-only.

## Lights it cannot take (§5.4, §7.2): it covers one for moth.linger_s, then treats it as searched.
const CANNOT_TAKE_KINDS: Array[String] = ["emergency", "gate_spill", "electric_lamp", "gob_fire", "egg_glow"]
const SEEN_FIELDS: int = 5

class Cluster:
	extends RefCounted
	var tiles: Array[Vector2i] = []
	var score: float = 0.0
	var centroid: Vector2 = Vector2.ZERO
	var brightest: Vector2i = Vector2i.ZERO
	var brightest_value: int = 0
	## The source behind its brightest tile, and what VIS-02 says of it.
	var source: int = 0
	var kind: String = ""
	var owner: int = 0
	var flags: int = 0
	var source_position: Vector2 = Vector2.ZERO
	var radius: float = 0.0
	var egg: bool = false
	## Every source that is the brightest on one of its tiles: id -> VIS-02's source_info. A merged
	## cluster (a lamp-bearer in base camp's light) keeps its carried flame here.
	var sources: Dictionary = {}

	## Carriers of lights in it: [miner, source], ascending source.
	func carriers() -> Array[Array]:
		var out: Array[Array] = []
		for id: int in _ids():
			var info: Dictionary = sources[id]
			var fl: int = int(Variants.number(info.get("flags", 0)))
			var who: int = int(Variants.number(info.get("owner", 0)))
			if (fl & LbLightGrid.FLAG_CARRIED) != 0 and who != 0:
				out.append([who, id])
		return out

	## Unheld lights it can take (a set-down or dropped lamp, a candle): ascending source.
	func unheld_sources() -> Array[int]:
		var out: Array[int] = []
		for id: int in _ids():
			var info: Dictionary = sources[id]
			var fl: int = int(Variants.number(info.get("flags", 0)))
			if (fl & LbLightGrid.FLAG_UNHELD) != 0 and not MothPerception.cannot_take_info(info):
				out.append(id)
		return out

	func has_source(id: int) -> bool:
		return sources.has(id)

	func _ids() -> Array[int]:
		var out: Array[int] = []
		for raw: Variant in sources.keys():
			out.append(int(Variants.number(raw)))
		out.sort()
		return out

	func carried() -> bool:
		return (flags & LbLightGrid.FLAG_CARRIED) != 0 and owner != 0

	func unheld() -> bool:
		return (flags & LbLightGrid.FLAG_UNHELD) != 0

	func cannot_take() -> bool:
		return egg or CANNOT_TAKE_KINDS.has(kind) or (flags & LbLightGrid.FLAG_CANNOT_TAKE) != 0


static func cannot_take_info(info: Dictionary) -> bool:
	return CANNOT_TAKE_KINDS.has(str(info.get("kind", ""))) or (int(Variants.number(info.get("flags", 0))) & LbLightGrid.FLAG_CANNOT_TAKE) != 0


var clusters: Array[Cluster] = []
## Miners standing in 0.30 in its sight (read only in a frenzy).
var lit_miners: Array[int] = []
## tile -> thousandths, everything seen at the last scan (egg-glow included).
var seen: Dictionary = {}
var scanned_tick: int = -1
## source id -> the tick it stops being searched.
var searched: Dictionary = {}
## beacon id -> {kind: &"flare" or &"signal", source: int (VIS-02), until: tick}
var beacons: Dictionary = {}


func searched_ids(now: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	var ids: Array = searched.keys()
	ids.sort()
	for raw: Variant in ids:
		if int(Variants.number(searched[raw])) > now:
			out.append(int(Variants.number(raw)))
		else:
			searched.erase(raw)
	return out


func mark_searched(source: int, now: int) -> void:
	searched[source] = now + roundi(Tuning.f(&"moth.searched_s") * Tuning.f(&"net.tick_hz"))


func scan(run: RunState, from: Vector2i, sight: float) -> void:
	scanned_tick = run.tick
	clusters.clear()
	lit_miners.clear()
	seen.clear()
	if run.light == null:
		return
	var far: Dictionary = {}
	var reach: float = sight
	for raw: Variant in beacons.keys():
		var b: Dictionary = beacons[raw]
		if int(Variants.number(b.get("until", 0))) <= run.tick:
			beacons.erase(raw)
			continue
		var r: float = Tuning.f(&"moth.flare_sight_tiles") if b["kind"] == &"flare" else Tuning.f(&"moth.signal_sight_tiles")
		far[int(Variants.number(b["source"]))] = r
		reach = maxf(reach, r)
	var see_level: float = Tuning.f(&"moth.see_level")
	var raw_tiles: PackedInt64Array = LightSense.new(run).lit_in_sight(from, reach, see_level, searched_ids(run.tick))
	var lit: Dictionary = {}
	var egg: Dictionary = {}
	var source_of: Dictionary = {}
	var see_milli: int = roundi(see_level * 1000.0)
	for i: int in range(0, raw_tiles.size(), SEEN_FIELDS):
		var t: Vector2i = Vector2i(raw_tiles[i], raw_tiles[i + 1])
		var value: int = raw_tiles[i + 2]
		var source: int = raw_tiles[i + 3]
		var d: float = Vector2(t - from).length()
		if d > sight and (not far.has(source) or d > float(Variants.number(far[source]))):
			continue
		seen[t] = value
		source_of[t] = source
		if raw_tiles[i + 4] == LbLightGrid.COLOUR_EGG_GLOW:
			egg[t] = value
		elif value >= see_milli:
			lit[t] = value
	for group: Dictionary in [lit, egg]:
		_cluster(run, group, source_of, group == egg)
	clusters.sort_custom(func(a: Cluster, b: Cluster) -> bool:
		if a.score != b.score:
			return a.score > b.score
		return a.brightest.y < b.brightest.y or (a.brightest.y == b.brightest.y and a.brightest.x < b.brightest.x))
	for id: int in run.registry.ids():
		var e: SimEntity = run.registry.get_entity(id)
		if e.kind == WorldIds.EntityKind.MINER and lit.has(e.tile()):
			lit_miners.append(id)
	lit_miners.sort()


func brightest() -> Cluster:
	return clusters[0] if not clusters.is_empty() else null


## The cluster holding a source among its brightest, or null.
func cluster_with_source(id: int) -> Cluster:
	for c: Cluster in clusters:
		if c.has_source(id):
			return c
	return null


## The cluster holding a tile, or null.
func cluster_at(tile: Vector2i) -> Cluster:
	for c: Cluster in clusters:
		if c.tiles.has(tile):
			return c
	return null


func _cluster(run: RunState, group: Dictionary, source_of: Dictionary, is_egg: bool) -> void:
	var keys: Array = group.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var done: Dictionary = {}
	for raw: Variant in keys:
		var start: Vector2i = raw
		if done.has(start):
			continue
		var c: Cluster = Cluster.new()
		c.egg = is_egg
		var stack: Array[Vector2i] = [start]
		done[start] = true
		var sum: Vector2 = Vector2.ZERO
		while not stack.is_empty():
			var t: Vector2i = stack.pop_back()
			var v: int = int(Variants.number(group[t]))
			c.tiles.append(t)
			c.score += v / 1000.0
			sum += (Vector2(t) + Vector2(0.5, 0.5)) * (v / 1000.0)
			if v > c.brightest_value or (v == c.brightest_value and (t.y < c.brightest.y or (t.y == c.brightest.y and t.x < c.brightest.x))):
				c.brightest_value = v
				c.brightest = t
			for dy: int in [-1, 0, 1]:
				for dx: int in [-1, 0, 1]:
					var n: Vector2i = t + Vector2i(dx, dy)
					if (dx != 0 or dy != 0) and group.has(n) and not done.has(n):
						done[n] = true
						stack.append(n)
		c.centroid = sum / c.score if c.score > 0.0 else Vector2(start) + Vector2(0.5, 0.5)
		for t: Vector2i in c.tiles:
			var id: int = int(Variants.number(source_of.get(t, 0)))
			if id != 0 and not c.sources.has(id):
				c.sources[id] = run.light.grid.source_info(id)
		c.source = int(Variants.number(source_of.get(c.brightest, 0)))
		var info: Dictionary = c.sources.get(c.source, run.light.grid.source_info(c.source))
		c.kind = str(info.get("kind", ""))
		c.owner = int(Variants.number(info.get("owner", 0)))
		c.flags = int(Variants.number(info.get("flags", 0)))
		c.radius = float(Variants.number(info.get("radius", 0.0)))
		# A point source sits where it is; an area, spill or spot is found at its brightest tile.
		var p: Variant = info.get("position", Vector2.ZERO)
		c.source_position = p if int(Variants.number(info.get("shape", 0))) == 0 else Vector2(c.brightest) + Vector2(0.5, 0.5)
		clusters.append(c)
