extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-06 (Gameplay §11.9, §6.8, GDD §14.3, §15.7): Lamp Check after §3.9's ride. It opens on the
## surface's tick: the mine freezes, the phase is LAMP_CHECK, and every client is sent the hooks by
## lamp number (Ada's empty), the remark (the Stythe's drag), the card as the design prints it and
## its own miner's outcome. Everyone, Ada below included, talks on one shared channel. Among friends
## it ends once every player still here is ready; in public, 120 s after it opens. Then the phase is
## ENDED, the run record is gone and every client is told. NET-08's audit passes all of it.

const W = preload("res://tests/scenario/rescue/lamp_check_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const CARD: String = "Morrow Main, first shift. Up 4 of 5. Left Below: Ada Rowe, Lamp 114. Deepest: the Third Level. Below 1 h 42 min."


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	WorldCoords.ring_override = -1


func _everyone(r: Array) -> Array[MinerHandle]:
	var out: Array[MinerHandle] = []
	out.assign(Variants.array(r[0]))
	out.append(r[1])
	return out


func test_lamp_check_after_the_first_shift() -> void:
	var s: Scenario = make({"seed": 12001, "fixture": W.K.E.T.C.scenario_fixture()})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var r: Array = W.first_shift(s)
	var ada: MinerHandle = r[1]
	var everyone: Array[MinerHandle] = _everyone(r)
	var lc: LampCheck = s.run.lamp_check
	assert_eq(lc.state, LampCheck.State.OPEN, "open on the surface's tick")
	assert_eq(s.run.phase, RunState.Phase.LAMP_CHECK)
	assert_true(s.run.frozen, "the mine stands still")
	var frozen_at: int = s.run.tick
	s.step(10)
	assert_eq(s.run.tick, frozen_at, "no tick of the mine runs")
	for h: MinerHandle in everyone:
		var opens: Array[Dictionary] = W.of_kind(h, LampCheckWire.OPEN)
		assert_eq(opens.size(), 1, "%s is told once" % h.name)
		if opens.is_empty():
			continue
		var o: Dictionary = opens[0]
		assert_eq(str(o["card"]), CARD)
		assert_eq(str(o["remark"]), "drag", "the remark: the Stythe's drag")
		var hooks: Array = []
		for raw: Variant in Variants.array(o["hooks"]):
			hooks.append([int(Variants.number(Variants.dict(raw)["lamp"])), Variants.flag(Variants.dict(raw)["hangs"])])
		assert_eq(hooks, [[108, true], [114, false], [131, true], [162, true], [207, true]], "by lamp number; hook 114 empty")
		assert_eq(str(o["own"]), "left_below" if h == ada else "escaped", "%s's own outcome, nobody else's" % h.name)
		assert_false(Variants.flag(o["wipe"]))
		assert_eq(Variants.number(o["public_s"]), 0.0, "among friends: when everyone is ready")
		assert_eq(str(o["run_uuid"]), s.run.header.run_uuid)
	var members: Dictionary = Variants.dict(s.run.voice.channels.get(LampCheck.CHANNEL, {}))
	for h: MinerHandle in everyone:
		assert_true(members.has(h.slot), "%s is on the pithead's channel" % h.name)
	for name: Variant in s.run.voice.channels.keys():
		if str(name) != LampCheck.CHANNEL:
			assert_true(Variants.dict(s.run.voice.channels[name]).is_empty(), "nobody is left on %s" % name)
	for h: MinerHandle in everyone:
		if h != ada:
			W.press_ready(h)
	s.step(3)
	assert_eq(lc.state, LampCheck.State.OPEN, "Ada has not pressed Ready")
	W.press_ready(ada)
	s.step(3)
	assert_eq(lc.state, LampCheck.State.ENDED, "all ready: it ends")
	assert_eq(lc.end_why, "ready")
	assert_eq(s.run.phase, RunState.Phase.ENDED)
	assert_true(s.run.record.discarded, "NET-07's record is gone")
	for h: MinerHandle in everyone:
		var ends: Array[Dictionary] = W.of_kind(h, LampCheckWire.END)
		assert_eq(ends.size(), 1, "%s is told it is over" % h.name)
	var report: Dictionary = audit.report()
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "NET-08's audit passes")
	assert_gt(int(Variants.number(Variants.dict(report["checked"]).get("lamp_check", 0))), 0, "it judged Lamp Check's messages")


func test_public_lamp_check_ends_by_120_s() -> void:
	var s: Scenario = make({"seed": 12002, "fixture": W.K.E.T.C.scenario_fixture(), "mode": ServerConfig.Mode.PUBLIC})
	var r: Array = W.first_shift(s)
	var everyone: Array[MinerHandle] = _everyone(r)
	var lc: LampCheck = s.run.lamp_check
	assert_eq(lc.state, LampCheck.State.OPEN)
	var budget: int = roundi(Tuning.f(&"rescue.lamp_check_public_s") * Tuning.f(&"net.tick_hz"))
	for h: MinerHandle in everyone:
		W.press_ready(h)
	s.step(budget - 2)
	assert_eq(lc.state, LampCheck.State.OPEN, "Ready ends nothing in public: the budget does")
	s.step(3)
	assert_eq(lc.state, LampCheck.State.ENDED, "by 120 s")
	assert_eq(lc.end_why, "time")
	assert_lte(lc.ended_at - lc.opened_at, budget)
	for h: MinerHandle in everyone:
		var opens: Array[Dictionary] = W.of_kind(h, LampCheckWire.OPEN)
		assert_eq(Variants.number(opens[0]["public_s"]) if not opens.is_empty() else -1.0, Tuning.f(&"rescue.lamp_check_public_s"),
			"%s is shown the pithead's budget" % h.name)
		assert_eq(W.of_kind(h, LampCheckWire.END).size(), 1)
