extends "res://tests/scenario/kit/scenario_test.gd"
## SND-12, under NET-08's audit: Ann signals STOP; Bob, facing her, gets the kind on her identity
## record while it lasts; Cid, beside Bob but facing away, never does. No signal is heard.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const W = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _kinds_seen(s: Scenario, h: MinerHandle, from_tick: int) -> Dictionary:
	var out: Dictionary = {}
	for t: int in range(from_tick, s.run.tick):
		var view: ReceivedView = s.client(h).records_at(t)
		if view == null:
			continue
		for raw: Variant in view.entities.keys():
			var e: Dictionary = view.entities[raw]
			var k: int = LampSignalKind.of_flame(int(Variants.number(e.get("flame", 0))))
			if k != 0:
				out[k] = true
	return out


func test_only_a_watcher_facing_her_sees_it() -> void:
	var s: Scenario = make({"seed": 1161, "fixture": W.road(40)})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = W.miner(s, "ann", a, 0.0)
	var bob: MinerHandle = W.miner(s, "bob", a + Vector2i(8, -1), 180.0)
	var cid: MinerHandle = W.miner(s, "cid", a + Vector2i(8, 1), 0.0)
	s.step(3)
	var from: int = s.run.tick
	var heard_before: int = s.run.heard.heard_log.size()
	W.signal_press(s, ann, LampSignalKind.Kind.STOP)
	s.step(30)
	assert_true(_kinds_seen(s, bob, from).has(LampSignalKind.Kind.STOP), "Bob saw STOP")
	assert_true(_kinds_seen(s, cid, from).is_empty(), "Cid, facing away, saw nothing")
	s.step(10)
	assert_true(_kinds_seen(s, bob, s.run.tick - 5).is_empty(), "and it ends")
	for row: Dictionary in s.run.heard.heard_log.slice(heard_before):
		assert_ne(int(Variants.number(row["slot"])), ann.slot, "a signal is never heard")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0)
