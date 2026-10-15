class_name CreatureNav
extends RefCounted
## CRT-02's navigation service: one native navigator (LbCreatureNav) over the mine and the light
## grid, the guard queries the creature tickets register, the doorway check LFT-02 asks, and the
## cells kept loaded around creatures. Paths themselves are walked by NavFollower.

var native: LbCreatureNav = LbCreatureNav.new()


func _init(mine: Mine, light: LightSystem = null) -> void:
	native.attach(mine.native, light.grid if light != null else null)
	native.set_defaults(NavModes.defaults())


## The Moth's guard: a walkable path of creatures.guard_moth_path_tiles or less to the miner.
func moth_path_within(from: Vector2i, miner: Vector2, max_tiles: float = -1.0) -> bool:
	var limit: float = max_tiles if max_tiles > 0.0 else Tuning.f(&"creatures.guard_moth_path_tiles")
	return Variants.flag(native.moth_path_within(from, miner, limit, Tuning.i(&"creatures.nav_guard_max_expansions"))["found"])


## The Tapper's guard: a rock path to rock behind a usable face within its reach of the miner.
func tapper_rock_path_within(from: Vector2i, miner: Vector2, max_tiles: float = -1.0) -> bool:
	var limit: float = max_tiles if max_tiles > 0.0 else Tuning.f(&"creatures.guard_tapper_rock_path_tiles")
	return Variants.flag(native.tapper_rock_path_within(from, miner, limit, Tuning.f(&"tapper.reach_tiles"),
		{"max_expansions": Tuning.i(&"creatures.nav_guard_max_expansions")})["found"])


## The Stythe's guard: a dark path to a tile within its reach of the miner.
func stythe_dark_path_within(from: Vector2i, miner: Vector2, max_tiles: float = -1.0, thin: bool = false) -> bool:
	var limit: float = max_tiles if max_tiles > 0.0 else Tuning.f(&"creatures.guard_stythe_dark_path_tiles")
	var params: Dictionary = NavModes.dark(thin)
	params["max_expansions"] = Tuning.i(&"creatures.nav_guard_max_expansions")
	return Variants.flag(native.stythe_dark_path_within(from, miner, limit, Tuning.f(&"stythe.reach_tiles"), params)["found"])


## Within the Tapper's reach: 1.5 tiles or less from a usable wall face.
func in_tapper_reach(point: Vector2) -> bool:
	return not native.usable_faces_within(point, Tuning.f(&"tapper.reach_tiles")).is_empty()


## LFT-02: a gate waits while a creature stands in its doorway (the gate's tiles).
static func creature_in_doorway(run: RunState, gate_tiles: Array[Vector2i]) -> bool:
	if run.creatures == null:
		return false
	for c: Creature in run.creatures.creatures:
		if gate_tiles.has(c.tile(run)):
			return true
	return false


## GDD §15.9: the cells within creatures.nav_keep_loaded_cells of any creature, never evicted.
static func keeps_loaded(run: RunState, cell: Vector2i) -> bool:
	if run.creatures == null:
		return false
	var reach: int = Tuning.i(&"creatures.nav_keep_loaded_cells")
	for c: Creature in run.creatures.creatures:
		var t: Vector2i = c.tile(run)
		var home: Vector2i = Vector2i(floori(float(t.x) / WorldIds.CELL_TILES), floori(float(t.y) / WorldIds.CELL_TILES))
		if absi(home.x - cell.x) <= reach and absi(home.y - cell.y) <= reach:
			return true
	return false
