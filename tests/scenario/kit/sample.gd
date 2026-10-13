extends RefCounted
## FND-09's sample scenario, shared by the sample, determinism and replay tests: two rooms
## joined by a gate, with coal, brick, timber and an air door; two miners with scripted inputs.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")

const ROWS: PackedStringArray = [
	"#########################",
	"#a......#...............#",
	"#.......G.....CCC.......#",
	"#.......#.....CCC...b...#",
	"#########...............#",
	"#BBBBBBB#....TTTT.......#",
	"#.......D...............#",
	"#########################",
]
const SEED: int = 0x5A3F1E


static func fixture() -> FixtureMap:
	return FixtureMap.from_ascii(ROWS)


## Ann walks east, turns, feels, then chalks; Bob calls out, runs west and talks.
static func build(cfg: Dictionary = {}) -> Scenario:
	var base: Dictionary = {"seed": SEED, "fixture": fixture()}
	base.merge(cfg, true)
	var s: Scenario = Scenario.create(base)
	var f: FixtureMap = s.fixture
	var ann: MinerHandle = s.add_miner("ann", f.spot("a"), {"facing_deg": 0.0})
	var bob: MinerHandle = s.add_miner("bob", f.spot("b"), {"facing_deg": 180.0})
	ann.at(1).move(0.0, InputRecord.Gait.WALK, 10).face(90.0).hold(InputRecord.HOLD_FEEL, 6) \
		.press(ActionRecord.Kind.CHALK, 4)
	bob.at(3).callout(7, 2)
	bob.at(5).move(180.0, InputRecord.Gait.RUN, 5).say(1, 4)
	return s
