extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-04: a fallen player watching a teammate receives that teammate's frames exactly as sent to them,
## 900 ticks (45 s) later, with nothing else: no voice and no sheet data.

const D = preload("res://tests/scenario/rescue/dark_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_frames_as_sent_45_s_later() -> void:
	var s: Scenario = make({"seed": 521, "fixture": "test"})
	var miners: Array[MinerHandle] = D.W.crew(s, 2, 521)
	var ann: MinerHandle = miners[0]
	var bob: MinerHandle = miners[1]
	ann.brain = null  # scripted: a bot brain's input would replace the press
	var bobs: Dictionary = {}
	s.client(bob).on_decoded = func(_d: FrameDecoder.Decoded) -> void: pass
	bob.at(30).say(2, 40)
	s.step(5)
	D.fall(s, ann)
	ann.at(s.run.tick + 1).press(ActionRecord.Kind.WATCH, 1)
	s.step(1100)
	# What Bob was sent, by frame tick.
	for m: Dictionary in bob.capture.messages:
		if int(Variants.number(m["type"])) == Protocol.Msg.FRAME:
			var bytes: PackedByteArray = m["bytes"]
			var payload: PackedByteArray = Protocol.unframe(bytes)["payload"]
			bobs[int(Variants.number(FrameDecoder.header(payload)["tick"]))] = payload
	var relayed: int = 0
	var problems: Array[String] = []
	var types: Dictionary = {}
	for m: Dictionary in ann.capture.messages:
		var t: int = int(Variants.number(m["type"]))
		if t != Protocol.Msg.WATCH:
			types[t] = true
			continue
		var bytes: PackedByteArray = m["bytes"]
		var body: PackedByteArray = Protocol.unframe(bytes)["payload"]
		var d: Dictionary = DarkMessages.decode(body)
		var arrived: int = int(Variants.number(m["tick"]))
		for raw: Variant in Variants.array(d["frames"]):
			var f: Array = raw
			var tick: int = f[0]
			var payload: PackedByteArray = f[1]
			relayed += 1
			if not bobs.has(tick) or bobs[tick] != payload:
				problems.append("frame %d is not Bob's" % tick)
			if arrived - tick < 900:
				problems.append("frame %d arrived %d ticks after it was sent" % [tick, arrived - tick])
	gut.p("relayed %d of Bob's frames" % relayed)
	assert_gt(relayed, 100)
	assert_eq(problems, [] as Array[String], "Bob's own frames, at least 45 s late")
	assert_false(types.has(Protocol.Msg.VOICE), "Ann (fallen, not in the dream) gets no voice")
