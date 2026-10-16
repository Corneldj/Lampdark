extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-14 (Gameplay §12.2; GDD §15.8): a 2-tile stretcher carried by two jams at a 1-wide
## right-angled corner and passes a 2-wide one. Both carriers steer it as a pair would, toward a
## point 1.5 tiles ahead along the corridor's middle; every tick the load and both carriers stay
## out of the rock, and each carrier stands at their end.

const W = preload("res://tests/unit/mnr/load_world.gd")

## East along row 1, then south down column 11.
const ONE_WIDE: PackedStringArray = [
	"##############",
	"#...........##",
	"###########.##",
	"###########.##",
	"###########.##",
	"###########.##",
	"###########.##",
	"###########.##",
	"###########.##",
	"###########.##",
	"##############",
]
## East along rows 1-2, then south down columns 10-11.
const TWO_WIDE: PackedStringArray = [
	"##############",
	"#...........##",
	"#...........##",
	"##########..##",
	"##########..##",
	"##########..##",
	"##########..##",
	"##########..##",
	"##########..##",
	"##########..##",
	"##############",
]
const AHEAD: float = 1.5


func before_all() -> void:
	assert_true(Tuning.load_server())


## The stretcher at `start` heading east, Ann and Bob holding its ends: [s, ann, bob, load].
func _carry(run_seed: int, picture: PackedStringArray, start: Vector2) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": FixtureMap.from_ascii(picture)})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(6, 1))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(2, 1))
	ann.at(s.run.tick).face(180.0)
	bob.at(s.run.tick).face(0.0)
	s.step(2)
	var load: int = s.run.loads.place(s.run, ItemKinds.Kind.STRETCHER, start, 0)
	assert_ne(load, 0)
	W.both_take(s, ann, bob)
	assert_true(s.run.loads.carrying(ann.entity_id) and s.run.loads.carrying(bob.entity_id), "both ends taken")
	return [s, ann, bob, load]


## The point `AHEAD` tiles on along the path past the nearest point to `at`.
static func _pursue(path: Array[Vector2], at: Vector2) -> Vector2:
	var best_s: float = 0.0
	var best_d: float = INF
	var total: float = 0.0
	for i: int in path.size() - 1:
		var ab: Vector2 = path[i + 1] - path[i]
		var u: float = clampf((at - path[i]).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var p: Vector2 = path[i] + ab * u
		if p.distance_to(at) < best_d:
			best_d = p.distance_to(at)
			best_s = total + ab.length() * u
		total += ab.length()
	var want: float = minf(best_s + AHEAD, total)
	var run_s: float = 0.0
	for i: int in path.size() - 1:
		var l: float = path[i].distance_to(path[i + 1])
		if want <= run_s + l:
			return path[i].lerp(path[i + 1], (want - run_s) / l)
		run_s += l
	return path[path.size() - 1]


## Steers for `ticks`; returns the tick the load's centre first passed `past_y` (-1 if never) and
## every fault seen.
func _steer(s: Scenario, ann: MinerHandle, bob: MinerHandle, load: int, path: Array[Vector2], past_y: float, ticks: int) -> Array:
	var faults: Array[String] = []
	var passed: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		var why: String = W.broken(sc, load)
		if not why.is_empty():
			faults.append("tick %d: %s" % [sc.run.tick, why])
		var c: Vector2 = W.segment(sc, load).centre()
		if passed[0] < 0 and c.y > past_y:
			passed[0] = sc.run.tick
		var dir: float = rad_to_deg((_pursue(path, c) - c).angle())
		ann.at(sc.run.tick).move(dir, InputRecord.Gait.WALK, 1)
		bob.at(sc.run.tick).move(dir, InputRecord.Gait.WALK, 1)
	s.step(ticks)
	s.on_tick = Callable()
	return [passed[0], faults]


func test_a_stretcher_jams_at_a_1_wide_corner() -> void:
	var w: Array = _carry(1501, ONE_WIDE, Vector2(4.5, 1.5))
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var load: int = w[3]
	var from: int = s.run.noise.event_log.size()
	var path: Array[Vector2] = [Vector2(4.5, 1.5), Vector2(11.5, 1.5), Vector2(11.5, 9.5)]
	var out: Array = _steer(s, ann, bob, load, path, 3.5, 400)
	var passed: int = int(Variants.number(out[0]))
	var faults: Array[String] = out[1]
	assert_eq(passed, -1, "20 s of steering: never round the corner")
	assert_eq(faults, [] as Array[String], "never in the rock, always at their ends")
	var seg: LoadSegment = W.segment(s, load)
	gut.p("jammed at %s heading %.1f°" % [seg.centre(), seg.heading * 360.0 / 65536.0])
	assert_gt(seg.x, 9.5, "it got as far as the corner")
	assert_eq(W.knocks_since(s, from), 0, "a jam is no knock")


func test_a_stretcher_passes_a_2_wide_corner() -> void:
	var w: Array = _carry(1502, TWO_WIDE, Vector2(4.5, 2.0))
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var load: int = w[3]
	var path: Array[Vector2] = [Vector2(4.5, 2.0), Vector2(11.0, 2.0), Vector2(11.0, 9.5)]
	var out: Array = _steer(s, ann, bob, load, path, 4.5, 400)
	var passed: int = int(Variants.number(out[0]))
	var faults: Array[String] = out[1]
	assert_gt(passed, 0, "round the corner and down the far side")
	gut.p("past the corner after %d ticks" % (passed - s.run.tick + 400))
	assert_eq(faults, [] as Array[String], "never in the rock, always at their ends")
	assert_gt(W.segment(s, load).y, 7.0, "well down the second leg")
