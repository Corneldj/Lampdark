class_name Mine
extends RefCounted
## The server's mine (GEN-01): the native LbMine, the material table and path costs from data,
## and a thread-safe queue so GEN-11's workers can hand over finished cells. Commits and
## unloads apply only when the tick calls apply_pending() (stage 5, MineCommitSystem), so no
## query ever sees a half-committed cell. Server-only.

const MATERIALS: String = "res://data/world/materials.json"


## A path query's answer, in tiles.
class PathAnswer:
	extends RefCounted
	## -1 when unreachable within the maximum.
	var distance: float = -1.0
	var touched_unloaded: bool = false
	var hit_max: bool = false

var native: LbMine = LbMine.new()
var _mutex: Mutex = Mutex.new()
var _pending_commits: Array[LbCellData] = []
var _pending_unloads: Array[Vector2i] = []
## CRT-02: (cell: Vector2i) -> bool, true for a cell that must stay loaded (one within
## creatures.nav_keep_loaded_cells of a creature). Refused unloads are dropped and counted;
## GEN-11 asks again once the creature has moved on.
var keep_loaded: Callable = Callable()
var refused_unloads: int = 0


func _init() -> void:
	var file: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(MATERIALS)))
	if not native.set_material_table(Variants.dict(file.get("materials", {}))):
		push_error("Mine: data/world/materials.json is incomplete; using built-in defaults")
	if Tuning.current.has_key(&"mine.path_diagonal_cost"):
		native.set_path_costs(1000, roundi(Tuning.f(&"mine.path_diagonal_cost") * 1000.0))


## Any thread: queue a finished cell for the next tick's stage 5.
func queue_commit(data: LbCellData) -> void:
	_mutex.lock()
	_pending_commits.append(data)
	_mutex.unlock()


func queue_unload(cell: Vector2i) -> void:
	_mutex.lock()
	_pending_unloads.append(cell)
	_mutex.unlock()


## Tick thread only.
func apply_pending() -> void:
	_mutex.lock()
	var commits: Array[LbCellData] = _pending_commits
	var unloads: Array[Vector2i] = _pending_unloads
	_pending_commits = []
	_pending_unloads = []
	_mutex.unlock()
	for cell: Vector2i in unloads:
		if keep_loaded.is_valid() and Variants.flag(keep_loaded.call(cell)):
			refused_unloads += 1
			continue
		native.unload(cell)
	for data: LbCellData in commits:
		native.commit(data)


func pending_count() -> int:
	_mutex.lock()
	var n: int = _pending_commits.size() + _pending_unloads.size()
	_mutex.unlock()
	return n


## Walk distance in tiles (8-connected, no corner cutting), capped at max_tiles
## (default mine.path_query_max_tiles).
func path_distance(from: Vector2i, to: Vector2i, max_tiles: float = -1.0, doors_open: bool = false) -> PathAnswer:
	var cap: float = max_tiles if max_tiles > 0.0 else Tuning.f(&"mine.path_query_max_tiles")
	var result: Dictionary = native.path_distance(from, to, roundi(cap * 1000.0), doors_open)
	var milli: int = int(Variants.number(result["distance_milli"]))
	var answer: PathAnswer = PathAnswer.new()
	answer.distance = milli / 1000.0 if milli >= 0 else -1.0
	answer.touched_unloaded = Variants.flag(result["touched_unloaded"])
	answer.hit_max = Variants.flag(result["hit_max"])
	return answer


## Loads every cell file of a fixed map (GEN-02's base camp, GEN-01's test map) at once; a map with
## a manifest (GEN-03's grey box) loads base camp and exactly its listed cells (FixedMapLoader).
func load_fixed_map(map_name: String) -> int:
	if not FixedMapLoader.manifest(map_name).is_empty():
		return FixedMapLoader.load_cells(self, map_name)
	var dir: String = "res://data/maps/%s" % map_name
	var count: int = 0
	for file: String in DirAccess.get_files_at(dir):
		if file.begins_with("cell_") and file.get_extension() == "json":
			var data: LbCellData = CellFile.load_file(dir.path_join(file))
			if data != null:
				native.commit(data)
				count += 1
	return count
