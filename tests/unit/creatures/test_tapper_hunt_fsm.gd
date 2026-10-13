extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09's hunt states: Approach to the wall nearest the sound, Listen for the crew's pause
## (60 ticks at crew count 3, 40 at 4), Search for the ring's search time with taps, then the hunt
## ends; no taps in Listen; the arm only in WindUp, Pin and ReStrike; no Approach before 4:00 in
## staged run 1.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func _arms(s: Scenario) -> int:
	var n: int = 0
	for id: int in s.run.registry.ids():
		if s.run.registry.get_entity(id).kind == WorldIds.EntityKind.TAPPER_ARM:
			n += 1
	return n


func _flow(crew: int) -> Dictionary:
	var s: Scenario = make({"seed": 10 + crew, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(14, 5))
	for i: int in crew - 1:
		s.add_miner("far%d" % i, Vector2i(36 - i, 5))
	var t: Tapper = W.tapper(s, Vector2i(10, 8))
	s.step(3)
	W.talk(s, ann)
	var counts: Dictionary = {}
	var taps_in: Dictionary = {}
	var arms_seen: Array[int] = [0]
	s.run.creatures.log.logged.connect(func(e: Dictionary) -> void:
		if e["type"] == &"tapper_taps":
			taps_in[t.state.name] = int(Variants.number(taps_in.get(t.state.name, 0))) + 1)
	s.on_tick = func(sc: Scenario) -> void:
		counts[t.state.name] = int(Variants.number(counts.get(t.state.name, 0))) + 1
		arms_seen[0] += _arms(sc)
	s.step(600)
	return {"counts": counts, "taps": taps_in, "arms": arms_seen[0], "state": t.state.name, "hunting": s.run.creatures.gate.is_hunting(t)}


func test_approach_listen_search_end() -> void:
	var r: Dictionary = _flow(3)
	var counts: Dictionary = r["counts"]
	var taps: Dictionary = r["taps"]
	gut.p("ticks by state: %s; taps by state: %s" % [counts, taps])
	assert_gt(int(Variants.number(counts.get(&"approach", 0))), 0, "it approached")
	assert_eq(int(Variants.number(counts.get(&"listen", 0))), 60, "Listen lasts 60 ticks at crew count 3")
	assert_eq(int(Variants.number(counts.get(&"search", 0))), 400, "Search runs the ring's 20 s")
	assert_false(taps.has(&"listen"), "no taps while it listens")
	assert_gt(int(Variants.number(taps.get(&"search", 0))), 4, "it taps while it searches")
	var end_state: StringName = r["state"]
	var arms: int = r["arms"]
	assert_eq(end_state, &"patrol", "then the hunt ends")
	assert_false(Variants.flag(r["hunting"]))
	assert_eq(arms, 0, "no arm out of the rock outside WindUp and Pin")


func test_listen_at_crew_four() -> void:
	var counts: Dictionary = _flow(4)["counts"]
	assert_eq(int(Variants.number(counts.get(&"listen", 0))), 40, "40 ticks at crew count 4")


func test_staged_run_one() -> void:
	var s: Scenario = make({"seed": 20, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(14, 5))
	var t: Tapper = W.tapper(s, Vector2i(10, 8))
	t.hunt.hunt_from_tick = 4800
	s.step(3)
	W.talk(s, ann)
	var hunted: Array[bool] = [false]
	s.on_tick = func(_sc: Scenario) -> void:
		if TapperHunt.busy(t):
			hunted[0] = true
	for i: int in 10:
		W.talk(s, ann)
		s.step(20)
	assert_false(hunted[0], "no Approach (nor any strike) before 4:00")
	s.run.tick = 4800
	W.talk(s, ann)
	s.step(3)
	assert_true(TapperHunt.busy(t), "from 4:00 it may hunt")
