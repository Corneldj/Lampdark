extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-12 (Gameplay §6.6, §12.5, §12.7): every phone's painted number is unique in the run, the next
## of the seed's own shuffle of 1 to phones.line_number_max as phones first generate, so a number
## says nothing of where. A phone met again (its cell evicted and back) keeps its number; a resume
## brings every number back and goes on with the pool. Past the pool's end a phone is dead and
## unnumbered.

const P = preload("res://tests/unit/phones/phone_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _shuffle(run_seed: int) -> Array:
	var pool: Array = []
	for i: int in Tuning.i(&"phones.line_number_max"):
		pool.append(i + 1)
	LbRng.from_seed(LbHash.sub_seed(run_seed, HashDomain.PHONES, PackedInt64Array([0]), 0)).shuffle(pool)
	return pool


func test_unique_from_the_seeded_shuffle() -> void:
	var s: Scenario = make({"seed": 4201, "fixture": P.road()})
	var want: Array = _shuffle(4201)
	var got: Array = []
	for i: int in 6:
		got.append(P.phone(s, "p%d" % i, Vector2i(3 + 5 * i, 1)).number)
	assert_eq(got, want.slice(0, 6), "the seed's shuffle, in the order they generated")
	var seen: Dictionary = {}
	for n: Variant in got:
		assert_false(seen.has(n), "%s is unique" % n)
		seen[n] = true
	assert_ne(got, [1, 2, 3, 4, 5, 6], "shuffled: the numbers say nothing of where")
	var other: Scenario = make({"seed": 4202, "fixture": P.road()})
	var first: int = int(Variants.number(got[0]))
	assert_ne(P.phone(other, "p0", Vector2i(3, 1)).number, first, "another seed, another shuffle")
	# Met again, as its cell comes back: as it was.
	var again: PitPhone = s.run.phones.meet(s.run, "p2", Vector2i(13, 1))
	var third: int = int(Variants.number(got[2]))
	assert_eq(again.number, third, "a phone met again keeps its number")
	assert_eq(s.run.phones.next_number, 6, "and takes none from the pool")


func test_a_resume_keeps_every_number() -> void:
	var s: Scenario = make({"seed": 4203, "fixture": P.road()})
	for i: int in 3:
		P.phone(s, "p%d" % i, Vector2i(3 + 5 * i, 1))
	var saved: Dictionary = Variants.dict(bytes_to_var(var_to_bytes(s.run.phones.save_state())))
	var b: Scenario = make({"seed": 4203, "fixture": P.road()})
	b.run.phones.load_state(b.run, saved)
	for i: int in 3:
		var now: PitPhone = b.run.phones.phones["p%d" % i]
		var was: PitPhone = s.run.phones.phones["p%d" % i]
		assert_eq(now.number, was.number, "p%d as it was" % i)
	var next: int = int(Variants.number(_shuffle(4203)[3]))
	assert_eq(P.phone(b, "p3", Vector2i(18, 1)).number, next, "and the pool goes on where it was")


func test_past_the_pool_a_phone_is_dead_and_unnumbered() -> void:
	var s: Scenario = make({"seed": 4204, "fixture": P.road(), "overrides": {"phones.line_number_max": 2}})
	P.power(s)
	P.phone(s, "a", Vector2i(3, 1))
	P.phone(s, "b", Vector2i(8, 1))
	var c: PitPhone = P.phone(s, "c", Vector2i(13, 1))
	assert_eq(c.number, 0, "the pool ran out: unnumbered")
	assert_false(s.run.phones.live(s.run, c), "and dead")
	var a: PitPhone = s.run.phones.phones["a"]
	assert_true(s.run.phones.live(s.run, a), "the numbered ones live")
