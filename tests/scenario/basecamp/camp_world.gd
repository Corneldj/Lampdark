extends RefCounted
## Helpers for LFT-01: base camp's cell and its three gate-road cells loaded into a scenario's
## mine, and the base camp state attached.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const B = preload("res://tests/scenario/world/basecamp_world.gd")

const SEED: int = 77


static func load_camp(s: Scenario, side: int = 0, fresh: bool = true) -> BaseCampState:
	s.run.mine.native.unload(Vector2i(0, 0))
	s.run.mine.native.commit(Basecamp.cell_data(SEED, side))
	for g: Dictionary in Basecamp.gate_specs(SEED, side):
		var road: Array = B.road_cell(g)
		var cell: Vector2i = road[0]
		var raw: PackedStringArray = road[1]
		s.run.mine.native.commit(CellFile.from_dict(B.cell_file(cell, Basecamp.apply_gate_arches(SEED, cell, raw, side)), "road"))
	for c: Vector2i in s.run.mine.native.loaded_cells():
		s.run.light.grid.on_cell_loaded(c)
	return BaseCampState.attach(s.run, SEED, side, fresh)


static func scenario_fixture() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#"]))


static func shut_all(s: Scenario, shut: bool = true) -> void:
	for g: Dictionary in Basecamp.gate_specs(SEED, s.run.base_camp.side):
		s.run.mine.native.set_barrier(Vector2i.ZERO, int(Variants.number(g["barrier"])), not shut)


## LFT-02: a gate's lever tile ("inside" or "outside").
static func lever(s: Scenario, side: String, which: String) -> Vector2i:
	return s.run.base_camp.gate_system.gate(side).levers[which]


## LFT-02: every gate clang emitted so far, from SND-02's true-world log.
static func clangs(s: Scenario) -> Array[NoiseSystem.Event]:
	var out: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if e.type == NoiseTypes.Type.GATE:
			out.append(e)
	return out


## LFT-02: a body standing in for Bess (or any non-miner body) on a tile.
static func place_body(s: Scenario, kind: WorldIds.EntityKind, at: Vector2) -> int:
	return s.run.registry.create(kind, at).id
