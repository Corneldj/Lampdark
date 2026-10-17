extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-10 (Gameplay §3.6, Proposed "aboard"): when the cage leaves, everything whose centre lies on a
## deck tile goes up with one offset: miners in any state (an unconscious one included), a Hired
## Hand, an item and a load lying on the deck; never a fixture, nor anyone or anything off the deck.
## The snapshot names them, and cage_departed carries it.

const K = preload("res://tests/unit/lift/cage_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_everything_aboard_goes_up_with_one_offset() -> void:
	var s: Scenario = make({"seed": 10301, "fixture": K.E.T.C.scenario_fixture()})
	K.ready(s)
	var cage: Cage = s.run.cage
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var hand: MinerHandle = K.aboard(s, "hand", 1)
	var cid: MinerHandle = K.aboard(s, "cid", 2)
	var bob: MinerHandle = K.at_home(s, "bob")
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id or e == bob.entity_id
	s.run.miner_state.fall_unconscious(cid.entity_id, "test")
	var far: Vector2 = Vector2(K.far_deck_tile(s)) + Vector2(0.5, 0.5)
	var flare: int = s.run.inventory.world.put(s.run, s.run.inventory.world.make(ItemKinds.Kind.FLARE), far)
	var stretcher: int = s.run.loads.place(s.run, ItemKinds.Kind.STRETCHER, Vector2(cage.deck.position) + Vector2(1.0, 2.5))
	var off_deck: int = s.run.inventory.world.put(s.run, s.run.inventory.world.make(ItemKinds.Kind.CANDLE), Vector2(cage.deck.position) - Vector2(1.5, 1.5))
	s.step(3)
	var before: Dictionary = {}
	for e: int in [ann.entity_id, hand.entity_id, cid.entity_id, flare, stretcher]:
		before[e] = s.run.registry.get_entity(e).position
	var departed: Array[Dictionary] = []
	cage.cage_departed.connect(func(snap: Dictionary) -> void: departed.append(snap))
	K.pull(s, ann)
	assert_eq(cage.state, Cage.State.BELL, "Ann alone: the Hands and the unconscious do not count")
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.is_departed(), K.bell_ticks() + 10))
	assert_eq(departed.size(), 1)
	var riders: Array[int] = cage.riders()
	for e: int in [ann.entity_id, hand.entity_id, cid.entity_id, flare, stretcher]:
		assert_true(riders.has(e), "aboard: %d" % e)
	assert_false(riders.has(bob.entity_id), "Bob stayed home")
	assert_false(riders.has(off_deck), "the candle off the deck stays")
	for raw: Variant in cage.fixtures.values():
		assert_false(riders.has(int(Variants.number(raw))), "never a fixture")
	assert_eq(Array(Variants.array(departed[0]["entities"])), Array(riders))
	assert_true(Variants.array(departed[0]["miners"]).has(cid.entity_id), "the unconscious ride where they lie")
	# One offset for all: where each lay on the deck, it lies on the ride's deck.
	var offset: Vector2 = Vector2(ShaftRide.deck_origin() - cage.deck.position)
	for raw: Variant in before.keys():
		var e: int = int(Variants.number(raw))
		var was: Vector2 = before[raw]
		assert_almost_eq(s.run.registry.get_entity(e).position.distance_to(was + offset), 0.0, 0.01, "%d kept its place" % e)
