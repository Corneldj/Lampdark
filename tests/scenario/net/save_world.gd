extends RefCounted
## NET-09's scenarios: a small room with saves on, a crew that stands still, the first snapshot,
## falls and deaths after it, and a fresh run of the same seed resumed from the files on disk.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const B = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


static func cfg(run_seed: int, mode: ServerConfig.Mode = ServerConfig.Mode.FRIENDS) -> Dictionary:
	return {"seed": run_seed, "fixture": B.room(), "saves": true, "mode": mode}


## Removes a seed's saves (the server's and every member's) left by an earlier run of the test.
static func clear(run_seed: int) -> void:
	for root: String in ["user://kit_saves/%d" % run_seed, "user://kit_client_saves/%d" % run_seed]:
		_remove_tree(ProjectSettings.globalize_path(root))


static func _remove_tree(path: String) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	for sub: String in d.get_directories():
		_remove_tree(path.path_join(sub))
	for f: String in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


static func miner(s: Scenario, name: String, tile: Vector2i) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, tile)
	h.brain = null
	return h


## Steps until the run has written `n` saves; false if not within `ticks`.
static func until_saved(s: Scenario, n: int, ticks: int = 700) -> bool:
	return s.run_until(func(sc: Scenario) -> bool: return sc.run.saves.written.size() >= n, ticks)


static func snapshot_path(s: Scenario) -> String:
	return s.run.saves.run_dir().path_join(Saves.SNAPSHOT_FILE)


## The server is killed: nothing more runs; what reached the disk is all there is.
static func kill(s: Scenario) -> void:
	s.run.saves.flush()
	s.close()


## A fresh run of the same seed, resumed from the save at `path`. Returns [scenario, restore summary].
static func resume(make: Callable, run_seed: int, path: String, mode: ServerConfig.Mode = ServerConfig.Mode.FRIENDS) -> Array:
	var opened: Dictionary = SaveResume.open_file(path)
	assert(Variants.flag(opened["ok"]), str(opened["message"]))
	var b: Scenario = make.call(cfg(run_seed, mode))
	var summary: Dictionary = SaveResume.apply(b.run, b.net, opened)
	return [b, summary]


## Where a lamp item is now: {where, holder, tile, lit}, or {} when nowhere.
static func lamp_place(s: Scenario, uid: int) -> Dictionary:
	for kind: ItemKinds.Kind in [ItemKinds.Kind.GAUZE_LAMP, ItemKinds.Kind.ELECTRIC_LAMP]:
		for place: Dictionary in ItemPlaces.of_kind(s.run, kind):
			var it: Item = place["item"]
			if it.uid == uid:
				var at: Vector2 = place["position"]
				return {"where": str(place["where"]), "holder": int(Variants.number(place["holder"])),
					"tile": Vector2i(floori(at.x), floori(at.y)), "lit": Variants.flag(it.state.get("lit", false))}
	return {}


## A belt's contents as [kind, uid] per slot (null for an empty one).
static func belt(s: Scenario, entity: int) -> Array:
	var out: Array = []
	for it: Item in s.run.inventory.hands_of(entity).slots:
		out.append([it.kind, it.uid] if it != null else null)
	return out



## A registry section's entities (id, kind, position, flags), without its id counter.
static func entities(bytes: PackedByteArray) -> Array:
	var r: SimStateReader = SimStateReader.new(bytes)
	r.get_i64()
	var out: Array = []
	for _i: int in r.get_i64():
		out.append([r.get_i64(), r.get_i32(), r.get_f64(), r.get_f64(), r.get_i32()])
	return out
