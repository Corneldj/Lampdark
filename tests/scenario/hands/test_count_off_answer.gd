extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §13.9, §6.7): 'Count off!' is answered 'Here!' at talk band, as a callout in the
## Hand's own character voice (a voice no player holds), which the crew hears like anyone's; the
## Hand carries on as it was. A Hand that does not keep the call says nothing.

const HW = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_hand_answers_here_at_talk() -> void:
	var s: Scenario = make({"seed": 4821, "fixture": HW.road(60)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a, 0.0)
	var bob: MinerHandle = HW.human(s, "bob", a + Vector2i(1, 2), 0.0)
	var hand: int = HW.hand(s, a + Vector2i(4, 0))
	var far: int = HW.hand(s, a + Vector2i(55, 0), 3)
	s.step(10)
	var state: HandController.State = HW.h_of(s, hand).state
	ann.at(s.run.tick).callout("count_off", CalloutLines.TALK)
	s.step(30)
	var answers: Array[Dictionary] = []
	for e: Dictionary in s.run.callouts.spoken:
		if str(e["line"]) == "here":
			answers.append(e)
	assert_eq(answers.size(), 1, "one 'Here!': the far Hand kept nothing")
	var here: Dictionary = answers[0]
	assert_eq(int(Variants.number(here["slot"])), 4, "from the Hand's place")
	assert_eq(int(Variants.number(here["band"])), CalloutLines.TALK, "at talk band")
	var voice: int = HW.h_of(s, hand).voice
	assert_eq(int(Variants.number(s.run.fall_audio.voice_for(4))), voice, "in its own character voice")
	assert_ne(voice, int(Variants.number(s.run.fall_audio.voice_for(ann.slot))), "not a player's")
	assert_ne(voice, int(Variants.number(s.run.fall_audio.voice_for(bob.slot))))
	var heard: bool = false
	for raw: Variant in bob.capture.messages:
		var m: Dictionary = raw
		if int(Variants.number(m["type"])) == Protocol.Msg.CALLOUT:
			var bytes: PackedByteArray = m["bytes"]
			var payload: PackedByteArray = Protocol.unframe(bytes)["payload"]
			var r: CalloutRecord = CalloutRecord.decode(payload)
			heard = heard or (r != null and r.line == VoiceManifest.wire_line("here"))
	assert_true(heard, "Bob hears the Hand's 'Here!'")
	assert_eq(HW.h_of(s, hand).state, state, "and it carries on as it was")
	assert_eq(HW.h_of(s, far).state, HandController.State.FOLLOW)
