extends GutTest
## MOD-01 (Gameplay §10.10): New Brigade for a player's first five runs, counted once per run that
## ends at Lamp Check with one of their miners in it; knock-offs and voided runs never count.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_counted_at_lamp_check_only() -> void:
	var p: Profile = Profile.create(8, 88)
	var m: int = p.state().roster[0].id
	assert_true(p.state().new_brigade())
	for i: int in 4:
		p.send_below("run%d" % i, m, i * 10)
		p.apply_outcome("run%d" % i, m, OutcomeEvent.Outcome.ESCAPED, i * 10 + 5)
		p.apply_outcome("run%d" % i, m, OutcomeEvent.Outcome.ESCAPED, i * 10 + 5)  # the same report twice
	assert_eq(p.state().new_brigade_runs, 4, "once per run")
	p.send_below("knocked", m, 100)
	p.end_without_lamp_check("knocked", OutcomeEvent.End.ABNORMAL, 101)
	p.end_without_lamp_check("void", OutcomeEvent.End.VOIDED, 102)
	assert_eq(p.state().new_brigade_runs, 4, "a knock-off or a voided run never counts")
	assert_true(p.state().new_brigade())
	p.apply_outcome("knocked", m, OutcomeEvent.Outcome.ESCAPED, 200)  # resumed, then ended at Lamp Check
	assert_eq(p.state().new_brigade_runs, 5)
	assert_false(p.state().new_brigade(), "five runs: New Brigade no longer")
