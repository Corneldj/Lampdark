extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-13 (§4.3, §11.4): a carrier who is smothered, grabbed or felled drops the body where they
## stand, on their own tile, in the tick their state changes; one who disconnects has it set down
## (NET-11 calls set_down with DISCONNECTED). The carrier's hands, lamp and pace come back with it.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")

const ROWS: PackedStringArray = [
	"####################",
	"#..................#",
	"#..a.b.............#",
	"#..................#",
	"####################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


## Ann carrying Bob a few tiles east of where he fell.
func _carrying(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": FixtureMap.from_ascii(ROWS)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("a") + Vector2i(1, 0))
	s.step(1)
	L.lit_in_hand(s, ann)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(45)
	assert_true(s.run.carry.is_carrying(ann.entity_id))
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 50)
	s.step(52)
	return [s, ann, bob]


func _drop(case: String, run_seed: int) -> void:
	var parts: Array = _carrying(run_seed)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var changed_at: Array[int] = [-1]
	var ended: Array = []
	s.run.miner_state.state_changed.connect(func(entity: int, _old: int, _new: int, _cause: String) -> void:
		if entity == ann.entity_id and changed_at[0] < 0:
			changed_at[0] = s.run.tick)
	s.run.carry.carry_ended.connect(func(_c: int, _b: int, reason: StringName) -> void: ended.append([reason, s.run.tick]))
	var carrier_tile: Vector2i = s.run.registry.get_entity(ann.entity_id).tile()
	match case:
		"smothered":
			assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
		"felled":
			assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
		"grabbed":
			s.run.miner_state.enter_grabbed(ann.entity_id, &"stythe_drag", 999)
		"disconnected":
			assert_true(s.run.carry.set_down(s.run, ann.entity_id, FiremanCarry.DISCONNECTED))
			changed_at[0] = s.run.tick
	s.step(1)
	assert_eq(ended.size(), 1, case)
	var end: Array = ended[0]
	assert_eq(int(Variants.number(end[1])), changed_at[0], "%s: the same tick" % case)
	var want: StringName = FiremanCarry.GRABBED if case == "grabbed" else (FiremanCarry.DISCONNECTED if case == "disconnected" else FiremanCarry.FELLED)
	assert_eq(StringName(str(end[0])), want)
	var b: BodyState = s.run.falls.body_of(bob.entity_id)
	assert_eq(b.carried_by, 0, case)
	assert_true(b.on_floor, "%s: on the floor" % case)
	assert_eq(s.run.registry.get_entity(bob.entity_id).tile(), carrier_tile, "%s: on the carrier's own tile" % case)
	assert_false(s.run.carry.is_carrying(ann.entity_id))
	assert_false(W.belt(s, ann.entity_id).two_handed, "%s: hands free again" % case)
	s.step(5)
	assert_eq(s.run.registry.get_entity(bob.entity_id).tile(), carrier_tile, "%s: and it stays there" % case)


func test_smothered() -> void:
	_drop("smothered", 1)


func test_grabbed() -> void:
	_drop("grabbed", 2)


func test_felled() -> void:
	_drop("felled", 3)


func test_disconnected() -> void:
	_drop("disconnected", 4)
