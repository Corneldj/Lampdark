extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-10 (Gameplay §3.6): the ride. Progress counts only while the cage moves: 40 s to the top, the
## shaft bare rock only below 20 s; a pin stops it until that pin ends (another's end changes
## nothing). Riding, the walls turn from rock to brick at 20 s and the cage surfaces at 40 s
## (cage_surfaced). The ride zone gets no emergency light, and no Road Graph event crosses between
## it and the mine.

const K = preload("res://tests/unit/lift/cage_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_progress_the_lining_and_a_pin() -> void:
	var ride: ShaftRide = ShaftRide.new()
	var hz: float = Tuning.f(&"net.tick_hz")
	assert_eq(ShaftRide.ride_ticks(), roundi(40.0 * hz))
	ride.departed_at = 0
	var bare: Array[int] = []
	var tick: int = 0
	var surfaced: int = -1
	while surfaced < 0 and tick < 10000:
		tick += 1
		if ride.is_bare_rock():
			bare.append(ride.progress_ticks)
		if tick == roundi(10.0 * hz):
			ride.stop_for_pin(7)
		if tick == roundi(15.0 * hz):
			assert_false(ride.resume(8), "another pin's end changes nothing")
			assert_true(ride.resume(7))
		if ride.step(tick):
			surfaced = tick
	var last_bare: int = bare.max()
	var first_bare: int = bare.min()
	assert_eq(last_bare, roundi(20.0 * hz) - 1, "bare rock only below 20 s of progress")
	assert_eq(first_bare, 0)
	assert_eq(surfaced, roundi(40.0 * hz) + roundi(5.0 * hz), "40 s of progress, and the 5 s stopped for the pin")
	assert_true(ride.is_surfaced())
	assert_false(ride.is_bare_rock())


func test_the_ride_zone_brick_surface_and_isolation() -> void:
	var s: Scenario = make({"seed": 10201, "fixture": K.E.T.C.scenario_fixture()})
	K.ready(s)
	var cage: Cage = s.run.cage
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var bob: MinerHandle = K.at_home(s, "bob")
	# Bob stays below: a Hand, so Ann alone is the majority.
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == bob.entity_id
	var surfaced: Array[Dictionary] = []
	cage.cage_surfaced.connect(func(top: Dictionary) -> void: surfaced.append(top))
	K.pull(s, ann)
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.state == Cage.State.RIDING, K.bell_ticks() + 10))
	var face: Vector2i = ShaftRide.wall_faces(cage.deck.size)[0]
	assert_eq(s.run.mine.native.material_at(face), WorldIds.TileMaterial.ROCK, "bare rock first")
	assert_true(cage.is_bare_rock())
	# Isolation: a sound by Bob in base camp is not heard aboard, nor Ann's below.
	var heard: Array[int] = []
	var hook: Callable = func(id: int, _record: Dictionary, _audit: Dictionary = {}) -> void: heard.append(id)
	s.run.noise.player_hooks.append(hook)
	s.run.noise.set_player_listener(101, Vector2i(s.run.registry.get_entity(ann.entity_id).position))
	s.run.noise.set_player_listener(102, Vector2i(s.run.registry.get_entity(bob.entity_id).position))
	s.run.noise.emit(NoiseTypes.Type.VOICE, Vector2i(s.run.registry.get_entity(bob.entity_id).position), {"level_np": 30.0, "source": bob.entity_id,
		"mode": RoadGraphService.MODE_VOICE, "voice_id": 0})
	s.step(2)
	assert_false(heard.has(101), "nothing from the mine reaches the ride")
	heard.clear()
	s.run.noise.emit(NoiseTypes.Type.VOICE, Vector2i(s.run.registry.get_entity(ann.entity_id).position), {"level_np": 30.0, "source": ann.entity_id,
		"mode": RoadGraphService.MODE_VOICE, "voice_id": 0})
	s.step(2)
	assert_true(heard.has(101), "the rider hears herself")
	assert_false(heard.has(102), "nothing from the ride reaches the mine")
	s.run.noise.player_hooks.erase(hook)
	# No emergency light in the ride zone.
	var deck_tile: Vector2i = ShaftRide.deck_origin() + Vector2i(1, 1)
	assert_eq(s.run.light.grid.value(deck_tile), 0, "unlit but by its riders' lamps")
	# Brick at 20 s, the top at 40 s.
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return not cage.is_bare_rock(), roundi(21.0 * Tuning.f(&"net.tick_hz"))))
	s.step(1)
	assert_eq(s.run.mine.native.material_at(face), WorldIds.TileMaterial.BRICK, "brick-lined above 150 m")
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.state == Cage.State.SURFACED, roundi(21.0 * Tuning.f(&"net.tick_hz"))))
	assert_eq(surfaced.size(), 1, "cage_surfaced once")
	assert_eq(int(Variants.number(surfaced[0]["tick"])) - cage.ride.departed_at, ShaftRide.ride_ticks(), "40 s after it left")
	assert_true(Variants.array(surfaced[0]["entities"]).has(ann.entity_id))
