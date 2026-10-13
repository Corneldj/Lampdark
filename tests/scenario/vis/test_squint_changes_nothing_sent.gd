extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-01 (FND-09): squinting moves only the client's view. Two runs with identical inputs except
## Ann's squint (held for 2 s, while she walks and turns among lit lamps, a teammate and a sleeping
## Moth) give byte-identical streams to every client: VIS-03 sends detail out to the full-squint view
## whether or not anyone squints, and the cone and the listener sit on the miner.

const FW = preload("res://tests/scenario/vis/flame_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _run(squint: bool, turn_deg: float = 300.0) -> Array[String]:
	var s: Scenario = make({"seed": 71, "fixture": FW.hall(50)})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 3), {"facing_deg": 0.0})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(18, 2))
	ann.at(0).lamp(false, LampRules.WICK_UP)
	s.step(1)
	L.lit_in_hand(s, ann, LampRules.WICK_UP)
	for x: int in [22, 30, 38]:
		FW.lamp(s, Vector2i(x, 1 + x % 3))
	s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(44, 3))
	ann.at(5).move(0.0, InputRecord.Gait.WALK, 30).face(20.0)
	ann.at(40).face(turn_deg).move(270.0, InputRecord.Gait.WALK, 10)
	if squint:
		ann.at(10).hold(InputRecord.HOLD_SQUINT, 40)
	s.step(90)
	return [s.client(ann).digest(), s.client(bob).digest(), str(s.client(ann).raw().size())] as Array[String]


func test_byte_identical_streams() -> void:
	var plain: Array[String] = _run(false)
	var squinting: Array[String] = _run(true)
	assert_ne(plain[2], "0", "frames were sent")
	assert_eq(squinting[0], plain[0], "Ann, who squinted, receives exactly the same bytes")
	assert_eq(squinting[1], plain[1], "and so does Bob")
	# The control: a real difference (Ann turns another way) does change what she receives.
	var turned: Array[String] = _run(false, 120.0)
	assert_ne(turned[0], plain[0], "the comparison sees real changes")
