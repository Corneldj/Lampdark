extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-01 for CRT-04's smother (the Moth's side lands with CRT-04; it calls fall_unconscious with
## moth_takes_lamp): with four miners in a hall, the lamp-bearer falls; her gauze lamp leaves with
## the Moth, snuffed; her belt stays; exactly one fell, with a full scream, which SND-15 turns into
## the scream and the three knocks for the other three; she sees nothing, they see on.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_smother() -> void:
	var s: Scenario = make({"seed": 72, "fixture": W.room()})
	W.light(s)
	var a: Vector2i = s.fixture.spot("a")
	var ada: MinerHandle = s.add_miner("ada", a)
	var others: Array[MinerHandle] = [s.add_miner("bob", a + Vector2i(2, 0)), s.add_miner("cy", a + Vector2i(3, 1)),
		s.add_miner("dee", a + Vector2i(4, -1))]
	s.step(1)
	var lamp: GauzeLamp = L.lit_in_hand(s, ada, LampRules.WICK_UP)
	assert_true(s.run.inventory.give(s.run, ada.entity_id, s.run.inventory.world.make(ItemKinds.Kind.HEALING_KIT)))
	var moth: int = s.run.registry.create(WorldIds.EntityKind.MOTH, Vector2(a) + Vector2(0.5, -1.5)).id
	for h: MinerHandle in others:
		h.at(s.run.tick).face(180.0)
	s.step(6)
	var records: Array[Dictionary] = []
	s.run.falls.fell.connect(func(r: Dictionary) -> void: records.append(r))
	assert_true(s.run.falls.fall_unconscious(s.run, ada.entity_id, FallCause.Cause.MOTH_SMOTHER, {"moth_takes_lamp": moth, "creature": moth}))
	s.step(8)
	assert_eq(records.size(), 1)
	var r: Dictionary = records[0]
	assert_eq(str(r["lamp_outcome"]), LampDisposition.TAKEN)
	assert_eq(int(Variants.number(r["scream_mode"])), FallCause.Scream.FULL, "SND-15 screams and knocks for the other three")
	assert_eq(int(Variants.number(r["creature"])), moth)
	assert_eq(lamp.state(), GauzeLamp.State.CARRIED_OFF, "the lamp leaves with the Moth, snuffed")
	assert_eq(lamp.holder, moth)
	assert_eq(s.run.inventory.hands_of(ada.entity_id).slots[0].kind, ItemKinds.Kind.HEALING_KIT, "the belt stays")
	assert_eq(ada.connection.view.entities.size(), 0, "she sees nothing")
	for h: MinerHandle in others:
		assert_eq(s.run.miner_state.life(h.entity_id), MinerTransitions.Life.UPRIGHT)
	var seen_by_others: int = 0
	for h: MinerHandle in others:
		seen_by_others += h.connection.view.entities.size()
	assert_gt(seen_by_others, 0, "the others see on")
