extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-02: at the start of a relax (Gameplay §10.3) hunts end and creatures drift home, each by its
## own movement, never by a jump:
## - a Stythe in Hunt (not winding up) stands down and heads for its lair;
## - a Stythe in WindUp completes;
## - a prowling Moth commits to nothing and drifts to its roost;
## - an attending Tapper stays in rock and plays nothing.
## (A Moth's Frenzy runs through the relax: test_frenzy_runs_through_relax.)

const D = preload("res://tests/scenario/director/draught_world.gd")
const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")
const T = preload("res://tests/scenario/creatures/hunt_world.gd")
const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_a_hunting_stythe_stands_down_and_heads_for_its_lair() -> void:
	var s: Scenario = make({"seed": 1401, "fixture": H.road(), "overrides": H.W.ON, "director": true})
	var h: H = H.new()
	h.build(s, 40, 30, 95)
	D.stand_in(s)
	assert_true(h.until_state(&"hunt", 200), "it hunts Ann in the build")
	D.force_relax(s, true)
	s.step(3)
	assert_false(s.run.creatures.gate.is_hunting(h.st), "the relax ended the hunt")
	assert_ne(h.st.state.name, &"hunt")
	var lair: Vector2 = Vector2(95.5, 2.5)
	var last: Vector2 = h.st.position(s.run)
	var from: float = last.distance_to(lair)
	var stride: float = Tuning.f(&"stythe.speed") / Tuning.f(&"net.tick_hz") + 1e-3
	for _i: int in 200:
		s.step(1)
		var now: Vector2 = h.st.position(s.run)
		assert_true(now.distance_to(last) <= stride, "by its own movement, never a jump")
		assert_ne(h.st.state.name, &"hunt", "no hunt on the way")
		last = now
	assert_lt(last.distance_to(lair), from - 10.0, "it drifted toward its lair")


func test_a_stythe_winding_up_completes() -> void:
	var s: Scenario = make({"seed": 1402, "fixture": H.road(), "overrides": H.W.ON, "director": true})
	var h: H = H.new()
	h.build(s, 40, 36, 95)
	D.stand_in(s)
	assert_true(h.until_state(&"windup", 300), "it winds up on Ann")
	D.force_relax(s, true)
	assert_true(s.run_until(func(_sv: Variant) -> bool:
		return s.run.miner_state.life(h.ann.entity_id) == MinerTransitions.Life.GRABBED, 100),
		"the wind-up under way finished: the grab landed")


func test_a_prowling_moth_commits_to_nothing_and_drifts_to_its_roost() -> void:
	var s: Scenario = make({"seed": 1403, "fixture": A.hall(), "director": true})
	var m: Moth = A.awake(s, Vector2i(5, 10), false)
	m.roost = Vector2i(34, 10)
	A.lit_miner(s, "ann", Vector2i(12, 4))
	D.stand_in(s)
	D.force_relax(s, true)
	var commits: Array[bool] = []
	s.run.creatures.gate.hunt_started.connect(func(_c: Creature, _miner: int, chosen: bool) -> void: commits.append(chosen))
	var roost: Vector2 = Vector2(m.roost) + Vector2(0.5, 0.5)
	var last: Vector2 = m.position(s.run)
	var from: float = last.distance_to(roost)
	var stride: float = m.max_speed / Tuning.f(&"net.tick_hz") + 1e-3
	for _i: int in 200:
		s.step(1)
		var now: Vector2 = m.position(s.run)
		assert_true(now.distance_to(last) <= stride, "by its own movement, never a jump")
		last = now
	assert_eq(commits.size(), 0, "it committed to nothing")
	assert_lt(last.distance_to(roost), from - 5.0, "it drifted toward its roost")


func test_an_attending_tapper_stays_in_rock_and_plays_nothing() -> void:
	T.ring(1)
	var s: Scenario = make({"seed": 1404, "fixture": T.road(), "director": true})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(20, 5))
	var t: Tapper = T.tapper(s, Vector2i(10, 8))
	D.stand_in(s)
	s.run.creatures.gate.pull_of = func(m: int) -> float: return 40.0 if m == bob.entity_id else 0.0
	assert_gt(T.until_state(s, t, &"attend", 100), -1, "it attends Bob (Pull 40)")
	D.force_relax(s, true)
	var tells: int = 0
	for _i: int in 200:
		s.step(1)
		var tile: Vector2i = WorldCoords.tile_at(t.position(s.run))
		assert_true(s.run.mine.native.is_solid(tile), "it stays in rock")
		if t.state.plays_tell:
			tells += 1
	assert_ne(t.state.name, &"attend", "it no longer attends")
	assert_false(s.run.creatures.gate.is_hunting(t))
	assert_eq(tells, 0, "and plays nothing")
	assert_false(s.run.relax.illusions_allowed(), "no illusion either")
