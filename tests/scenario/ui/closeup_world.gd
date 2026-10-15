extends RefCounted
## UI-02's scenarios: base camp loaded (LFT-01), miners beside its map table, Manual lectern or
## switchboard seat, and the asks a client sends.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const FIXTURE: Dictionary = {CloseupKind.Kind.MAP_TABLE: "map_table", CloseupKind.Kind.MANUAL: "manual_lectern",
	CloseupKind.Kind.SWITCHBOARD: "switchboard_seat"}


static func camp(seed_value: int, scenario_test: Object) -> Scenario:
	var s: Scenario = scenario_test.call(&"make", {"seed": seed_value, "fixture": C.scenario_fixture()})
	C.load_camp(s)
	return s


static func fixture_tile(s: Scenario, kind: CloseupKind.Kind) -> Vector2i:
	var anchors: Array[Dictionary] = Basecamp.fixture(C.SEED, str(FIXTURE[kind]), s.run.base_camp.side)
	return anchors[0]["position"]


## A miner on a walkable tile in touch range of the fixture, facing it, `nth` ones further round.
static func beside(s: Scenario, name: String, kind: CloseupKind.Kind, nth: int = 0) -> MinerHandle:
	var t: Vector2i = fixture_tile(s, kind)
	var found: int = 0
	for off: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(-1, 1),
			Vector2i(1, -1), Vector2i(-1, -1)]:
		if not s.run.mine.native.is_walkable(t + off):
			continue
		if found < nth:
			found += 1
			continue
		var facing: float = fposmod(rad_to_deg(Vector2(-off).angle()), 360.0)
		return s.add_miner(name, t + off, {"facing_deg": facing})
	return null


## An interact held for `ticks` from the next tick (the table and the Manual open on the press).
static func interact(s: Scenario, h: MinerHandle, ticks: int = 2) -> void:
	h.at(s.run.tick + 1).hold(InputRecord.HOLD_INTERACT, ticks)


static func ask(s: Scenario, h: MinerHandle, what: CloseupKind.Ask) -> void:
	h.at(s.run.tick + 1).press(ActionRecord.Kind.CLOSE_UP, what)


static func kind_of(s: Scenario, h: MinerHandle) -> CloseupKind.Kind:
	return s.run.closeups.kind_of(h.entity_id)
