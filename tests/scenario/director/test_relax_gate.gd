extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-02: Gameplay §10.3's table, through each creature's own decisions and marks, with the
## Director's relax provider (RelaxRules) in charge. In RELAX every chosen entry on the table's left
## is refused and everything on its right goes ahead; in BUILD all of them go ahead.
## Left (chosen): a prowling Moth committing to a light; the Tapper from Attend or Patrol to
## Approach; the Stythe from Lurk to Hunt; every illusion.
## Right: a Moth's Frenzy (woken by light, a flash or a flare); a strike at a Tapper's wall; the
## Stythe's grab of a miner who walks unlit into its reach; its collecting (no hunt); the apex.
## Shadowing (CRT-16), laying (CRT-06) and homing (CRT-05) arrive with their tickets: none is a hunt,
## so none passes the gate.

const D = preload("res://tests/scenario/director/draught_world.gd")
const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")
const T = preload("res://tests/scenario/creatures/hunt_world.gd")
const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")

var _seed: int = 1100


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


## [what, row(relax) -> it happened, allowed in a relax]
func test_the_relax_table() -> void:
	var rows: Array = [
		["a prowling Moth commits to a lit miner", _moth_prowl, false],
		["the Tapper turns from Patrol to Approach", _tapper_approach, false],
		["the Stythe turns from Lurk to Hunt", _stythe_hunt, false],
		["an illusion may play", _illusion, false],
		["a Moth's Frenzy hunts", _moth_frenzy, true],
		["a Tapper strikes at its wall", _tapper_strike, true],
		["the Stythe takes a miner who walks unlit into its reach", _stythe_walk_in, true],
		["the Stythe collects a body", _stythe_collect, true],
		["in the apex, a prowling Moth commits", _apex_moth_prowl, true],
	]
	for row: Array in rows:
		var happens: Callable = row[1]
		assert_true(Variants.flag(happens.call(false)), "in a build: %s" % row[0])
		var allowed: bool = Variants.flag(row[2])
		assert_eq(Variants.flag(happens.call(true)), allowed, "in a relax: %s %s" % [row[0], "(allowed)" if allowed else "(refused)"])


func _make(relax: bool, fixture: Variant, overrides: Dictionary = {}) -> Scenario:
	_seed += 1
	var cfg: Dictionary = {"seed": _seed, "fixture": fixture, "director": true}
	if not overrides.is_empty():
		cfg["overrides"] = overrides
	var s: Scenario = make(cfg)
	D.force_relax(s, relax)
	return s


func _moth_prowl(relax: bool) -> bool:
	var s: Scenario = _make(relax, A.hall())
	var m: Moth = A.awake(s, Vector2i(5, 10), false)
	A.lit_miner(s, "ann", Vector2i(15, 10))
	D.stand_in(s)
	var chosen: Array[bool] = []
	s.run.creatures.gate.hunt_started.connect(func(_c: Creature, _miner: int, ch: bool) -> void: chosen.append(ch))
	s.step(200)
	assert_true(m.state.name != &"asleep")
	return chosen.has(true)


func _tapper_approach(relax: bool) -> bool:
	T.ring(1)
	var s: Scenario = _make(relax, T.road())
	var bob: MinerHandle = s.add_miner("bob", Vector2i(14, 5))
	var t: Tapper = T.tapper(s, Vector2i(10, 8))
	D.stand_in(s)
	s.step(3)
	T.talk(s, bob)
	for _i: int in 10:
		s.step(1)
		if t.state.name == &"approach":
			return true
	return false


func _stythe_hunt(relax: bool) -> bool:
	var s: Scenario = _make(relax, H.road(), H.W.ON)
	var h: H = H.new()
	h.build(s, 40, 30, 95)
	D.stand_in(s)
	for _i: int in 200:
		s.step(1)
		if h.st.state.name == &"hunt":
			return true
	return false


func _illusion(relax: bool) -> bool:
	var s: Scenario = _make(relax, D.hall())
	s.step(1)
	return s.run.relax.illusions_allowed()


func _moth_frenzy(relax: bool) -> bool:
	var s: Scenario = _make(relax, A.hall())
	var m: Moth = A.awake(s, Vector2i(5, 10), true)
	A.lit_miner(s, "ann", Vector2i(15, 10))
	D.stand_in(s)
	return A.until_state(s, m, &"hunt", 200) >= 0


func _tapper_strike(relax: bool) -> bool:
	T.ring(1)
	var s: Scenario = _make(relax, T.road())
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 5))
	var t: Tapper = T.tapper(s, Vector2i(10, 4))
	t.follower.stop()
	D.stand_in(s)
	s.step(3)
	T.talk(s, ann)
	return T.until_state(s, t, &"pin", 40) >= 0


func _stythe_walk_in(relax: bool) -> bool:
	var s: Scenario = _make(relax, H.road(), H.W.ON)
	var h: H = H.new()
	h.build(s, 40, 39, 95) # Ann already within its reach, unlit
	D.stand_in(s)
	for _i: int in 200:
		s.step(1)
		if s.run.miner_state.life(h.ann.entity_id) == MinerTransitions.Life.GRABBED:
			return true
	return false


func _stythe_collect(relax: bool) -> bool:
	var s: Scenario = _make(relax, H.road(), H.W.ON)
	var h: H = H.new()
	h.build(s, 40, 30, 95)
	D.stand_in(s)
	s.run.miner_state.fall_unconscious(h.ann.entity_id, "test")
	for _i: int in 400:
		s.step(1)
		if h.st.state.name == &"collect":
			return true
	return false


func _apex_moth_prowl(relax: bool) -> bool:
	var s: Scenario = _make(relax, A.hall())
	s.run.creatures.gate.apex_on = func() -> bool: return true # LFT-09's provider, standing in
	var m: Moth = A.awake(s, Vector2i(5, 10), false)
	A.lit_miner(s, "ann", Vector2i(15, 10))
	D.stand_in(s)
	var chosen: Array[bool] = []
	s.run.creatures.gate.hunt_started.connect(func(_c: Creature, _miner: int, ch: bool) -> void: chosen.append(ch))
	s.step(200)
	assert_true(m.state.name != &"asleep")
	return chosen.has(true)
