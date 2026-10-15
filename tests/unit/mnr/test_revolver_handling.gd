extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-16: draw and put away take 20 ticks; drawn, every free-hand action but feeling, levers and
## phones is refused; aiming refuses running; it fires only while aiming, at most once per 10
## ticks, a round a shot; an empty cylinder clicks for the shooter alone. Reload adds a round per 20
## held ticks from the box, with an 8 np click, up to six; a box holds at most 12. Hands never pick
## it up, draw or fire it.

const R = preload("res://tests/unit/mnr/revolver_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_draw_and_put_away_in_twenty_ticks() -> void:
	var s: Scenario = make({"seed": 1201, "fixture": R.hall()})
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	s.step(2)
	var belt: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	belt.slots[0] = Revolver.make(s.run)
	belt.selected = 0
	ann.at(s.run.tick).hold(InputRecord.HOLD_USE, 40)
	var pressed: int = s.run.tick
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.revolver.is_drawn(ann.entity_id), 60))
	var took: int = s.run.tick - pressed
	gut.p("drawn after %d ticks (input delay included)" % took)
	var lag: int = took - 20
	assert_between(lag, 0, 4, "20 ticks after the press reaches the server")
	assert_null(belt.slots[0], "out of its slot")
	assert_true(belt.free_hand_blocked(&"relight"), "the flint is blocked")
	assert_true(belt.free_hand_blocked(&"chalk"), "chalk too")
	assert_false(belt.free_hand_blocked(&"feel"), "feeling still works")
	assert_false(belt.free_hand_blocked(&"lever"), "and levers")
	assert_false(belt.free_hand_blocked(&"phone"), "and phones")
	s.step(25)
	ann.at(s.run.tick).hold(InputRecord.HOLD_USE, 40)
	pressed = s.run.tick
	assert_true(s.run_until(func(sc: Scenario) -> bool: return not sc.run.revolver.is_drawn(ann.entity_id), 60))
	assert_eq(s.run.tick - pressed - lag, 20, "put away in 20 ticks")
	assert_eq(belt.slots[0].kind, ItemKinds.Kind.REVOLVER, "back in the slot")


func test_aiming_walks_and_firing_needs_aim_and_a_round() -> void:
	var s: Scenario = make({"seed": 1202, "fixture": R.hall()})
	R.lit(s)
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	s.step(2)
	var gun: Item = R.armed(s, ann, 6)
	R.trigger(s, ann)
	s.step(6)
	assert_eq(s.run.revolver.shots.size(), 0, "not aiming: nothing")
	R.aim(s, ann, 300)
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 40)
	s.step(30)
	var m: MovementSystem.Miner = s.run.movement.miner(ann.slot)
	assert_true(s.run.revolver.is_aiming(ann.entity_id))
	assert_ne(m.state.gait, MinerMotion.RUN, "aiming: never a run")
	for t: int in range(s.run.tick, s.run.tick + 40):
		R.trigger(s, ann, 0.0, t)
	s.step(46)
	assert_between(s.run.revolver.shots.size(), 4, 5, "at most one shot per 10 ticks (%d)" % s.run.revolver.shots.size())
	assert_eq(Revolver.rounds_in(gun), 6 - s.run.revolver.shots.size(), "a round a shot")
	var gaps: Array[int] = []
	for i: int in range(1, s.run.revolver.shots.size()):
		gaps.append(int(Variants.number(s.run.revolver.shots[i]["tick"])) - int(Variants.number(s.run.revolver.shots[i - 1]["tick"])))
	for g: int in gaps:
		assert_gte(g, 10)
	gun.state["rounds"] = 0
	var before: int = s.run.audio.deliveries.size()
	var shots_before: int = s.run.revolver.shots.size()
	R.trigger(s, ann)
	s.step(6)
	assert_eq(s.run.revolver.shots.size(), shots_before, "empty: no shot")
	var clicks: int = 0
	for d: Dictionary in s.run.audio.deliveries.slice(before):
		clicks += 1 if int(Variants.number(d["client"])) == ann.slot else 0
	assert_gte(clicks, 1, "a dry click, for her")


func test_reload_a_round_per_twenty_ticks_up_to_six() -> void:
	var s: Scenario = make({"seed": 1203, "fixture": R.hall()})
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	s.step(2)
	var gun: Item = R.armed(s, ann, 3, 5)
	var belt: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	var from_event: int = s.run.noise.event_log.size()
	ann.at(s.run.tick).hold(InputRecord.HOLD_RELIGHT, 100)
	s.step(110)
	var clicks: Array[int] = []
	var levels: Array[float] = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from_event):
		if e.type == NoiseTypes.Type.RELOAD_CLICK:
			clicks.append(e.tick)
			levels.append(e.level_np)
	assert_eq(Revolver.rounds_in(gun), 6, "up to six")
	assert_eq(belt.count_of(ItemKinds.Kind.ROUNDS), 2, "three from the box")
	assert_eq(clicks.size(), 3, "a click a round")
	assert_eq(clicks[1] - clicks[0], 20, "a round per 20 held ticks")
	assert_eq(clicks[2] - clicks[1], 20)
	assert_almost_eq(levels[0], 8.0, 1e-9, "8 np")
	assert_eq(ItemKinds.stack_size(ItemKinds.Kind.ROUNDS), 12, "a box holds at most 12")


func test_hands_never_touch_it() -> void:
	var s: Scenario = make({"seed": 1204, "fixture": R.hall()})
	R.lit(s)
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	s.step(2)
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == ann.entity_id
	var belt: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	belt.slots[0] = Revolver.make(s.run)
	belt.selected = 0
	ann.at(s.run.tick).hold(InputRecord.HOLD_USE, 40)
	s.step(40)
	assert_false(s.run.revolver.is_drawn(ann.entity_id), "a Hand never draws it")
	belt.slots[0] = null
	belt.free_hand = Revolver.make(s.run)
	R.aim(s, ann)
	s.step(3)
	R.trigger(s, ann)
	s.step(6)
	assert_eq(s.run.revolver.shots.size(), 0, "nor fires it")
	belt.free_hand = null
	var gun: int = s.run.inventory.world.put(s.run, Revolver.make(s.run), Vector2(4.5, 2.5))
	ann.at(s.run.tick).face(0.0).hold(InputRecord.HOLD_INTERACT, 40)
	s.step(40)
	assert_true(s.run.inventory.world.items.has(gun), "nor picks it up")
