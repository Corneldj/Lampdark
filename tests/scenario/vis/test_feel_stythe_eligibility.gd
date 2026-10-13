extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-07 (CRT-13 stubbed until M2): feeling the Stythe returns '[cold soot]' and raises `felt`, which
## puts the miner inside its reach for CRT-13.

const F = preload("res://tests/unit/vis/feel_world.gd")
const W = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_cold_soot() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	# The Stythe is disabled in M1 (CRT-11 onward); an entity of its kind is all feeling needs.
	var stythe: int = s.run.registry.create(WorldIds.EntityKind.STYTHE, Vector2(a) + Vector2(1.5, 0.5)).id
	var ann: MinerHandle = s.add_miner("ann", a)
	var felt: Array[Array] = []
	s.run.feel.felt.connect(func(miner: int, entity: int) -> void: felt.append([miner, entity]))
	s.step(2)
	F.feel(s, ann)
	assert_eq(str(ann.connection.feel.last_feel["caption_key"]), "feel.cold_soot", "'[cold soot]'")
	assert_eq(felt, [[ann.entity_id, stythe]], "felt, for CRT-13's eligibility")
