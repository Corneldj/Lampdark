extends RefCounted
## Helpers for MNR-14's tests: a lit hall, a load laid in it heading east, and two miners taking its
## ends by holding interact as players do: Ann east of its front end, Bob west of its rear.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

const WIDTH: int = 40
## Where the load lies: its front end at x 15.5, its rear at 13.5 (a stretcher).
const CENTRE: Vector2 = Vector2(14.5, 4.5)
const ANN_TILE: Vector2i = Vector2i(16, 4)
const BOB_TILE: Vector2i = Vector2i(12, 4)


## A 40 x 9 hall of floor.
static func hall() -> FixtureMap:
	var wall: String = "#".repeat(WIDTH)
	var row: String = "#" + ".".repeat(WIDTH - 2) + "#"
	return FixtureMap.from_ascii(PackedStringArray([wall, row, row, row, row, row, row, row, wall]))


static func lit(s: Scenario, value: float = 0.6) -> void:
	var tiles: Array = []
	for y: int in range(1, 8):
		for x: int in range(1, WIDTH - 1):
			tiles.append(Vector2i(x, y))
	s.run.light.grid.add_area("emergency", LbLightGrid.COLOUR_WHITE, 0, value, tiles)


## Ann and Bob either side of a load of `kind`: [ann, bob, the load's entity].
static func setup(s: Scenario, kind: ItemKinds.Kind = ItemKinds.Kind.STRETCHER) -> Array:
	lit(s)
	var ann: MinerHandle = s.add_miner("ann", ANN_TILE)
	var bob: MinerHandle = s.add_miner("bob", BOB_TILE)
	ann.at(s.run.tick).face(180.0)
	bob.at(s.run.tick).face(0.0)
	s.step(2)
	var load: int = s.run.loads.place(s.run, kind, CENTRE, 0)
	return [ann, bob, load]


## `h` holds interact on the load in reach until the take is done, then lets go of the button.
static func take(s: Scenario, h: MinerHandle, ticks: int = 26) -> void:
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, ticks)
	s.step(ticks + 3)


static func both_take(s: Scenario, ann: MinerHandle, bob: MinerHandle) -> void:
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 26)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 26)
	s.step(29)


## Both carriers push the same way for `ticks`.
static func drive(s: Scenario, ann: MinerHandle, bob: MinerHandle, dir_deg: float, ticks: int) -> void:
	ann.at(s.run.tick).move(dir_deg, InputRecord.Gait.WALK, ticks)
	bob.at(s.run.tick).move(dir_deg, InputRecord.Gait.WALK, ticks)


static func uid_of(s: Scenario, load: int) -> int:
	return s.run.inventory.world.item_at(load).uid


static func segment(s: Scenario, load: int) -> LoadSegment:
	return s.run.loads.segment_of(s.run, uid_of(s, load))


static func knocks_since(s: Scenario, from: int) -> int:
	var n: int = 0
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from):
		if e.type == NoiseTypes.Type.CARRY_KNOCK:
			n += 1
	return n


## True if the load's capsule or a carrier overlaps rock, or a carrier is not at its end.
static func broken(s: Scenario, load: int) -> String:
	var seg: LoadSegment = segment(s, load)
	var is_solid: Callable = func(tile: Vector2i) -> bool: return not s.run.mine.native.is_walkable(tile)
	if seg.collides(seg.x, seg.y, seg.heading, is_solid):
		return "the load overlaps rock at %s" % seg.centre()
	var l: LoadCarry.Load = s.run.loads.active.get(uid_of(s, load), null)
	if l == null:
		return ""
	for pair: Array in [[l.front, seg.front_end()], [l.rear, seg.rear_end()]]:
		var carrier: int = int(Variants.number(pair[0]))
		var end: Vector2 = pair[1]
		if carrier != 0 and s.run.registry.get_entity(carrier).position.distance_to(end) > 1e-4:
			return "carrier %d is %.3f from their end" % [carrier, s.run.registry.get_entity(carrier).position.distance_to(end)]
	return ""
