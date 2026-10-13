extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-05: the ring opens on a teammate within touch range who is seen with identity or just felt,
## never on a fringe token or out of reach; the range check rewinds to what the actor's client
## showed; the options reach only the actor.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const R = preload("res://tests/unit/mnr/ring_world.gd")
const F = preload("res://tests/unit/vis/feel_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_opens_in_touch_range_to_the_actor_only() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var pair: Array = R.pair(s)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	R.tap(s, ann)
	assert_true(s.run.ring.rings.has(ann.entity_id), "open")
	assert_true(Variants.flag(ann.connection.ring.get("open", false)), "her client has the ring")
	assert_true(bob.connection.ring.is_empty(), "his has nothing")


func test_not_out_of_reach() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.room()})
	W.light(s)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	s.add_miner("bob", a + Vector2i(3, 0))
	ann.at(0).face(0.0)
	s.step(4)
	R.tap(s, ann)
	assert_false(s.run.ring.rings.has(ann.entity_id), "3 tiles: no ring")


func test_dark_needs_feeling() -> void:
	var s: Scenario = make({"seed": 3, "fixture": W.room()})
	var pair: Array = R.pair(s, false)
	var ann: MinerHandle = pair[0]
	R.tap(s, ann)
	assert_false(s.run.ring.rings.has(ann.entity_id), "unseen in the dark: no ring")
	F.feel(s, ann)
	assert_eq(str(ann.connection.feel.last_feel["caption_key"]), "feel.someone_standing")
	assert_eq(str(ann.connection.feel.last_feel["verb_key"]), "verb.ring")
	R.tap(s, ann)
	assert_true(s.run.ring.rings.has(ann.entity_id), "just felt: the ring opens")


func test_never_on_a_fringe_token() -> void:
	var s: Scenario = make({"seed": 4, "fixture": W.room()})
	var pair: Array = R.pair(s, false)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	# Light enough to see a shape (a token), not who it is.
	s.run.light.grid.add_spot(0, s.run.registry.get_entity(bob.entity_id).tile(), 0.2, 0)
	s.step(4)
	R.tap(s, ann)
	assert_false(s.run.ring.rings.has(ann.entity_id), "a fringe token is never a target")


func test_rewound_range() -> void:
	var s: Scenario = make({"seed": 5, "fixture": W.room()})
	var pair: Array = R.pair(s)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	var shown: int = s.run.tick - 1
	s.run.registry.move(bob.entity_id, s.run.registry.get_entity(bob.entity_id).position + Vector2(1.5, 0))
	assert_true(s.run.ring.open(s.run, ann.entity_id, bob.entity_id, shown), "in reach on her screen: it opens")
	s.run.ring.close(s.run, ann.entity_id, "test")
	assert_false(s.run.ring.open(s.run, ann.entity_id, bob.entity_id), "on current positions alone it would not")
