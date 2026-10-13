extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-07: in a black room a miner finds a lamp by feel, then picks it up by interacting again; a
## felt phone is cranked (LFT-12's handler, stubbed) and a felt unconscious miner lifted into a
## fireman's carry (RSC-01's 2 s lift).

const W = preload("res://tests/unit/mnr/belt_world.gd")
const F = preload("res://tests/unit/vis/feel_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_find_a_lamp_and_pick_it_up() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var lamp: GauzeLamp = s.run.lamps.create(s.run, 0.5, 2, false, LampRules.WICK_NORMAL, Vector2(a) + Vector2(0.5, 1.5))
	s.step(2)
	F.feel(s, ann)
	assert_eq(str(ann.connection.feel.last_feel["caption_key"]), "feel.item.gauze_lamp", "'[a gauze lamp]'")
	assert_eq(str(ann.connection.feel.last_feel["verb_key"]), "verb.pick_up")
	assert_eq(int(Variants.number(ann.connection.feel.last_feel["bearing_q"])), 4, "south: step 4 of 16")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(40)
	assert_eq(s.run.inventory.hands_of(ann.entity_id).lamp_hand, lamp.item, "interacting again picks it up, in the dark")


func test_crank_a_phone_and_lift_a_body() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var phone: int = s.run.registry.create(WorldIds.EntityKind.PHONE, Vector2(a) + Vector2(-0.5, 0.5)).id
	var cranked: Array[int] = []
	s.run.feel.register_felt_use(WorldIds.EntityKind.PHONE, func(_r: RunState, miner: int, entity: int) -> bool:
		cranked.append(entity)
		return miner > 0)
	s.step(2)
	F.feel(s, ann)
	assert_eq(str(ann.connection.feel.last_feel["caption_key"]), "feel.telephone")
	assert_eq(str(ann.connection.feel.last_feel["verb_key"]), "verb.crank")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 10)
	s.step(15)
	assert_eq(cranked, [phone] as Array[int], "interacting again cranks the felt phone")
	s.run.registry.destroy(phone)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(1, 0))
	s.step(2)
	s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST)
	s.step(2)
	F.feel(s, ann)
	assert_eq(str(ann.connection.feel.last_feel["caption_key"]), "feel.body_breathing", "'[a body, breathing]'")
	assert_eq(str(ann.connection.feel.last_feel["verb_key"]), "verb.lift")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 50)
	s.step(60)
	assert_eq(s.run.falls.body_of(bob.entity_id).carried_by, ann.entity_id, "lifted into a fireman's carry")
