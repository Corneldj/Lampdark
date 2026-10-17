extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-10 (Gameplay §3.6): the hold bell. The majority rings one 20 np event at the cage, lasting
## lift.hold_bell_s; departure is committed (a vote lost no longer matters), and after exactly 20 s
## the cage leaves with everything aboard at that tick: a straggler who stepped on during the bell
## rides, one who stepped off is left below. Afterwards the deck site is an open shaft never boarded
## again, and the cord is gone. The engine running dry during the bell cancels departure.

const K = preload("res://tests/unit/lift/cage_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_bell_then_departure_with_everything_aboard() -> void:
	var s: Scenario = make({"seed": 10101, "fixture": K.E.T.C.scenario_fixture()})
	K.ready(s)
	var cage: Cage = s.run.cage
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var bob: MinerHandle = K.aboard(s, "bob", 1)
	var flare: int = s.run.inventory.world.put(s.run, s.run.inventory.world.make(ItemKinds.Kind.FLARE), Vector2(K.far_deck_tile(s)) + Vector2(0.5, 0.5))
	var from: int = s.run.noise.event_log.size()
	K.pull(s, ann)
	K.pull(s, bob)
	assert_eq(cage.state, Cage.State.BELL)
	var bells: Array[NoiseSystem.Event] = K.bells(s, from)
	assert_eq(bells.size(), 1, "one bell")
	assert_eq(bells[0].level_np, 20.0)
	assert_almost_eq(bells[0].duration_s, Tuning.f(&"lift.hold_bell_s"), 1e-6)
	assert_eq(Vector2i(bells[0].origins[0]), cage.deck.get_center(), "at the cage")
	# During the bell: Bob steps off (committed, it still leaves), a straggler steps on.
	K.move_to(s, bob, s.run.base_camp.medbay_tables()[0])
	var cid: MinerHandle = K.at_home(s, "cid")
	K.move_to(s, cid, K.far_deck_tile(s))
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.state != Cage.State.BELL, K.bell_ticks() + 10))
	assert_eq(cage.state, Cage.State.RIDING)
	assert_eq(cage.ride.departed_at - bells[0].tick, K.bell_ticks(), "exactly 20 s after the bell")
	var riders: Array[int] = cage.riders()
	assert_true(riders.has(ann.entity_id))
	assert_true(riders.has(cid.entity_id), "the straggler rides")
	assert_false(riders.has(bob.entity_id), "the one who stepped off is left below")
	assert_true(riders.has(flare), "and what lay on the deck")
	# They are in the ride zone; the deck site is an open shaft and the cord is gone.
	var ride_cell: Vector2i = WorldCoords.cell_of(WorldCoords.tile_at(s.run.registry.get_entity(ann.entity_id).position))
	assert_eq(ride_cell, ShaftRide.RIDE_CELL)
	for y: int in range(cage.deck.position.y, cage.deck.end.y):
		for x: int in range(cage.deck.position.x, cage.deck.end.x):
			assert_false(s.run.mine.native.is_walkable(Vector2i(x, y), false), "the deck site never boarded again")
	assert_false(cage.fixtures.has("cord"), "the cord is gone")
	K.pull(s, bob)
	assert_eq(cage.cord.votes.size(), 0, "nothing to pull")


func test_a_dry_engine_during_the_bell_cancels_departure() -> void:
	var s: Scenario = make({"seed": 10102, "fixture": K.E.T.C.scenario_fixture()})
	K.ready(s)
	var cage: Cage = s.run.cage
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	K.pull(s, ann)
	assert_eq(cage.state, Cage.State.BELL)
	s.step(100)
	s.run.fuel.level_ticks = 1
	s.step(3)
	assert_false(s.run.engine.is_running(), "dry")
	assert_eq(cage.state, Cage.State.WAITING, "departure cancelled")
	s.step(K.bell_ticks())
	assert_false(cage.is_departed(), "it never left")
	assert_eq(str(cage.log.back()["what"]), "cancelled")
