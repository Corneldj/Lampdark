extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-06 (Gameplay §6.8, §11.9): at Lamp Check everyone talks on one shared channel: Harry, Ellis and
## Nell who came up, Wilf shot during the bell and brought home dead, and Ada left below out cold.
## Each speaker reaches every other member, dry, with no range and no loss, and nothing they say
## makes a noise. The dead body aboard counts in Up and adds its line to the card.

const W = preload("res://tests/scenario/rescue/lamp_check_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	WorldCoords.ring_override = -1


func test_one_channel_for_everyone() -> void:
	var s: Scenario = make({"seed": 12301, "fixture": W.K.E.T.C.scenario_fixture()})
	var r: Array = W.first_shift(s, func(sc: Scenario, crew: Array[MinerHandle]) -> void:
		sc.run.miner_state.kill(crew[2].entity_id, "shot"))
	var everyone: Array[MinerHandle] = []
	everyone.assign(Variants.array(r[0]))
	var ada: MinerHandle = r[1]
	everyone.append(ada)
	var wilf: MinerHandle = everyone[2]
	assert_eq(s.run.lamp_check.state, LampCheck.State.OPEN)
	assert_eq(s.run.miner_state.life(wilf.entity_id), MinerTransitions.Life.DEAD, "Wilf rode up dead")
	assert_eq(s.run.miner_state.life(ada.entity_id), MinerTransitions.Life.UNCONSCIOUS, "Ada lies out cold below")
	var card: String = str(s.run.lamp_check.facts["card"])
	assert_string_contains(card, "Up 4 of 5.", "a body brought home counts in Up")
	assert_string_contains(card, "\nDead: Wilfred Dodd, Lamp 207, brought home.")
	s.step(2)
	var opens: Array[Dictionary] = W.of_kind(wilf, LampCheckWire.OPEN)
	assert_eq(str(opens[0]["own"]) if not opens.is_empty() else "", "dead", "his own outcome: dead, brought home")
	var slots: Array[int] = []
	for h: MinerHandle in everyone:
		slots.append(h.slot)
	for h: MinerHandle in everyone:
		var routes: Array = s.run.voice.compute(h.slot, 2, {})
		var heard: Array[int] = []
		for raw: Variant in routes:
			var route: Dictionary = raw
			heard.append(int(Variants.number(route["listener"])))
			assert_eq(int(Variants.number(route["flags"])), VoicePackets.DRY, "dry")
			assert_eq(Variants.number(route["loss"]), 0.0, "no loss")
			assert_eq(Variants.number(route["gain_db"]), 0.0, "no range")
		heard.sort()
		var others: Array[int] = slots.duplicate()
		others.erase(h.slot)
		others.sort()
		assert_eq(heard, others, "%s reaches every other member, and only them" % h.name)
	var made: int = s.run.voice_noise.emitted
	for h: MinerHandle in everyone:
		for band: int in [1, 2, 3]:
			s.run.voice.band_heard.emit(h.slot, band)
	s.step(5)
	assert_eq(s.run.voice_noise.emitted, made, "nothing said at the pithead makes a noise")
