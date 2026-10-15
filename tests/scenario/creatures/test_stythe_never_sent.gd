extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13, under NET-08's audit: in the fringe the Stythe reaches a miner only as a miner-sized token;
## lit to 0.30, as the faceless figure with no face, badge or cue fields; never anything of its
## senses, memory, eligibility, target or timers.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const W = preload("res://tests/unit/creatures/stythe_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_token_then_faceless_and_nothing_else() -> void:
	var s: Scenario = make({"seed": 1301, "fixture": W.road(60), "overrides": W.ON})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var st: StytheCreature = W.stythe(s, Vector2i(35, 2))
	s.step(1)
	var ann: MinerHandle = W.miner(s, "ann", Vector2i(30, 2), 0.0)
	s.step(1)
	L.lit_in_hand(s, ann)
	s.step(3)
	var types_before: Dictionary = {}
	for m: Dictionary in ann.capture.messages:
		types_before[int(Variants.number(m["type"]))] = true
	# The fringe: lit 0.12-0.30 where it stands (and 0.2 is no wall to it).
	W.light(s, st.tile(s.run), 0.2)
	s.step(2)
	var view: ReceivedView = s.client(ann).records_at(s.run.tick - 1)
	var tokens: int = 0
	for raw: Variant in view.entities.keys():
		var e: Dictionary = view.entities[raw]
		if int(Variants.number(e.get("level", 0))) == 1:
			tokens += 1
	gut.p("Stythe at %s, light %.2f; tokens %d" % [st.tile(s.run), s.run.light.light_at(st.tile(s.run)), tokens])
	# Lit to 0.30 on the tick it is lit: the faceless figure, nothing else on its record.
	assert_eq(tokens, 1, "in the fringe: one miner-sized token")
	W.light(s, st.tile(s.run), 0.6)
	s.step(2)
	var figures: int = 0
	for t: int in range(s.run.tick - 4, s.run.tick):
		var v: ReceivedView = s.client(ann).records_at(t)
		if v == null:
			continue
		for raw: Variant in v.entities.keys():
			var e: Dictionary = v.entities[raw]
			if int(Variants.number(e.get("level", 0))) == 2 and int(Variants.number(e.get("size_or_kind", -1))) == SeenKind.Kind.STYTHE:
				figures += 1
				assert_eq(int(Variants.number(e.get("cues", 0))), 0, "no cues or cap badge on the faceless figure")
				assert_eq(int(Variants.number(e.get("in_hand", 0))), 0, "nothing in its hands")
	assert_gt(figures, 0, "lit to 0.30: the faceless figure")
	for m: Dictionary in ann.capture.messages:
		assert_true(types_before.has(int(Variants.number(m["type"]))), "no new kind of message carries its senses")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0)
