extends GutTest
## MOD-01: a five-miner run ends Up 4 of 5 with one Left Below. Each player's profile takes RSC-06's
## miner_outcome for their own miner (fed here as Lamp Check will send it): four rosters keep their
## miner as they were, the fifth loses theirs for good and is offered three fresh names; all five
## count the run once toward New Brigade; the four escapes unlock the hard variants.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_up_four_of_five() -> void:
	var players: Array[Profile] = []
	var sent: Array[RosterMiner] = []
	var seated: Array[int] = []
	for i: int in 5:
		var p: Profile = Profile.create(76561198000000000 + i, 1000 + i)
		var choice: Array[RosterMiner] = LampNumbers.seatable(seated, p.state().roster)
		assert_false(choice.is_empty(), "player %d can seat a miner" % i)
		var m: RosterMiner = choice[0]
		seated.append(m.lamp_number)
		assert_true(p.send_below("run-5", m.id, 100))
		players.append(p)
		sent.append(m)
	assert_eq(seated.size(), 5)
	var unique: Dictionary = {}
	for n: int in seated:
		unique[n] = true
	assert_eq(unique.size(), 5, "no lobby seats two miners with one number")
	for i: int in 5:
		var what: OutcomeEvent.Outcome = OutcomeEvent.Outcome.LEFT_BELOW if i == 3 else OutcomeEvent.Outcome.ESCAPED
		players[i].apply_outcome("run-5", sent[i].id, what, 200)
	for i: int in 5:
		var s: Profile.State = players[i].state()
		assert_eq(s.new_brigade_runs, 1, "player %d: the run counts once" % i)
		if i == 3:
			assert_null(s.miner(sent[i].id), "Left Below: gone for good")
			assert_eq(s.roster.size(), 2)
			assert_eq(Variants.array(s.offers[sent[i].id]).size(), 3, "three fresh names offered")
			assert_false(s.unlocked_variants)
		else:
			var m: RosterMiner = s.miner(sent[i].id)
			assert_true(m != null and m.available(), "player %d's miner is back" % i)
			assert_eq([m.full_name(), m.lamp_number], [sent[i].full_name(), sent[i].lamp_number])
			assert_eq(s.roster.size(), 3)
			assert_true(s.offers.is_empty())
			assert_true(s.unlocked_variants, "an escape unlocks the hard variants")
