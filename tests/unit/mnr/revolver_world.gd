extends RefCounted
## MNR-16's tests: a long lit hall (a 30-tile road, three rows wide), a miner with the revolver on
## the belt or drawn, aim held, triggers pressed.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


static func hall(width: int = 34) -> FixtureMap:
	var wall: String = "#".repeat(width)
	var row: String = "#" + ".".repeat(width - 2) + "#"
	return FixtureMap.from_ascii(PackedStringArray([wall, row, row, row, wall]))


static func lit(s: Scenario, width: int = 34, value: float = 0.6) -> void:
	var tiles: Array = []
	for y: int in range(1, 4):
		for x: int in range(1, width - 1):
			tiles.append(Vector2i(x, y))
	s.run.light.grid.add_area("emergency", LbLightGrid.COLOUR_WHITE, 0, value, tiles)


static func miner(s: Scenario, name: String, tile: Vector2i, facing_deg: float = 0.0) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, tile, {"facing_deg": facing_deg})
	h.brain = null
	h.at(s.run.tick).face(facing_deg)
	return h


## The revolver straight into her free hand (six rounds unless given), and a box on the belt.
static func armed(s: Scenario, h: MinerHandle, rounds: int = -1, box: int = 0) -> Item:
	var it: Item = Revolver.make(s.run, rounds)
	var belt: HandsAndBelt = s.run.inventory.hands_of(h.entity_id)
	belt.free_hand = it
	if box > 0:
		belt.slots[1] = s.run.inventory.world.make(ItemKinds.Kind.ROUNDS, box)
	return it


## Aim held from now for `ticks`.
static func aim(s: Scenario, h: MinerHandle, ticks: int = 400) -> void:
	h.at(s.run.tick).hold(InputRecord.HOLD_AIM, ticks)


static func trigger(s: Scenario, h: MinerHandle, aim_deg: float = 0.0, at_tick: int = -1) -> void:
	h.at(at_tick if at_tick >= 0 else s.run.tick).press(ActionRecord.Kind.TRIGGER, 0, aim_deg)
