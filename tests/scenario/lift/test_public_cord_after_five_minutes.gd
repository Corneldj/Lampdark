extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-10 (Gameplay §3.6, §13.10): the public cord. In a public run of four conscious miners, two
## aboard both pulling ring no bell before the engine has run lift.cord_public_after_s (5 minutes):
## the majority is of the run's conscious miners, and two of four is not it. From then on it is of
## the conscious miners aboard, and the same two pulls ring it. A friends' run never relaxes.

const K = preload("res://tests/unit/lift/cage_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _two_aboard_of_four(run_seed: int, mode: ServerConfig.Mode) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": K.E.T.C.scenario_fixture(), "mode": mode})
	K.ready(s, 200.0)
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var bob: MinerHandle = K.aboard(s, "bob", 1)
	K.at_home(s, "cid")
	K.at_home(s, "dot")
	K.pull(s, ann)
	K.pull(s, bob)
	return [s, s.run.cage]


func test_after_five_minutes_two_aboard_suffice() -> void:
	var r: Array = _two_aboard_of_four(10601, ServerConfig.Mode.PUBLIC)
	var s: Scenario = r[0]
	var cage: Cage = r[1]
	assert_eq(cage.cord.pullers().size(), 2)
	assert_eq(SignalCord.required(s.run, cage.deck), 3, "before 300 s: of the run's four")
	s.step(20)
	assert_eq(cage.state, Cage.State.WAITING, "two of four: no bell")
	# The engine runs on past 300 s.
	var at_300: int = s.run.engine.caught_at + roundi(Tuning.f(&"lift.cord_public_after_s") * Tuning.f(&"net.tick_hz"))
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.tick >= at_300 - 1, 2200))
	assert_eq(cage.state, Cage.State.WAITING)
	s.step(3)
	assert_eq(SignalCord.required(s.run, cage.deck), 2, "after 300 s: of the two aboard")
	assert_eq(cage.state, Cage.State.BELL, "the same two pulls ring it")


func test_a_friends_run_never_relaxes() -> void:
	var r: Array = _two_aboard_of_four(10602, ServerConfig.Mode.FRIENDS)
	var s: Scenario = r[0]
	var cage: Cage = r[1]
	s.run.engine.caught_at -= roundi(400.0 * Tuning.f(&"net.tick_hz"))
	s.step(5)
	assert_eq(SignalCord.required(s.run, cage.deck), 3)
	assert_eq(cage.state, Cage.State.WAITING, "two of four, however long it runs")
