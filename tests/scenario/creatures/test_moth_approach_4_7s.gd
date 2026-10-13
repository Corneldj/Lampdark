extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-04: a lit miner standing 20 tiles down a straight road is smothered no sooner than 94 ticks
## after the first dust (18.5 tiles at 5.0 tiles/s, then the 1.0 s wind-up).

const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_approach() -> void:
	var s: Scenario = make({"seed": 41, "fixture": A.road(60)})
	var m: Moth = A.awake(s, Vector2i(10, 2), true)
	var first_dust: int = -1
	for e: Dictionary in s.run.creatures.log.of_type(&"tell"):
		if str(e.get("kind", "")) == "moth_awake":
			first_dust = int(Variants.number(e["tick"]))
	assert_gte(first_dust, 0, "the awake tell began at waking")
	var ann: MinerHandle = A.lit_miner(s, "ann", Vector2i(30, 2))
	assert_gte(A.until_state(s, m, &"linger", 400), 0)
	var smother: Array[Dictionary] = s.run.creatures.log.of_type(&"moth_smother")
	assert_eq(smother.size(), 1)
	var landed: int = int(Variants.number(smother[0]["tick"]))
	gut.p("first dust at %d, smothered at %d: %d ticks (%.2f s)" % [first_dust, landed, landed - first_dust, (landed - first_dust) / 20.0])
	assert_gte(landed - first_dust, 94, "no sooner than 4.7 s")
	assert_eq(A.life(s, ann.entity_id), MinerTransitions.Life.UNCONSCIOUS)
