extends GutTest
## MOD-01 (Gameplay §3.8, §13.2): each outcome changes the roster as the design says. Escaped keeps
## name, number and book; dead, Left Below and a wipe leave for good, and three fresh names are
## offered; a voided public run and an abnormal friends end change nothing; a Below miner cannot be
## sent again; the first escape unlocks the hard variants and nothing else does.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_each_outcome() -> void:
	var p: Profile = Profile.create(1, 11)
	var first: Array[RosterMiner] = p.state().roster
	var a: RosterMiner = first[0]
	a.book_pages.append("moth")
	p.founding[0].book_pages.append("moth")
	assert_true(p.send_below("r1", a.id, 10))
	assert_false(p.send_below("r2", a.id, 11), "Below: cannot be sent again")
	assert_false(p.state().roster[0].available())
	p.apply_outcome("r1", a.id, OutcomeEvent.Outcome.ESCAPED, 20)
	var s: Profile.State = p.state()
	var back: RosterMiner = s.miner(a.id)
	assert_true(back.available(), "escaped: back on the roster")
	assert_eq([back.full_name(), back.lamp_number, back.book_pages], [a.full_name(), a.lamp_number, ["moth"]], "name, number and book kept")
	assert_true(s.unlocked_variants, "the first escape unlocks One Lamp, No Chalk and Dead Lines")
	for what: OutcomeEvent.Outcome in [OutcomeEvent.Outcome.DEAD, OutcomeEvent.Outcome.LEFT_BELOW, OutcomeEvent.Outcome.WIPE]:
		var q: Profile = Profile.create(2, 22 + what)
		var m: RosterMiner = q.state().roster[1]
		q.send_below("run", m.id, 5)
		q.apply_outcome("run", m.id, what, 9)
		var t: Profile.State = q.state()
		assert_null(t.miner(m.id), "%s: gone for good" % OutcomeEvent.OUTCOME_NAMES[what])
		assert_eq(t.roster.size(), 2)
		assert_false(t.unlocked_variants, "no unlock from %s" % OutcomeEvent.OUTCOME_NAMES[what])
		var offered: Array = Variants.array(t.offers[m.id])
		assert_eq(offered.size(), 3, "three fresh names")
		for n: Variant in offered:
			for kept: RosterMiner in t.roster:
				assert_ne(NameDrawer.full(Variants.dict(n)), kept.full_name())
		assert_true(q.hire(m.id, 1, 12))
		var u: Profile.State = q.state()
		assert_eq(u.roster.size(), 3, "the hire fills the place")
		var hired: RosterMiner = u.roster[2]
		assert_eq(hired.full_name(), NameDrawer.full(Variants.dict(offered[1])))
		assert_eq(hired.book_pages, [] as Array[String], "the new hire's book starts blank")
		assert_false([u.roster[0].lamp_number, u.roster[1].lamp_number].has(hired.lamp_number), "a new number for life")
		assert_false(q.hire(m.id, 0, 13), "one hire per place")


func test_a_wipe_and_runs_that_end_without_lamp_check() -> void:
	var p: Profile = Profile.create(3, 33)
	var ids: Array[int] = []
	for m: RosterMiner in p.state().roster:
		ids.append(m.id)
	# A public run voided by an abnormal end: nothing changes, the miner comes back.
	p.send_below("pub", ids[0], 1)
	p.end_without_lamp_check("pub", OutcomeEvent.End.VOIDED, 2)
	assert_true(p.state().miner(ids[0]).available())
	# A friends run that ends abnormally: still Below, nothing else.
	p.send_below("friends", ids[1], 3)
	p.end_without_lamp_check("friends", OutcomeEvent.End.ABNORMAL, 4)
	var s: Profile.State = p.state()
	assert_eq(s.roster.size(), 3)
	assert_eq(s.miner(ids[1]).below_run, "friends", "waits for the resume")
	assert_eq(s.new_brigade_runs, 0, "neither counts")
	# A wipe: the player's miner of that run leaves, as every other player's does.
	p.apply_outcome("friends", ids[1], OutcomeEvent.Outcome.WIPE, 9)
	assert_null(p.state().miner(ids[1]))
	assert_eq(p.state().new_brigade_runs, 1, "it ended at Lamp Check")
