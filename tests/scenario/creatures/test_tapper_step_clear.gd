extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09: the wind-up lasts tapper.windup_s (1.25 s, 25 ticks, since the first playtest found 0.5 s
## undodgeable); a miner who steps beyond 1.5 tiles before its end is missed (at 0 and at 120 ms round
## trip, under NET-06's defender rule) and the Tapper listens again. The target is warned: a crack only
## they hear and dust bursting off the face; the arm reaches them as the Tapper, facing out of the
## wall. A walker reacting 0.4 s after the warning (a person's reaction; NET-06 judges the step by
## the client's own time) gets the 2 tiles along the wall out of reach; at 0.5 s they could not.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func _step_clear(rtt: int) -> Dictionary:
	var s: Scenario = make({"seed": 60 + rtt, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 5))
	ann.link(rtt, 0.0)
	var t: Tapper = W.tapper(s, Vector2i(10, 4))
	t.follower.stop()
	s.step(4)
	W.talk(s, ann)
	W.until_state(s, t, &"windup", 20)
	# She runs east the moment the arm leaves the wall.
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 30)
	s.step(30)
	var w: Array[Dictionary] = s.run.creatures.log.of_type(&"wind_up")
	return {"outcome": str(w[0]["outcome"]) if not w.is_empty() else "none", "len": int(Variants.number(w[0]["end"])) - int(Variants.number(w[0]["start"])) if not w.is_empty() else -1,
		"state": t.state.name, "life": W.life(s, ann.entity_id)}


func test_at_0_ms() -> void:
	var r: Dictionary = _step_clear(0)
	gut.p("0 ms: %s" % r)
	var length: int = r["len"]
	var outcome: String = r["outcome"]
	var life: int = r["life"]
	assert_eq(length, roundi(Tuning.f(&"tapper.windup_s") * Tuning.f(&"net.tick_hz")), "the tuned wind-up")
	assert_eq(length, 25, "1.25 s")
	assert_eq(outcome, "missed", "she stepped clear")
	assert_eq(life, MinerTransitions.Life.UPRIGHT)


func test_at_120_ms() -> void:
	var r: Dictionary = _step_clear(120)
	gut.p("120 ms: %s" % r)
	var outcome: String = r["outcome"]
	var life: int = r["life"]
	assert_eq(outcome, "missed", "the step, issued before the end on her screen, counts")
	assert_eq(life, MinerTransitions.Life.UPRIGHT)


func test_a_walker_reacting_in_time_escapes_and_is_warned() -> void:
	var s: Scenario = make({"seed": 75, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 5), {"facing_deg": 0.0})
	ann.brain = null
	ann.link(120, 0.0)
	L.lit_in_hand(s, ann)
	var heard: Array[int] = []
	var prev: Callable = s.run.audio.sink
	s.run.audio.sink = func(slot: int, r: AudioRecord) -> void:
		if slot == ann.slot:
			heard.append(r.type)
		if prev.is_valid():
			prev.call(slot, r)
	var t: Tapper = W.tapper(s, Vector2i(10, 4))
	t.follower.stop()
	s.step(4)
	var bursts: int = s.run.tells.bursts_sent
	W.talk(s, ann)
	W.until_state(s, t, &"windup", 20)
	assert_eq(t.state.name, &"windup", "it strikes")
	var started: int = s.run.tick
	assert_has(heard, LocalSounds.Type.ROCK_CRACK, "warned: the crack beside her")
	s.step(2)
	assert_gt(s.run.tells.bursts_sent, bursts, "dust bursts off the face")
	var arm: Dictionary = {}
	for _i: int in 5:
		for raw: Variant in ann.connection.view.entities.keys():
			var e: Dictionary = ann.connection.view.entities[raw]
			if int(Variants.number(e.get("size_or_kind", 0))) == SeenKind.Kind.TAPPER:
				arm = e
		if not arm.is_empty():
			break
		s.step(1)
	assert_false(arm.is_empty(), "the arm reaches her client as the Tapper")
	var toward: Vector2 = ViewGeometry.facing_vector(int(Variants.number(arm.get("facing", 0))))
	assert_gt(toward.dot(Vector2(0, 1)), 0.9, "facing out of the wall, toward her (south)")
	# She reacts 0.4 s after the warning and walks along the wall, away from the face.
	s.step(started + 8 - s.run.tick)
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 30)
	s.step(40)
	var w: Array[Dictionary] = s.run.creatures.log.of_type(&"wind_up")
	assert_false(w.is_empty())
	assert_eq(str(w[0]["outcome"]), "missed", "a walker reacting in 0.4 s escapes a 1.25 s wind-up")
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.UPRIGHT)
