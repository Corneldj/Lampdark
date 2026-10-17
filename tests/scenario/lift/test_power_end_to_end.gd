extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-05, §3.9's beat at 34:50: at the substation (here a room four cells east of base camp), Wilf
## clears the burnt links with the cutters and fits three fuses, then holds the trip and calls 'Now!'
## by the callout wheel; Ellis throws the switch on it. On the success tick power is on, Power is
## done and base camp wakes: the relighter and the battery rack work, and with the other jobs done
## Start becomes possible (the winder's brake). NET-08's audit passes throughout, and Cat, in base
## camp, is never sent the substation's fixtures.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const P = preload("res://tests/unit/lift/power_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_power_beat() -> void:
	var s: Scenario = make({"seed": 5511, "fixture": C.scenario_fixture()})
	C.load_camp(s)
	s.run.repair.set_list(RepairList.for_run(s.run.header.run_seed, RepairList.Kind.SHORT, false))
	var o: Vector2i = P.room_at(s, Vector2i(4, 0))
	P.substation(s, false, 0.6, o)
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var wilf: MinerHandle = P.beside(s, "wilf", o + P.BOARD)
	var ellis: MinerHandle = P.beside(s, "ellis", o + P.SWITCH, Vector2i(-1, 0))
	var cat: MinerHandle = s.add_miner("cat", Vector2i(9, 10))
	cat.brain = null
	s.step(3)
	var power: PowerJob = s.run.power
	var fired: Array[int] = []
	var woke: Array[bool] = []
	power.power_on.connect(func(tick: int) -> void:
		fired.append(tick)
		woke.append(power.board_wakes() and s.run.repair.is_done(&"power") and s.run.base_camp.powered))
	assert_false(s.run.base_camp.powered, "base camp's relighter and rack wait for power")
	# The links and three fuses.
	P.ready_switch(s, wilf, 3)
	assert_true(power.links_cleared)
	assert_eq(power.fuses_fitted, 3)
	# The trip, 'Now!' and the throw.
	s.run.movement.place(s.run, wilf.entity_id, Vector2(o + P.TRIP + Vector2i(-1, 0)) + Vector2(0.5, 0.5))
	wilf.at(s.run.tick).face(0.0)
	s.step(2)
	ellis.connection.callouts.clear()
	wilf.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 120)
	wilf.at(s.run.tick + 2).callout("now", CalloutLines.TALK)
	assert_true(P.throw_after_cue(s, ellis, 0.4, 0))
	for i: int in 30:
		if power.is_on():
			break
		s.step(1)
	assert_true(power.is_on(), "thrown on 'Now!': power on")
	assert_eq(fired.size(), 1)
	if fired.size() == 1:
		assert_eq(power.on_tick, fired[0])
		assert_true(woke[0], "on the success tick the board wakes, Power is done and base camp is powered")
	assert_true(power.board_wakes() and power.lines_live(), "the board wakes and the lines are live")
	var heard_now: bool = false
	for r: CalloutRecord in ellis.connection.callouts:
		heard_now = heard_now or r.line == VoiceManifest.wire_line("now")
	assert_true(heard_now, "Ellis heard Wilf's 'Now!'")
	# Base camp wakes: the relighter and the rack.
	assert_true(s.run.base_camp.powered)
	var lamp: GauzeLamp = s.run.lamps.create(s.run, 0.5, 2, false, 1, Vector2(9.5, 10.5))
	assert_not_null(lamp)
	assert_true(s.run.base_camp.relighter.begin(s.run, s.run.base_camp.powered, lamp), "the relighter works")
	assert_true(s.run.base_camp.rack.put(s.run.base_camp.powered, 0, 0.0), "the battery rack takes a lamp")
	# Start: once Fuel is done too, the brake releases (LFT-03's can_start).
	assert_true(s.run.repair.is_done(&"power"))
	assert_false(s.run.repair.can_start(), "Fuel still to do")
	s.run.repair.mark_done(s.run, &"fuel")
	assert_true(s.run.repair.can_start(), "with Power done, Start can count")
	s.step(20)
	# NET-08: nothing unseen sent; Cat in base camp never learns of the substation's fixtures.
	for v: Dictionary in audit.violations.slice(0, 6):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "NET-08: the substation as seen, never more")
	assert_eq(power.fixtures.size(), 3)
	var sent_near: int = 0
	for t: int in range(0, s.run.tick + 1):
		var seen: Dictionary = cat.client().entities_visible(t)
		for raw: Variant in seen.values():
			var e: Dictionary = raw
			var at: Vector2 = e.get("position", Vector2.ZERO)
			if at.x >= float(o.x):
				sent_near += 1
	assert_eq(sent_near, 0, "Cat, in base camp, is sent nothing of the substation")
