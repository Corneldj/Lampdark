extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-02: the relax is quiet, never safety (Gameplay §10.3, §11.3). A pin or a drag running when
## a relax begins runs to its end; the relax wakes no sleeping creature and starts no hunt.

const D = preload("res://tests/scenario/director/draught_world.gd")
const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")
const T = preload("res://tests/scenario/creatures/hunt_world.gd")
const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_a_pin_runs_to_its_end() -> void:
	T.ring(1)
	var s: Scenario = make({"seed": 1501, "fixture": T.road(), "director": true})
	D.stand_in(s)
	var w: Array = T.pinned(s)
	var who: MinerHandle = w[0]
	var t: Tapper = w[1]
	assert_eq(t.state.name, &"pin", "pinned")
	var ann: int = who.entity_id
	D.force_relax(s, true)
	var held: int = 0
	while s.run.miner_state.life(ann) == MinerTransitions.Life.GRABBED and held < 2000:
		s.step(1)
		held += 1
	assert_eq(s.run.miner_state.life(ann), MinerTransitions.Life.UNCONSCIOUS, "the pin ran out: she fell")
	assert_gt(held, 100, "the relax freed nobody: the pin held on")


func test_a_drag_runs_to_its_end() -> void:
	var s: Scenario = make({"seed": 1502, "fixture": H.road(), "overrides": H.W.ON, "director": true})
	var h: H = H.new()
	h.build(s, 40, 39, 95)
	D.stand_in(s)
	assert_true(h.until_state(&"drag", 200), "grabbed and dragged")
	D.force_relax(s, true)
	for _i: int in 100:
		s.step(1)
		assert_ne(s.run.miner_state.life(h.ann.entity_id), MinerTransitions.Life.UPRIGHT, "the relax never frees her")
	assert_eq(h.st.state.name, &"drag", "the drag runs on")


func test_a_relax_wakes_nobody_and_starts_no_hunt() -> void:
	var s: Scenario = make({"seed": 1503, "fixture": A.hall(), "director": true})
	s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(30, 10))
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	s.add_miner("ann", Vector2i(3, 3))
	D.stand_in(s)
	s.step(5)
	assert_true(Moth.SLEEPY.has(m.state.name), "the Moth sleeps")
	var hunts: Array[int] = []
	s.run.creatures.gate.hunt_started.connect(func(_c: Creature, _miner: int, _ch: bool) -> void: hunts.append(s.run.tick))
	D.force_relax(s, true)
	s.step(60)
	assert_true(Moth.SLEEPY.has(m.state.name), "the relax woke nothing")
	assert_eq(hunts.size(), 0, "and started no hunt")
