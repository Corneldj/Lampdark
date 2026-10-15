extends GutTest
## GEN-13's properties, over a minimal run (the mine, the inventory and the log; no light, sound or
## miners). 10,000 random sequences of puts, takes, set-downs, moves across cells, evictions,
## returns and compactions never duplicate or lose an item: each uid is in exactly one place, on a
## loaded floor, in a hand, or in an evicted cell's log. Compaction never changes what a replay
## puts back.

const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

const SEQUENCES: int = 10000
const CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
const KINDS: Array[ItemKinds.Kind] = [ItemKinds.Kind.SPANNER, ItemKinds.Kind.FUSE, ItemKinds.Kind.OIL_FLASK, ItemKinds.Kind.ROPE_CLAMP]

var _run: RunState = null
var _cells: Dictionary = {}
## The items in "hands": uid -> Item.
var _held: Dictionary = {}
var _made: Array[int] = []
## A stand-in owner's doors (shut by default): key -> open.
var _doors: Dictionary = {}


func before_all() -> void:
	assert_true(Tuning.load_server())


func _fresh() -> void:
	_run = RunState.create(9, ServerConfig.Mode.FRIENDS, false)
	_run.mine = Mine.new()
	_run.diff_log = DiffLog.new()
	_run.inventory = InventorySystem.new()
	_run.inventory.bind(_run)
	_run.diff_log.bind(_run)
	_run.diff_log.register(DiffLog.Kind.BARRIER, func(_r: RunState, _c: Vector2i, key: String, p: Dictionary, _t: int) -> void:
		_doors[key] = Variants.flag(p["open"]), Callable(),
		func(_c: Vector2i, _k: String, p: Dictionary) -> bool: return not Variants.flag(p["open"]))
	# Blood is the vision's to show; here the log's own packed set is compared.
	_run.diff_log.register(DiffLog.Kind.BLOOD, func(_r: RunState, _c: Vector2i, _k: String, _p: Dictionary, _t: int) -> void: pass)
	var fixture: FixtureMap = FixtureMap.from_ascii(PackedStringArray(["#".repeat(60), "#" + ".".repeat(58) + "#", "#".repeat(60)]))
	_cells.clear()
	for file: Dictionary in fixture.cells:
		var data: LbCellData = CellFile.from_dict(file, "props")
		_cells[data.get_coord()] = file
		_run.mine.native.commit(data)
	_held.clear()
	_made.clear()
	_doors.clear()


func _commit(cell: Vector2i) -> void:
	var file: Dictionary = _cells[cell]
	_run.mine.queue_commit(CellFile.from_dict(file, "props"))
	_run.mine.apply_pending()


func _unload(cell: Vector2i) -> void:
	_run.mine.queue_unload(cell)
	_run.mine.apply_pending()


func _loaded() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in CELLS:
		if _run.mine.native.is_loaded(c):
			out.append(c)
	return out


func _spot(rng: RandomNumberGenerator, cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 20 + rng.randi_range(1, 18), 1) + Vector2(0.5, 0.5)


func _floor_entities() -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in _run.inventory.world.items.keys():
		out.append(int(Variants.number(raw)))
	out.sort()
	return out


## uid -> where, failing on any uid in two places.
func _census() -> Dictionary:
	var where: Dictionary = {}
	var twice: Array[int] = []
	for raw: Variant in _run.inventory.world.items.values():
		var it: Item = raw
		if where.has(it.uid):
			twice.append(it.uid)
		where[it.uid] = "floor"
	for raw: Variant in _held.keys():
		var uid: int = int(Variants.number(raw))
		if where.has(uid):
			twice.append(uid)
		where[uid] = "hand"
	for c: Vector2i in CELLS:
		if _run.mine.native.is_loaded(c):
			continue
		for r: Dictionary in _run.diff_log.records(c):
			var p: Dictionary = r["payload"]
			if int(Variants.number(r["kind"])) == DiffLog.Kind.ITEM and str(p.get("where", "")) == "floor":
				var uid: int = int(Variants.number(p["uid"]))
				if where.has(uid):
					twice.append(uid)
				where[uid] = "log %s" % c
	where["twice"] = twice
	return where


func _step(rng: RandomNumberGenerator) -> String:
	var loaded: Array[Vector2i] = _loaded()
	var op: int = rng.randi_range(0, 6)
	var floor_ids: Array[int] = _floor_entities()
	match op:
		0:
			if loaded.is_empty():
				return "none"
			var it: Item = _run.inventory.world.make(KINDS[rng.randi_range(0, KINDS.size() - 1)], rng.randi_range(1, 3),
				{"fill": rng.randf()} if rng.randf() < 0.5 else {})
			_run.inventory.world.put(_run, it, _spot(rng, loaded[rng.randi_range(0, loaded.size() - 1)]))
			_made.append(it.uid)
			return "put"
		1:
			if floor_ids.is_empty():
				return "none"
			var e: int = floor_ids[rng.randi_range(0, floor_ids.size() - 1)]
			var it: Item = _run.inventory.world.lift(_run, e, &"take", 7)
			_held[it.uid] = it
			return "take"
		2:
			if _held.is_empty() or loaded.is_empty():
				return "none"
			var uids: Array = _held.keys()
			uids.sort()
			var uid: int = int(Variants.number(uids[rng.randi_range(0, uids.size() - 1)]))
			var it: Item = _held[uid]
			_held.erase(uid)
			_run.inventory.world.put(_run, it, _spot(rng, loaded[rng.randi_range(0, loaded.size() - 1)]), &"set_down", 7)
			return "set_down"
		3:
			if floor_ids.is_empty() or loaded.is_empty():
				return "none"
			var e: int = floor_ids[rng.randi_range(0, floor_ids.size() - 1)]
			_run.registry.move(e, _spot(rng, loaded[rng.randi_range(0, loaded.size() - 1)]))
			_run.inventory.world.moved(_run, e)
			return "move"
		4:
			if loaded.is_empty():
				return "none"
			_unload(loaded[rng.randi_range(0, loaded.size() - 1)])
			return "evict"
		5:
			var gone: Array[Vector2i] = []
			for c: Vector2i in CELLS:
				if not loaded.has(c):
					gone.append(c)
			if gone.is_empty():
				return "none"
			_commit(gone[rng.randi_range(0, gone.size() - 1)])
			return "return"
		_:
			_run.diff_log.compact(_run)
			return "compact"


