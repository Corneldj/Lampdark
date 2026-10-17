extends RefCounted
## MOD-05's tests: base camp loaded with saves on and every gate shut, a crew standing on its floor,
## and the knock-off driven as server_main drives it: the request, the frozen network pump while the
## members acknowledge the save, then everyone to the Pithead.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const S = preload("res://tests/scenario/net/save_world.gd")


static func cfg(run_seed: int, mode: ServerConfig.Mode = ServerConfig.Mode.FRIENDS) -> Dictionary:
	return {"seed": run_seed, "fixture": C.scenario_fixture(), "saves": true, "mode": mode}


static func camp(s: Scenario) -> void:
	C.load_camp(s)
	C.shut_all(s, true)
	s.step(2)


## Base camp's floor tiles (never the cage deck), in order, every other one.
static func floor_tiles(s: Scenario) -> Array[Vector2i]:
	var deck: Rect2i = Basecamp.deck_rect(s.run.base_camp.seed_value, s.run.base_camp.side)
	var tiles: Array[Vector2i] = []
	for raw: Variant in s.run.base_camp.inside_tiles.keys():
		var t: Vector2i = raw
		if not deck.has_point(t) and s.run.mine.native.is_walkable(t) and (t.x + t.y) % 2 == 0:
			tiles.append(t)
	tiles.sort()
	return tiles


static func miner(s: Scenario, name: String, k: int) -> MinerHandle:
	var tiles: Array[Vector2i] = floor_tiles(s)
	var h: MinerHandle = s.add_miner(name, tiles[(k * 7) % tiles.size()])
	h.brain = null
	return h


## A tile just outside base camp (beyond a gate's road), walkable.
static func outside(s: Scenario) -> Vector2i:
	for g: Dictionary in Basecamp.gate_specs(C.SEED, s.run.base_camp.side):
		var road: Vector2i = g["outside"] if g.has("outside") else Vector2i(-1, -1)
		if road.x >= 0 and s.run.mine.native.is_walkable(road):
			return road
	for x: int in range(-30, 50):
		for y: int in range(-30, 50):
			var t: Vector2i = Vector2i(x, y)
			if not s.run.base_camp.inside_tiles.has(t) and s.run.mine.native.is_walkable(t):
				return t
	return Vector2i(-1, -1)


## The knock-off as server_main drives it. Returns the refusal ("" when the crew knocked off).
static func knock_off(s: Scenario, by: String = "host") -> String:
	var why: String = s.run.knock_off.request(s.run, by, Transport.now_usec())
	if not why.is_empty():
		return why
	var members: Array[int] = []
	for session: Sessions.Session in s.net.sessions.welcomed():
		members.append(session.slot)
	var done: bool = false
	for _i: int in 200:
		for h: MinerHandle in s.miners:
			if h.connection != null:
				h.capture.tick = s.run.tick
				h.connection.poll()
		s.run.run_frozen_pump()
		if s.run.knock_off.poll(s.run, members, Transport.now_usec()):
			done = true
			break
	assert(done, "every member acknowledged the knock-off save")
	for slot: int in members:
		s.net.remove(slot, Protocol.Reject.KNOCKED_OFF)
	for _i: int in 8:
		s.run.run_frozen_pump()
		for h: MinerHandle in s.miners:
			if h.connection != null:
				h.connection.poll()
	s.run.saves.flush()
	return ""


static func knockoff_path(s: Scenario) -> String:
	return s.run.saves.run_dir().path_join(Saves.KNOCKOFF_FILE)


static func client_copy(s: Scenario, h: MinerHandle, uuid: String) -> String:
	return h.connection.saves.root.path_join(uuid.validate_filename()).path_join(SaveStore.KNOCKOFF_FILE)


## A fresh run of the same seed on base camp, resumed from the save at `path` (as server_main does:
## the camp's state attached first). Returns [scenario, restore summary].
static func resume(make: Callable, run_seed: int, path: String, mode: ServerConfig.Mode = ServerConfig.Mode.FRIENDS) -> Array:
	var opened: Dictionary = SaveResume.open_file(path)
	assert(Variants.flag(opened["ok"]), str(opened["message"]))
	var b: Scenario = make.call(cfg(run_seed, mode))
	C.load_camp(b, 0, false)
	var summary: Dictionary = SaveResume.apply(b.run, b.net, opened)
	return [b, summary]


## The items lying on base camp's bench, by kind.
static func on_bench(s: Scenario) -> Array[int]:
	var at: Vector2 = Vector2(s.run.base_camp.bench_tile()) + Vector2(0.5, 0.5)
	var out: Array[int] = []
	for id: int in s.run.registry.ids():
		var it: Item = s.run.inventory.world.item_at(id)
		if it != null and s.run.registry.get_entity(id).position.distance_to(at) < 0.01:
			out.append(it.kind)
	out.sort()
	return out
