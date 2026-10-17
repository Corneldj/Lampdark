extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §13.9, §6.8): Hands are taken like miners. A smothered or dragged Hand falls
## without a scream, but the knocks sound for every conscious miner; taken, it does nothing; a kit on
## a medbay table revives it, and it rises and follows again.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const M = preload("res://tests/unit/rescue/medbay_world.gd")
const HW = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_fallen_hand_knocks_without_a_scream_and_is_revived() -> void:
	var s: Scenario = make({"seed": 4881, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var table: Vector2i = camp.medbay_tables()[0]
	var spot: Vector2i = M.beside(s, table)
	var ann: MinerHandle = s.add_miner("ann", spot)
	var bob: MinerHandle = s.add_miner("bob", spot)
	ann.brain = null
	bob.brain = null
	var hand: int = HW.hand(s, spot, 4)
	s.step(5)
	var knocks_before: int = s.run.fall_audio.knocks_sent
	var screams: Array[int] = []
	for ev: NoiseSystem.Event in s.run.noise.event_log:
		if ev.type == NoiseTypes.Type.FALL_SCREAM:
			screams.append(ev.id)
	assert_true(s.run.falls.fall_unconscious(s.run, hand, FallCause.Cause.MOTH_SMOTHER))
	s.step(roundi((Tuning.f(&"voice.knock_delay_s") + 1.0) * Tuning.f(&"net.tick_hz")))
	for ev: NoiseSystem.Event in s.run.noise.event_log:
		assert_false(ev.type == NoiseTypes.Type.FALL_SCREAM and not screams.has(ev.id), "a Hand falls without a scream")
	assert_gt(s.run.fall_audio.knocks_sent, knocks_before, "the knocks sound")
	for h: MinerHandle in [ann, bob]:
		var knocked: bool = false
		for raw: Variant in h.capture.messages:
			var m: Dictionary = raw
			knocked = knocked or int(Variants.number(m["type"])) == Protocol.Msg.KNOCKS
		assert_true(knocked, "%s hears the knocks" % h.name)
	assert_eq(HW.h_of(s, hand).state, HandController.State.TAKEN, "taken, it does nothing")
	# Laid on a medbay table, a kit revives it.
	M.lay(s, hand, table)
	s.step(1)
	M.give_kit(s, ann.entity_id)
	assert_true(s.run.revival.may_revive(s.run, ann.entity_id, hand))
	M.start(s, ann, hand, KitUse.Mode.REVIVE, 110)
	s.step(110)
	assert_eq(M.life(s, hand), MinerTransitions.Life.UPRIGHT, "revived")
	s.step(10)
	assert_ne(HW.h_of(s, hand).state, HandController.State.TAKEN, "and back to work")
