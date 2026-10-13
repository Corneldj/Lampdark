extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-13: a carrier grabbed by the Stythe (RSC-03's grab) drops the body on their own tile that
## tick, and is dragged off without it; a teammate can lift it again. Observers never get the
## carried body as a token of its own: in the fringe the carrier and body are one token, and at
## identity the carrier's record shows the body over the shoulder.

const L = preload("res://tests/unit/mnr/lamp_world.gd")

const ROWS: PackedStringArray = [
	"######################",
	"#....................#",
	"#..o...a.b...........#",
	"#....................#",
	"######################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _carrying(s: Scenario) -> Array[MinerHandle]:
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	s.step(1)
	L.lit_in_hand(s, ann)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	ann.at(s.run.tick).walk_to(s.fixture.spot("b"))
	s.step(30)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(45)
	assert_true(s.run.carry.is_carrying(ann.entity_id))
	return [ann, bob]


func test_grabbed_carrier_drops_the_body() -> void:
	var s: Scenario = make({"seed": 95, "fixture": FixtureMap.from_ascii(ROWS)})
	var pair: Array[MinerHandle] = _carrying(s)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 30)
	s.step(20)
	var tile: Vector2i = s.run.registry.get_entity(ann.entity_id).tile()
	var dropped_at: Array[int] = [-1]
	var grabbed_at: Array[int] = [-1]
	s.run.carry.carry_ended.connect(func(_c: int, _b: int, reason: StringName) -> void:
		if reason == FiremanCarry.GRABBED:
			dropped_at[0] = s.run.tick)
	s.run.miner_state.state_changed.connect(func(entity: int, _o: int, new: int, _c: String) -> void:
		if entity == ann.entity_id and new == MinerTransitions.Life.GRABBED:
			grabbed_at[0] = s.run.tick)
	assert_gt(s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.STYTHE_DRAG, 99, 400), 0)
	s.step(1)
	assert_eq(dropped_at[0], grabbed_at[0], "the same tick")
	assert_eq(s.run.registry.get_entity(bob.entity_id).tile(), tile, "on her own tile")
	assert_true(s.run.falls.body_of(bob.entity_id).on_floor)
	assert_false(s.run.carry.is_carrying(ann.entity_id))
	# A teammate can lift it again.
	var cat: MinerHandle = s.add_miner("cat", tile)
	s.step(2)
	assert_true(s.run.carry.may_lift(s.run, cat.entity_id, bob.entity_id))


## The records `observer` holds now for entities near `at`.
func _near(s: Scenario, observer: MinerHandle, at: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in s.client(observer).entities_visible(s.run.tick).values():
		var e: Dictionary = raw
		var p: Vector2 = e.get("position", Vector2(INF, INF))
		if p.distance_to(at) < 1.0:
			out.append(e)
	return out


func test_one_token_in_the_fringe_and_the_body_at_identity() -> void:
	for light: float in [0.20, 0.30]:
		var s: Scenario = make({"seed": 96, "fixture": FixtureMap.from_ascii(ROWS)})
		var pair: Array[MinerHandle] = _carrying(s)
		var ann: MinerHandle = pair[0]
		var obs: MinerHandle = s.add_miner("obs", s.fixture.spot("o"), {"facing_deg": 0.0})
		obs.at(s.run.tick).face(0.0)
		var at: Vector2 = s.run.registry.get_entity(ann.entity_id).position
		# The hooked lamp shuttered, so only the spot lights them.
		ann.at(s.run.tick).lamp(true, LampRules.WICK_NORMAL)
		s.run.light.grid.add_spot(0, Vector2i(floori(at.x), floori(at.y)), light, 0)
		s.step(LampRules.step_ticks() + 4)
		var near: Array[Dictionary] = _near(s, obs, at)
		assert_eq(near.size(), 1, "%.2f: the carrier and the body are one record" % light)
		if near.is_empty():
			continue
		var e: Dictionary = near[0]
		if light < 0.25:
			assert_eq(int(Variants.number(e["level"])), 1, "the fringe: one miner-sized token")
		else:
			assert_eq(int(Variants.number(e["level"])), 2, "identity")
			assert_eq(int(Variants.number(e.get("in_hand", 0))) >> 8, ItemKinds.LOAD_BODY, "a body over the shoulder")
