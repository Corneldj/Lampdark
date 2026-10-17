extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-06 (Gameplay §11.9, §13.2, GDD §14.3): Lamp Check after a wipe of four. It waits
## rescue.wipe_lamp_check_wait_s with the mine still running (the last victim's fall view), then opens
## frozen: no check hangs, the card reads 'Up none of 4.', every client's own outcome is the wipe's,
## and on each player's roster the miner they sent below leaves for good.

const W = preload("res://tests/scenario/rescue/lamp_check_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_wipe_of_four() -> void:
	var s: Scenario = make({"seed": 12101, "fixture": W.hall(), "mode": ServerConfig.Mode.FRIENDS})
	var crew: Array[MinerHandle] = W.wiped(s, ["ann", "bob", "cid", "dot"] as Array[String])
	var lc: LampCheck = s.run.lamp_check
	assert_true(s.run.outcomes.ended and s.run.outcomes.wiped, "the wipe")
	assert_eq(lc.state, LampCheck.State.WAITING, "the last fall view first")
	assert_false(s.run.frozen, "the mine runs on while it plays")
	var wait: int = roundi(Tuning.f(&"rescue.wipe_lamp_check_wait_s") * Tuning.f(&"net.tick_hz"))
	var from: int = s.run.tick
	s.step(wait - 1 - lc.clock)
	assert_eq(lc.state, LampCheck.State.WAITING)
	s.step(2)
	assert_eq(lc.state, LampCheck.State.OPEN, "open %.0f s after the wipe" % Tuning.f(&"rescue.wipe_lamp_check_wait_s"))
	assert_gt(s.run.tick, from, "the mine ran during the wait")
	assert_true(s.run.frozen)
	for h: MinerHandle in crew:
		var opens: Array[Dictionary] = W.of_kind(h, LampCheckWire.OPEN)
		assert_eq(opens.size(), 1)
		if opens.is_empty():
			continue
		var o: Dictionary = opens[0]
		assert_true(Variants.flag(o["wipe"]))
		assert_string_contains(str(o["card"]), "Up none of 4.")
		for raw: Variant in Variants.array(o["hooks"]):
			assert_false(Variants.flag(Variants.dict(raw)["hangs"]), "no check hangs")
		assert_eq(Variants.array(o["hooks"]).size(), 4, "a hook for each")
		assert_eq(str(o["own"]), "left_below")
		assert_eq(str(o["remark"]), "roof_fall")
		# MOD-01: the miner this player sent below leaves the roster for good.
		var p: Profile = Profile.create(1000 + crew.find(h), 77 + crew.find(h))
		var sent: RosterMiner = p.state().roster[0]
		assert_true(p.send_below(str(o["run_uuid"]), sent.id, 1))
		assert_true(LampCheckRoster.apply(p, str(o["run_uuid"]), str(o["own"]), Variants.flag(o["wipe"]), 2))
		var after: Profile.State = p.state()
		assert_true(after.miner(sent.id) == null, "%s's miner has left the roster" % h.name)
		assert_eq(after.gone.size(), 1)
		assert_eq(after.gone[0].left, "wipe")
		assert_true(LampCheckRoster.apply(p, str(o["run_uuid"]), str(o["own"]), true, 3) == false, "applied once: nobody else is below")
