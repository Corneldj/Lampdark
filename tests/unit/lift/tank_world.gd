extends RefCounted
## Helpers for LFT-06's tests: base camp loaded, the run's list set, a miner standing at the tank's
## filler with a paraffin can in the free hand, and her pours.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const C = preload("res://tests/scenario/basecamp/camp_world.gd")


## Base camp and a list of `kind` (Short 2 cans, Standard 4, Full 6).
static func camp(s: Scenario, kind: RepairList.Kind = RepairList.Kind.STANDARD) -> void:
	C.load_camp(s)
	s.run.repair.set_list(RepairList.for_run(s.run.header.run_seed, kind, false))
	s.step(2)


## A walkable floor tile inside base camp from which the filler is in touch range.
static func beside_filler(s: Scenario) -> Vector2i:
	var filler: Vector2 = s.run.fuel.filler
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var t: Vector2i = Vector2i(floori(filler.x), floori(filler.y)) + Vector2i(dx, dy)
			var d: float = (Vector2(t) + Vector2(0.5, 0.5)).distance_to(filler)
			if d > 0.0 and d <= reach and d < best_d and s.run.mine.native.is_walkable(t):
				best = t
				best_d = d
	return best


## A miner at the filler, facing it.
static func at_filler(s: Scenario, name: String) -> MinerHandle:
	var tile: Vector2i = beside_filler(s)
	var h: MinerHandle = s.add_miner(name, tile)
	var toward: Vector2 = s.run.fuel.filler - (Vector2(tile) + Vector2(0.5, 0.5))
	h.at(s.run.tick).face(rad_to_deg(toward.angle()))
	s.step(3)
	return h


## A can of `fills` straight into `h`'s free hand.
static func can_in_hand(s: Scenario, h: MinerHandle, fills: float = 4.0) -> Item:
	var can: Item = s.run.inventory.world.make(ItemKinds.Kind.PARAFFIN_CAN, 1, {"fills": fills})
	s.run.inventory.hands_of(h.entity_id).free_hand = can
	return can


## Holds interact for `ticks` (then lets go) and steps on.
static func hold(s: Scenario, h: MinerHandle, ticks: int, after: int = 4) -> void:
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, ticks)
	s.step(ticks + after)
