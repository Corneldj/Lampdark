extends RefCounted
## Helpers for LFT-10's tests: base camp ready to leave (every job but Start done, the tank full and
## the engine running, its run-up done or not), miners aboard by the cord facing it, their pulls, and
## miners elsewhere in base camp.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const E = preload("res://tests/unit/lift/engine_world.gd")


## Base camp with the engine running since `running_s` ago (default: past its run-up).
static func ready(s: Scenario, running_s: float = -1.0, kind: RepairList.Kind = RepairList.Kind.SHORT) -> void:
	E.ready(s, kind)
	var engine: WinderEngine = s.run.engine
	var ran: float = running_s if running_s >= 0.0 else Tuning.f(&"lift.clutch_run_up_s") + 1.0
	engine.state = WinderEngine.State.RUNNING
	engine.caught_at = s.run.tick - roundi(ran * Tuning.f(&"net.tick_hz"))
	s.step(2)


## Deck tiles within touch range of the cord, nearest first.
static func cord_tiles(s: Scenario) -> Array[Vector2i]:
	var deck: Rect2i = s.run.cage.deck
	var cord: Vector2 = s.run.cage.cord_point
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var out: Array[Vector2i] = []
	for y: int in range(deck.position.y, deck.end.y):
		for x: int in range(deck.position.x, deck.end.x):
			if (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(cord) <= reach:
				out.append(Vector2i(x, y))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_to(cord) < (Vector2(b) + Vector2(0.5, 0.5)).distance_to(cord))
	return out


## A deck tile out of the cord's reach (the far end).
static func far_deck_tile(s: Scenario) -> Vector2i:
	var deck: Rect2i = s.run.cage.deck
	var cord: Vector2 = s.run.cage.cord_point
	var best: Vector2i = deck.position
	for y: int in range(deck.position.y, deck.end.y):
		for x: int in range(deck.position.x, deck.end.x):
			if (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(cord) > (Vector2(best) + Vector2(0.5, 0.5)).distance_to(cord):
				best = Vector2i(x, y)
	return best


## A miner aboard on the `k`th tile by the cord, facing it.
static func aboard(s: Scenario, name: String, k: int = 0) -> MinerHandle:
	var tiles: Array[Vector2i] = cord_tiles(s)
	var t: Vector2i = tiles[k % tiles.size()]
	var h: MinerHandle = s.add_miner(name, t)
	face(s, h, t)
	s.step(2)
	return h


## A miner in base camp off the deck (on the floor tile nearest the medbay's first table).
static func at_home(s: Scenario, name: String) -> MinerHandle:
	var t: Vector2i = s.run.base_camp.medbay_tables()[0]
	var h: MinerHandle = s.add_miner(name, t)
	s.step(1)
	return h


static func face(s: Scenario, h: MinerHandle, from_tile: Vector2i) -> void:
	var to: Vector2 = s.run.cage.cord_point - (Vector2(from_tile) + Vector2(0.5, 0.5))
	h.at(s.run.tick).face(rad_to_deg(to.angle()))


## One interact on the cord.
static func pull(s: Scenario, h: MinerHandle) -> void:
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
	s.step(4)


## `h` stepped onto another deck tile (or anywhere), keeping its vote while aboard.
static func move_to(s: Scenario, h: MinerHandle, tile: Vector2i) -> void:
	s.run.movement.place(s.run, h.entity_id, Vector2(tile) + Vector2(0.5, 0.5))
	s.step(1)


static func bells(s: Scenario, from: int = 0) -> Array[NoiseSystem.Event]:
	return E.events(s, NoiseTypes.Type.HOLD_BELL, from)


static func bell_ticks() -> int:
	return roundi(Tuning.f(&"lift.hold_bell_s") * Tuning.f(&"net.tick_hz"))
