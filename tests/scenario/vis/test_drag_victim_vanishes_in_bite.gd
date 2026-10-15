extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-10: a drag victim on a bitten tile vanishes from a teammate's view while its own client still
## draws it (its own block); NET-08's audit stays clean.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const W = preload("res://tests/scenario/vis/bite_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_victim_goes_with_the_bite() -> void:
	var s: Scenario = make({"seed": 1002, "fixture": W.road()})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var w: W = W.new()
	w.build(s)
	var t: Vector2i = w.fringe_tile()
	w.put_stythe(t)
	var bob: MinerHandle = s.add_miner("bob", t + Vector2i(0, 1))
	bob.brain = null
	s.step(3)
	assert_eq(w.token_count(), 2, "both in the fringe before the tell")
	w.active = true
	s.step(3)
	assert_true(s.run.vision.bite_now.has(t + Vector2i(0, 1)) or s.run.light.light_at(t + Vector2i(0, 1)) >= 0.30)
	assert_eq(w.token_count(), 0, "Bob is gone from Ann's view with the Stythe")
	var own: ReceivedView = s.client(bob).records_at(s.run.tick - 1)
	assert_not_null(own)
	assert_false(own.own.is_empty(), "his own client still draws him")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0)
