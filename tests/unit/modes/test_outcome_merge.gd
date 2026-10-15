extends GutTest
## MOD-01 (Proposed, event-sourced): events are idempotent, and two copies merge by union. A copy
## holding "Left Below" for a miner wins, whatever the order (STM-05's rule: deaths in any fork
## stand).


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_idempotent() -> void:
	var p: Profile = Profile.create(4, 44)
	var m: int = p.state().roster[0].id
	p.apply_outcome("r", m, OutcomeEvent.Outcome.ESCAPED, 5)
	var once: Dictionary = p.to_dict()
	p.apply_outcome("r", m, OutcomeEvent.Outcome.ESCAPED, 5)
	p.merge(Profile.from_dict(once))
	assert_eq(p.to_dict(), once, "applying again, or merging the same copy, changes nothing")


func test_left_below_wins_in_either_order() -> void:
	var base: Profile = Profile.create(5, 55)
	var m: int = base.state().roster[2].id
	var results: Array[bool] = []
	for order: int in 2:
		var a: Profile = Profile.from_dict(base.to_dict())
		var b: Profile = Profile.from_dict(base.to_dict())
		a.apply_outcome("fork", m, OutcomeEvent.Outcome.ESCAPED, 30)
		b.apply_outcome("fork", m, OutcomeEvent.Outcome.LEFT_BELOW, 31)
		var merged: Profile = a if order == 0 else b
		merged.merge(b if order == 0 else a)
		results.append(merged.state().miner(m) == null)
	assert_eq(results, [true, true], "Left Below stands, in either order")


func test_two_copies_hiring_for_one_place_agree() -> void:
	var base: Profile = Profile.create(6, 66)
	var m: int = base.state().roster[0].id
	base.apply_outcome("r", m, OutcomeEvent.Outcome.DEAD, 1)
	var a: Profile = Profile.from_dict(base.to_dict())
	var b: Profile = Profile.from_dict(base.to_dict())
	a.hire(m, 0, 10)
	b.hire(m, 2, 11)
	a.merge(b)
	b.merge(a)
	assert_eq(a.state().roster.size(), 3)
	assert_eq(a.state().roster[2].full_name(), b.state().roster[2].full_name(), "both copies keep the same hire")
