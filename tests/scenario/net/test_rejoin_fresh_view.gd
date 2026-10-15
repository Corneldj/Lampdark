extends "res://tests/scenario/kit/scenario_test.gd"
## NET-11, under NET-08's audit: a rejoining client starts from nothing. Its first frame is a full
## resync, holding only what its miner sees now (its seen tiles and margin), and nothing it held
## before the drop.

const R = preload("res://tests/unit/mnr/revolver_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_rejoin_gets_only_what_it_sees_now() -> void:
	var s: Scenario = make({"seed": 1331, "fixture": R.hall(40)})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	R.lit(s, 40)
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	R.miner(s, "bob", Vector2i(8, 2), 180.0)
	s.step(10)
	ann.at(s.run.tick).disconnect_at()
	s.step(30)
	# Moved on while she was away: what she saw before is not what she sees now.
	s.run.movement.place(s.run, ann.entity_id, Vector2(30.5, 2.5))
	s.run.movement.miner(ann.slot).state.facing = Intents.facing_u16(0.0)
	s.step(3)
	var from: int = ann.capture.messages.size()
	ann.at(s.run.tick).reconnect_at()
	s.step(20)
	assert_true(ann.is_connected_now())
	var first: PackedByteArray = PackedByteArray()
	for m: Dictionary in ann.capture.messages.slice(from):
		if int(Variants.number(m["type"])) == Protocol.Msg.FRAME:
			var raw: PackedByteArray = m["bytes"]
			first = Protocol.unframe(raw)["payload"]
			break
	assert_false(first.is_empty(), "frames again")
	var d: FrameDecoder.Decoded = FrameDecoder.new().decode(first)
	assert_true(d.ok, "it decodes with nothing held: a full resync")
	assert_true(d.full)
	for t: Vector2i in d.view.tiles.keys():
		assert_gt(t.x, 20, "only around where she stands now (%s)" % t)
	assert_true(d.view.entities.is_empty(), "Bob, back at 8, is out of her sight: no token from before")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p(str(v))
	assert_eq(audit.violation_count, 0, "nothing beyond her seen set and margin")
