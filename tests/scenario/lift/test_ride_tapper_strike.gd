extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-10 with CRT-09 (Gameplay §3.6, §7.3): the Tapper in the bare rock of the shaft. It follows the
## cage into the shaft's rock; a rider by the cage's side who talks from 10 s is struck and pinned,
## which stops the cage in the dark; a teammate's silent pull breaks the pin and the ride goes on to
## the top. A rider in the deck's middle, more than 1.5 tiles from every side, is never struck, and
## no strike lands once the walls are brick.

const K = preload("res://tests/unit/lift/cage_world.gd")
const A = preload("res://tests/scenario/apex/apex_world.gd")
const T = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_strike_in_the_shaft_stops_the_cage_until_the_pull() -> void:
	var s: Scenario = make({"seed": 10401, "fixture": K.E.T.C.scenario_fixture(), "overrides": A.ON})
	K.ready(s)
	var gate: Gate = A.road_gate(s)
	var t: Tapper = A.tapper(s, A.in_rock(gate, 14, 4))
	var cage: Cage = s.run.cage
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var bob: MinerHandle = K.aboard(s, "bob", 1)
	K.pull(s, ann)
	K.pull(s, bob)
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.is_departed(), K.bell_ticks() + 10))
	# Bob to the deck's middle: more than 1.5 tiles from every side.
	var middle: Vector2 = Vector2(ShaftRide.deck_origin()) + Vector2(cage.deck.size) / 2.0
	s.run.movement.place(s.run, bob.entity_id, middle)
	var hz: float = Tuning.f(&"net.tick_hz")
	var pins: Array[int] = []
	var victims: Array[int] = []
	var at_progress: Array[int] = []
	s.run.holds.grab_begun.connect(func(id: int, kind: GrabHold.Kind, _c: int, victim: int) -> void:
		if kind == GrabHold.Kind.TAPPER_PIN:
			pins.append(id)
			victims.append(victim)
			at_progress.append(cage.ride.progress_ticks))
	var talk_from: int = roundi(10.0 * hz)
	var struck: bool = s.run_until(func(sc: Scenario) -> bool:
		if cage.ride.progress_ticks >= talk_from and sc.run.tick % 10 == 0:
			T.talk(sc, ann)
		return not pins.is_empty(), roundi(16.0 * hz))
	assert_true(cage.tapper_in_shaft, "the Tapper followed into the shaft's rock")
	assert_true(struck, "struck in the bare rock")
	assert_eq(victims[0], ann.entity_id, "the rider by the side")
	assert_lt(at_progress[0], roundi(20.0 * hz), "below the brick")
	assert_eq(cage.look(s.run), FixtureKinds.CageLook.STOPPED, "the governor tripped: stopped in the dark")
	var held: int = cage.ride.progress_ticks
	s.step(60)
	assert_eq(cage.ride.progress_ticks, held, "no progress while pinned")
	# A teammate's silent pull.
	assert_true(s.run.holds.end_grab(s.run, pins[0], GrabHold.Outcome.BROKEN))
	s.step(5)
	assert_gt(cage.ride.progress_ticks, held, "the ride goes on")
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.state == Cage.State.SURFACED, roundi(40.0 * hz)), "to the top")
	for i: int in victims.size():
		assert_ne(victims[i], bob.entity_id, "the deck's middle is beyond its reach")
		assert_lt(at_progress[i], roundi(20.0 * hz), "never once the walls are brick")
	assert_false(cage.tapper_in_shaft, "it dropped back below at the brick")
	assert_ne(WorldCoords.cell_of(t.tile(s.run)), ShaftRide.RIDE_CELL)
