extends GutTest
## NET-09, found by MOD-05's hosted resume: a save's 64-bit values come back exact. A run's seed and
## every random stream's state use all 64 bits, past a double's 53: read through Variants.number they
## came back rounded, so a resumed generated mine refused its own plan ("another seed's") and every
## stream drew differently after a resume. They are read through Variants.whole.

## A seed a hosted run drew, well past 2^53.
const SEED: int = -6327166314039434197
const KEYS: Array[int] = [1]


func _stream(run: RunState) -> LbRng:
	return run.stream(HashDomain.HANDS, PackedInt64Array(KEYS))


func test_a_restored_stream_draws_as_if_it_never_stopped() -> void:
	var played: RunState = RunState.create(SEED, ServerConfig.Mode.FRIENDS, true)
	var rng: LbRng = _stream(played)
	for i: int in 3:
		rng.next_u64()
	assert_gt(absi(rng.get_state()), 1 << 53, "a state a double cannot hold")
	var saved: Dictionary = Variants.dict(bytes_to_var(var_to_bytes(played.stream_states())))  # as a save holds it
	var asked_after: RunState = RunState.create(SEED, ServerConfig.Mode.FRIENDS, true)
	asked_after.restore_streams(saved)
	var asked_before: RunState = RunState.create(SEED, ServerConfig.Mode.FRIENDS, true)
	var early: LbRng = _stream(asked_before)
	asked_before.restore_streams(saved)
	var want: int = rng.next_u64()
	assert_eq(_stream(asked_after).next_u64(), want, "a stream asked for after the restore picks up where it was")
	assert_eq(early.next_u64(), want, "and one that already existed")


func test_a_saved_seed_comes_back_whole() -> void:
	var head: Dictionary = Variants.dict(bytes_to_var(var_to_bytes({"run_seed": SEED})))
	assert_eq(Variants.whole(head["run_seed"]), SEED)
	assert_ne(int(Variants.number(head["run_seed"])), SEED, "a double rounds it (why every 64-bit value is read whole)")
	var src: String = FileAccess.get_file_as_string("res://server/server_main.gd")
	assert_true(src.contains("RunState.create(Variants.whole(head[\"run_seed\"])"), "the server resumes the save's own seed")
