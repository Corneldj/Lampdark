extends GutTest
## MOD-01: lamp numbers are three digits, distinct within a roster; seatable() leaves out a joiner's
## miners whose numbers are seated (and any Below), and refuses a joiner whose three all clash.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_three_digits_distinct_and_seatable() -> void:
	for seed_value: int in 200:
		var p: Profile = Profile.create(1000 + seed_value, seed_value)
		var roster: Array[RosterMiner] = p.state().roster
		assert_eq(roster.size(), 3)
		var numbers: Dictionary = {}
		var names: Dictionary = {}
		for m: RosterMiner in roster:
			assert_between(m.lamp_number, 100, 999)
			numbers[m.lamp_number] = true
			names[m.full_name()] = true
			assert_true(m.available())
		assert_eq(numbers.size(), 3, "distinct numbers")
		assert_eq(names.size(), 3, "distinct names")
	var p: Profile = Profile.create(7, 7)
	var roster: Array[RosterMiner] = p.state().roster
	var seated: Array[int] = [roster[0].lamp_number]
	assert_eq(LampNumbers.seatable(seated, roster), [roster[1], roster[2]] as Array[RosterMiner], "the clashing one stays home")
	seated = [roster[0].lamp_number, roster[1].lamp_number, roster[2].lamp_number]
	assert_eq(LampNumbers.seatable(seated, roster), [] as Array[RosterMiner], "all three clash: refused")
	roster[2].below_run = "run-x"
	assert_eq(LampNumbers.seatable([] as Array[int], roster), [roster[0], roster[1]] as Array[RosterMiner], "a Below miner cannot go")
