extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-01: two medbay tables (one body each), the cupboard with one kit, and the bench.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_medbay() -> void:
	var s: Scenario = make({"seed": 7, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s, 2)
	assert_eq(camp.medbay_tables().size(), 2, "two tables")
	assert_eq(camp.cupboard().kits, 1, "one kit at run start")
	assert_true(camp.cupboard().take_kit())
	assert_false(camp.cupboard().take_kit(), "then none")
	var table: Vector2i = camp.medbay_tables()[0]
	assert_true(camp.medbay.lay(table, 41))
	assert_false(camp.medbay.lay(table, 42), "one body a table")
	assert_true(Basecamp.is_inside_base_camp(C.SEED, camp.bench_tile(), 2), "the bench is inside")
