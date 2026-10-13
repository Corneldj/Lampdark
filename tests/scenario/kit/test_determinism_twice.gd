extends "res://tests/scenario/kit/scenario_test.gd"
## FND-09: a scenario run twice gives identical per-tick state hashes and identical bytes for
## every client, and the sample's final hash is the same on every platform (golden file).

const Sample = preload("res://tests/scenario/kit/sample.gd")
const GOLDEN: String = "res://tests/fixtures/kit/sample_final_hash.txt"
const TICKS: int = 80


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_sample_twice() -> void:
	var result: Dictionary = Scenario.assert_deterministic(func() -> Scenario: return Sample.build(), TICKS)
	assert_true(Variants.flag(result["ok"]), "identical runs (first mismatch at tick %d)" % int(Variants.number(result["mismatch_tick"])))
	assert_true(Variants.flag(result["digests_equal"]), "identical bytes for every client")
	var final_hash: String = str(result["final_hash"])
	gut.p("sample final state hash after %d ticks: %s" % [TICKS, final_hash])
	var golden: String = FileAccess.get_file_as_string(GOLDEN).strip_edges()
	assert_eq(final_hash, golden, "the sample's final hash matches %s on this platform; if a change to the state is intended, write the new hash there" % GOLDEN)


func test_lossy_links_replay_exactly_too() -> void:
	var build: Callable = func() -> Scenario:
		var s: Scenario = Sample.build({"seed": 99})
		s.miners[0].link(120, 10.0)
		s.miners[1].link(40, 2.0)
		return s
	var result: Dictionary = Scenario.assert_deterministic(build, TICKS)
	assert_true(Variants.flag(result["ok"]), "seeded loss and delay replay exactly")


func test_a_different_seed_changes_the_tokens() -> void:
	var a: Scenario = make({"seed": 1})
	var b: Scenario = make({"seed": 2})
	var ha: MinerHandle = a.add_miner("x", Vector2i(1, 1))
	var hb: MinerHandle = b.add_miner("x", Vector2i(1, 1))
	assert_ne(ha.connection.session_token, hb.connection.session_token, "tokens come from the scenario's seed")
