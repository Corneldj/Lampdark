extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-15: air doors start shut; a miner holding interact on one in touch range works it in
## mine.air_door_operate_s, silently; released early, nothing changes; only an Upright miner who is
## not a Hand, not carrying and has a free hand may; a door never shuts on an occupied doorway, the
## action waiting until it clears; the pass rule for every mover.

const W = preload("res://tests/unit/world/door_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": W.corridor()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(14, 1), {"facing_deg": 0.0})
	ann.at(0).face(0.0)
	s.step(2)
	return [s, ann]


func test_starts_shut_and_walls_like_rock() -> void:
	var w: Array = _world(1)
	var s: Scenario = w[0]
	var d: AirDoorSystem.Door = W.door(s)
	assert_not_null(d, "the barrier is an air door")
	assert_false(d.open, "shut at generation")
	assert_false(s.mine.native.is_walkable(W.DOOR), "bodies blocked")
	assert_true(s.mine.native.is_opaque(W.DOOR), "light and sight blocked")


func test_operate_in_one_second_silently() -> void:
	var w: Array = _world(2)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var need: int = roundi(Tuning.f(&"mine.air_door_operate_s") * Tuning.f(&"net.tick_hz"))
	var events_before: int = s.run.noise.event_log.size()
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, need + 10)
	var seen: Dictionary = {"opened_at": -1}
	var start: int = s.run.tick
	s.on_tick = func(sc: Scenario) -> void:
		if int(Variants.number(seen["opened_at"])) < 0 and W.door(sc).open:
			seen["opened_at"] = sc.run.tick
	s.step(need + 14)
	assert_true(W.door(s).open, "opened")
	var took: int = int(Variants.number(seen["opened_at"])) - start
	assert_almost_eq(float(took), float(need), 4.0, "after about %d ticks held (%d, input delay included)" % [need, took])
	assert_true(s.mine.native.is_walkable(W.DOOR), "its tiles are floor")
	assert_eq(s.run.noise.event_log.size(), events_before, "silently (Proposed)")
	assert_eq(s.run.air_doors.diff_log.size(), 1, "the flip is in the diff log")
	s.on_tick = Callable()
	s.step(4)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, need + 4)
	s.step(need + 8)
	assert_false(W.door(s).open, "a second hold shuts it")


func test_released_early_changes_nothing() -> void:
	var w: Array = _world(3)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var need: int = roundi(Tuning.f(&"mine.air_door_operate_s") * Tuning.f(&"net.tick_hz"))
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, need - 6)
	s.step(need + 10)
	assert_false(W.door(s).open)
	assert_eq(s.run.air_doors.diff_log.size(), 0)


func test_who_may_work_it() -> void:
	var w: Array = _world(4)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	assert_true(s.run.air_doors.may_work(s.run, ann.entity_id), "an Upright miner")
	s.run.miner_state.make_hurt(ann.entity_id, "test")
	s.step(1)
	assert_true(s.run.air_doors.may_work(s.run, ann.entity_id), "Hurt is Upright")
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == ann.entity_id
	assert_false(s.run.air_doors.may_work(s.run, ann.entity_id), "never a Hired Hand")
	s.run.crew.is_hand_driven = func(_e: int) -> bool: return false
	s.run.miner_state.fall_unconscious(ann.entity_id, "test")
	s.step(1)
	assert_false(s.run.air_doors.may_work(s.run, ann.entity_id), "never the unconscious")
	var moth: int = s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(5, 1))
	assert_false(s.run.air_doors.may_work(s.run, moth), "never a creature")


func test_never_shuts_on_an_occupied_doorway() -> void:
	var w: Array = _world(5)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var need: int = roundi(Tuning.f(&"mine.air_door_operate_s") * Tuning.f(&"net.tick_hz"))
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, need + 4)
	s.step(need + 8)
	assert_true(W.door(s).open)
	var bob: MinerHandle = s.add_miner("bob", W.DOOR)
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, need * 3)
	s.step(need + 10)
	assert_true(W.door(s).open, "Bob stands in the doorway: it waits")
	s.run.movement.place(s.run, bob.entity_id, Vector2(20.5, 1.5))
	s.step(4)
	assert_false(W.door(s).open, "the doorway clear, the waiting action shuts it")


func test_pass_rules() -> void:
	var w: Array = _world(6)
	var s: Scenario = w[0]
	var d: AirDoorSystem.Door = W.door(s)
	var moth: Dictionary = AirDoorSystem.request_pass(d, WorldIds.EntityKind.MOTH)
	assert_eq(int(Variants.number(moth["result"])), AirDoorSystem.Pass.HOLD)
	assert_almost_eq(float(Variants.number(moth["seconds"])), Tuning.f(&"moth.air_door_hold_s"), 1e-6, "the Moth: held 3 s")
	for kind: WorldIds.EntityKind in [WorldIds.EntityKind.STYTHE, WorldIds.EntityKind.BESS, WorldIds.EntityKind.MINER]:
		assert_eq(int(Variants.number(AirDoorSystem.request_pass(d, kind)["result"])), AirDoorSystem.Pass.DENY, "a wall to kind %d" % kind)
	assert_eq(int(Variants.number(AirDoorSystem.request_pass(d, WorldIds.EntityKind.TAPPER)["result"])), AirDoorSystem.Pass.ALLOW,
		"the Tapper is in the rock")
	d.open = true
	assert_eq(int(Variants.number(AirDoorSystem.request_pass(d, WorldIds.EntityKind.STYTHE)["result"])), AirDoorSystem.Pass.ALLOW, "open: anyone")
