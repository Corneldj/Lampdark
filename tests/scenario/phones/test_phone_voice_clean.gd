extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-12 with SND-07 (Gameplay §6.2, §6.6; GDD §15.5): on a live call the operator, 300 tiles off,
## gets every frame of the caller's voice in telephone band at the same gain however far (no
## distance loss), and so does the caller of the operator's; the caller's voice is still noise at
## the wall (a Road Graph event where they stand), and nobody beside the operator hears it.

const P = preload("res://tests/unit/phones/phone_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _heard(h: MinerHandle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Array in h.connection.voice_in:
		var packet: PackedByteArray = raw[0]
		out.append(VoicePackets.read_down(packet))
	h.connection.voice_in.clear()
	return out


func test_clean_both_ways_at_three_hundred_tiles() -> void:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(310), "#a" + ".".repeat(307) + "#", "#".repeat(310)])
	var s: Scenario = make({"seed": 4601, "fixture": FixtureMap.from_ascii(rows)})
	P.power(s)
	var p: PitPhone = P.phone(s, "p1", Vector2i(3, 1))
	var ann: MinerHandle = P.miner(s, "ann", Vector2i(2, 1))
	var bob: MinerHandle = P.miner(s, "bob", Vector2i(302, 1))
	var cat: MinerHandle = P.miner(s, "cat", Vector2i(298, 1))
	s.step(3)
	P.press(s, ann, 50)
	assert_true(s.run.phones.answer(s.run, p.number, bob.slot), "the operator answers")
	for h: MinerHandle in [ann, bob, cat]:
		h.connection.voice_in.clear()
	var events_before: int = s.run.noise.event_log.size()
	ann.at(s.run.tick).say(1, 6)
	s.step(10)
	var down: Array[Dictionary] = _heard(bob)
	assert_eq(down.size(), 6, "every frame, 300 tiles off")
	var gains: Array = down.map(func(d: Dictionary) -> int: return int(Variants.number(d["gain_db"])))
	assert_eq(gains, [0, 0, 0, 0, 0, 0], "at 0 dB on every frame: no distance loss")
	for d: Dictionary in down:
		assert_true(Variants.flag(d["telephone"]), "in telephone band")
	assert_eq(_heard(cat).size(), 0, "nobody beside the operator hears the caller")
	var at_wall: Array = s.run.noise.event_log.slice(events_before).filter(func(e: NoiseSystem.Event) -> bool:
		return e.type == NoiseTypes.Type.VOICE and e.origins.has(Vector2i(2, 1)))
	assert_gt(at_wall.size(), 0, "her voice is still noise at the wall")
	# And back: the operator to the caller.
	bob.at(s.run.tick).say(1, 4)
	s.step(8)
	var up: Array[Dictionary] = _heard(ann)
	assert_eq(up.size(), 4, "the operator's every frame reaches her")
	assert_true(up.size() > 0 and Variants.flag(up[0]["telephone"]))
	# Near the operator at the same 300 tiles but with no line, a teammate gets nothing from her.
	s.run.phones.hang_up(s.run, p.number)
	bob.connection.voice_in.clear()
	ann.at(s.run.tick).say(1, 4)
	s.step(8)
	assert_eq(_heard(bob).size(), 0, "hung up: nothing")
