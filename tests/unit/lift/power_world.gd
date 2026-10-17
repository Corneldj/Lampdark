extends RefCounted
## Helpers for LFT-05's tests: a lit substation room (an 18 x 9 room, its fuse board at its middle,
## the trip lever and the main switch below it, 4 tiles apart in one bay, set as a fixed map sets
## them, so the trip's catch carries to the switch), miners
## beside a fixture facing it, the cutters and fuses handed out, and the steps' moves.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

const BOARD: Vector2i = Vector2i(9, 2)
const TRIP: Vector2i = Vector2i(7, 5)
const SWITCH: Vector2i = Vector2i(11, 5)
## Alone: the trip and the switch either side of one spot, a step apart.
const LONE_TRIP: Vector2i = Vector2i(8, 6)
const LONE_SWITCH: Vector2i = Vector2i(10, 6)
const LONE_SPOT: Vector2i = Vector2i(9, 6)


static func room() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("#".repeat(18))
	for y: int in 7:
		rows.append("#" + ".".repeat(16) + "#")
	rows.append("#".repeat(18))
	return FixtureMap.from_ascii(rows)


## The room lit at `value` (0.6: identity for everything in it) and the substation's fixtures in it;
## `origin` is the room's north-west tile when it stands in another cell (room_at).
static func substation(s: Scenario, alone: bool = false, value: float = 0.6, origin: Vector2i = Vector2i.ZERO) -> void:
	var tiles: Array = []
	for y: int in range(1, 8):
		for x: int in range(1, 17):
			tiles.append(origin + Vector2i(x, y))
	s.run.light.grid.add_area("emergency", LbLightGrid.COLOUR_WHITE, 0, value, tiles)
	if alone:
		s.run.power.set_anchors(origin + BOARD, origin + LONE_TRIP, origin + LONE_SWITCH)
	else:
		s.run.power.set_anchors(origin + BOARD, origin + TRIP, origin + SWITCH)
	s.step(2)


## The room committed as cell `cell` of a mine that has others (base camp's), lit when loaded;
## returns its north-west tile.
static func room_at(s: Scenario, cell: Vector2i) -> Vector2i:
	var file: Dictionary = Variants.dict(room().cells[0]).duplicate(true)
	file["cell"] = [cell.x, cell.y]
	s.run.mine.native.commit(CellFile.from_dict(file, "fixture"))
	s.run.light.grid.on_cell_loaded(cell)
	return cell * WorldIds.CELL_TILES


## A miner on the tile `side` of `place`, facing it.
static func beside(s: Scenario, name: String, place: Vector2i, side: Vector2i = Vector2i(0, 1)) -> MinerHandle:
	var facing: float = fposmod(rad_to_deg(Vector2(-side).angle()), 360.0)
	var h: MinerHandle = s.add_miner(name, place + side, {"facing_deg": facing})
	h.at(s.run.tick).face(facing)
	h.brain = null
	return h


static func give(s: Scenario, h: MinerHandle, kind: ItemKinds.Kind, count: int = 1) -> bool:
	var w: ItemWorld = s.run.inventory.world
	return s.run.inventory.give(s.run, h.entity_id, w.make(kind, count))


## Interact held from the next tick for `ticks`, then `after` more ticks stepped.
static func hold(s: Scenario, h: MinerHandle, ticks: int, after: int = 4) -> void:
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, ticks)
	s.step(ticks + after)


## The links cleared (4 s of held interact and the input's way there) and `fuses` fitted, by `h`.
static func ready_switch(s: Scenario, h: MinerHandle, fuses: int = 3) -> void:
	give(s, h, ItemKinds.Kind.WIRE_CUTTERS)
	give(s, h, ItemKinds.Kind.FUSE, fuses)
	hold(s, h, 86)
	for i: int in fuses:
		hold(s, h, 46)


## Steps until `h`'s client presents the trip's catch (the main switch's cue), then presses
## `seconds` after it on h's own timeline, as NET-06's tests do. False if the cue never shows.
static func throw_after_cue(s: Scenario, h: MinerHandle, seconds: float, after: int = 40) -> bool:
	var offset: float = seconds * Tuning.f(&"net.tick_hz")
	var since: int = s.run.tick
	for i: int in 400:
		s.step(1)
		var job: CuePress = s.run.power.main_switch
		if job == null or job.cue_tick < since:
			continue
		var want: int = TimedCues.cue_id(NoiseTypes.Type.TRIP_LEVER, job.cue_tick)
		for p: PackedInt64Array in h.connection.cues.presented:
			if p[0] != want:
				continue
			var arrived: float = float(p[1]) + p[2] / 256.0
			var stamp: PackedInt64Array = h.connection.shown_stamp(Transport.now_usec())
			if float(stamp[0]) + stamp[1] / 256.0 + 1.0 >= arrived + offset:
				h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
				s.step(after)
				return true
	return false


## Every noise event of `type` since `from`.
static func events(s: Scenario, type: NoiseTypes.Type, from: int = 0) -> Array[NoiseSystem.Event]:
	var out: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from):
		if e.type == type:
			out.append(e)
	return out


static func whats(power: PowerJob) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in power.log:
		out.append(str(e["what"]))
	return out
