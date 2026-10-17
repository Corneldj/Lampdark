extends RefCounted
## LFT-13's tests: base camp with its switchboard, phones on its floor (LFT-12's lines, given their
## roads home), Power on or off, an operator seated at the board (UI-02's seat, opened directly), and
## the operator's asks sent as the client sends them (ActionRecord.Kind.BOARD).

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const K = preload("res://tests/unit/modes/knock_off_world.gd")
const P = preload("res://tests/unit/phones/phone_world.gd")


static func cfg(run_seed: int) -> Dictionary:
	return {"seed": run_seed, "fixture": C.scenario_fixture(), "slots": 8}


## Base camp loaded, the board's cabinet made.
static func camp(s: Scenario) -> void:
	C.load_camp(s)
	s.step(2)


## Base camp's floor tile `k` (never the cage deck), in order.
static func floor_tile(s: Scenario, k: int) -> Vector2i:
	var tiles: Array[Vector2i] = K.floor_tiles(s)
	return tiles[(k * 7) % tiles.size()]


## A phone on floor tile `k`, and a caller standing beside it.
static func phone_and_caller(s: Scenario, id: String, k: int, name: String) -> Array:
	var tile: Vector2i = floor_tile(s, k)
	var p: PitPhone = P.phone(s, id, tile)
	var h: MinerHandle = s.add_miner(name, tile)
	h.brain = null
	s.run.movement.place(s.run, h.entity_id, Vector2(tile) + Vector2(0.9, 0.5))
	return [p, h]


## Seats `h` at the board (UI-02's seat, opened directly), once their miner has its place, so the
## close-up blinds them as a real sit does.
static func seat(s: Scenario, h: MinerHandle) -> void:
	s.step(2)
	s.run.closeups.open_for(s.run, h.entity_id, CloseupKind.Kind.SWITCHBOARD, "test")
	s.step(2)


static func operator(s: Scenario, name: String, k: int) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, floor_tile(s, k))
	h.brain = null
	seat(s, h)
	return h


## The operator's ask, as the close-up sends it.
static func ask(s: Scenario, op: MinerHandle, verb: BoardWire.Verb, n: int) -> void:
	op.at(s.run.tick).press(ActionRecord.Kind.BOARD, BoardWire.ask(verb, n))
	s.step(4)


## A caller's crank (a fresh hold, long enough for the 2 s).
static func crank(s: Scenario, h: MinerHandle) -> void:
	P.press(s, h, 50)


static func flaps(s: Scenario) -> PackedByteArray:
	var d: Dictionary = BoardWire.decode(s.run.switchboard.view(s.run))
	return d.get("flaps", PackedByteArray())


static func events_of(s: Scenario, type: NoiseTypes.Type) -> Array[NoiseSystem.Event]:
	return P.events_of(s, type)