func test_no_item_is_ever_duplicated_or_lost() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var failures: int = 0
	_fresh()
	for n: int in SEQUENCES:
		if n % 500 == 0:
			_fresh()
		else:
			for c: Vector2i in CELLS:
				if not _run.mine.native.is_loaded(c):
					_commit(c)
			for raw: Variant in _run.inventory.world.items.keys():
				_run.registry.destroy(int(Variants.number(raw)))
			_run.inventory.world.items.clear()
			_run.diff_log.store.clear()
			_run.diff_log.items.cell_of.clear()
			_held.clear()
			_made.clear()
		rng.seed = 7000 + n
		var ops: Array[String] = []
		for _i: int in rng.randi_range(1, 16):
			ops.append(_step(rng))
			var census: Dictionary = _census()
			var twice: Array[int] = census["twice"]
			census.erase("twice")
			if not twice.is_empty() or census.size() != _made.size():
				failures += 1
				if failures <= 3:
					fail_test("sequence %d %s: duplicated %s, %d of %d accounted" % [n, ops, twice, census.size(), _made.size()])
				break
		for c: Vector2i in CELLS:
			if not _run.mine.native.is_loaded(c):
				_commit(c)
		var live: int = _run.inventory.world.items.size() + _held.size()
		if live != _made.size():
			failures += 1
			if failures <= 3:
				fail_test("sequence %d %s: %d live after every return, %d made" % [n, ops, live, _made.size()])
	assert_eq(failures, 0, "%d sequences: every item in exactly one place, always" % SEQUENCES)


## Replays every cell from the log alone: what a replay puts back, canonical.
func _replayed() -> Dictionary:
	for c: Vector2i in CELLS:
		if _run.mine.native.is_loaded(c):
			_unload(c)
	_doors.clear()
	for c: Vector2i in CELLS:
		_commit(c)
	var items: Dictionary = {}
	for raw: Variant in _run.inventory.world.items.keys():
		var it: Item = _run.inventory.world.items[raw]
		var e: SimEntity = _run.registry.get_entity(int(Variants.number(raw)))
		items[it.uid] = [it.kind, it.count, DiffLog.canonical(it.state), e.position]
	var doors: Dictionary = {}
	for k: String in ["door:0", "door:1", "door:2"]:
		doors[k] = Variants.flag(_doors.get(k, false))
	var blood: Dictionary = {}
	for c: Vector2i in CELLS:
		for b: Variant in _run.diff_log.store.blood(c):
			var row: Dictionary = b
			blood[row["tile"]] = row["direction"]
	return {"items": items, "doors": doors, "blood": blood}


func test_compaction_never_changes_a_replay() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var differ: int = 0
	for n: int in 1000:
		_fresh()
		rng.seed = 91000 + n
		for _i: int in rng.randi_range(1, 14):
			var r: float = rng.randf()
			var loaded: Array[Vector2i] = _loaded()
			if r < 0.2 and not loaded.is_empty():
				var c: Vector2i = loaded[rng.randi_range(0, loaded.size() - 1)]
				# A door's key names its cell, as AirDoorSystem's does.
				_run.diff_log.record(c, DiffLog.Kind.BARRIER, "door:%d" % c.x, {"open": rng.randf() < 0.5})
			elif r < 0.35:
				var t: Vector2i = Vector2i(rng.randi_range(1, 58), 1)
				if rng.randf() < 0.8:
					_run.diff_log.mark_blood(t, rng.randi_range(0, 7))
				else:
					_run.diff_log.erase_blood(t)
			else:
				_step(rng)
		for c: Vector2i in CELLS:
			if _run.mine.native.is_loaded(c):
				_unload(c)
		var saved: PackedByteArray = _run.diff_log.store.serialise()
		var plain: Dictionary = _replayed()
		for c: Vector2i in CELLS:
			_unload(c)
		for raw: Variant in _run.inventory.world.items.keys():
			_run.registry.destroy(int(Variants.number(raw)))
		_run.inventory.world.items.clear()
		assert_true(_run.diff_log.store.deserialise(saved))
		_run.diff_log.compact(_run)
		var compacted: Dictionary = _replayed()
		if plain != compacted:
			differ += 1
			if differ <= 3:
				fail_test("sequence %d: %s != %s" % [n, plain, compacted])
	assert_eq(differ, 0, "1,000 sequences: a compacted log replays to the same state")
