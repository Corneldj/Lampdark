extends RefCounted
## Helpers for CRT-08: a long road along row 2 in rock, a listener in the rock at (0, 1) whose
## open tile is (1, 2), and voice-band events at a distance along the road.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


static func road(length: int = 60) -> FixtureMap:
	var w: int = length + 2
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(w), "#".repeat(w), "#" + ".".repeat(length) + "#",
		"#".repeat(w), "#".repeat(w)]))


## A Tapper's hearing alone, listening from the rock above the road's west end.
static func ears(s: Scenario) -> TapperHearing:
	var h: TapperHearing = TapperHearing.new(s.run, Tapper.LISTENER_BASE + 1)
	h.listen_from(Vector2(1.5, 1.5))
	return h


## A voice-band event of `np` at `tiles` tiles of road from the listening tile (1, 2).
static func voice(s: Scenario, tiles: int, np: float) -> void:
	s.run.noise.emit(NoiseTypes.Type.VOICE, Vector2i(1 + tiles, 2), {"level_np": np, "mode": RoadGraphService.MODE_VOICE, "voice_id": 0})


static func heard_now(s: Scenario, h: TapperHearing) -> int:
	s.step(1)
	return h.take().size()


## A 60 x 36 block: roads along rows 4 and 31 and a cross road at column 50, with thick rock
## between (rich rock), a brick-lined room at the east end of the north road, and spots a-d.
static func block() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 36:
		var row: String = "#".repeat(60)
		if y == 4 or y == 31:
			row = "#" + ".".repeat(58) + "#"
		elif y > 4 and y < 31:
			row = "#".repeat(50) + "." + "#".repeat(9)
		rows.append(row)
	for y: int in range(1, 4):
		rows[y] = "#".repeat(40) + "BBBBBBBBBB" + "#".repeat(10)
	rows[2] = "#".repeat(40) + "B........B" + "#".repeat(10)
	rows[3] = "#".repeat(40) + "B........B" + "#".repeat(10)
	rows[4] = rows[4].substr(0, 2) + "a" + rows[4].substr(3, 27) + "b" + rows[4].substr(31)
	rows[31] = rows[31].substr(0, 2) + "c" + rows[31].substr(3, 27) + "d" + rows[31].substr(31)
	return FixtureMap.from_ascii(rows)


static func tapper(s: Scenario, at: Vector2i) -> Tapper:
	s.place_creature(WorldIds.EntityKind.TAPPER, at)
	var t: Tapper = s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER)
	return t
