extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-01 with CRT-09: a 25 s pin ends with the body at the wall's foot and the lamp burning at
## the wall (the Tapper's drop_lamp, wired to MNR-06 at spawn); one fell, cause PIN; the belt stays.

const H = preload("res://tests/scenario/creatures/hunt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	H.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_pin_runs_out() -> void:
	var s: Scenario = make({"seed": 71, "fixture": H.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 5))
	s.step(1)
	var lamp: GauzeLamp = L.lit_in_hand(s, ann)
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.SPANNER)))
	var t: Tapper = H.tapper(s, Vector2i(10, 4))
	t.follower.stop()
	s.step(2)
	H.talk(s, ann)
	H.until_state(s, t, &"pin", 60)
	var g: GrabHold = s.run.holds.grab_of(ann.entity_id)
	assert_not_null(g, "pinned")
	var records: Array[Dictionary] = []
	s.run.falls.fell.connect(func(r: Dictionary) -> void: records.append(r))
	var pin_ticks: int = roundi(Tuning.f(&"tapper.pin_s") * Tuning.f(&"net.tick_hz"))
	assert_eq(pin_ticks, 500, "25 s")
	s.step(pin_ticks + 20)
	assert_eq(g.outcome, GrabHold.Outcome.TIMED_OUT)
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	assert_eq(records.size(), 1)
	assert_eq(int(Variants.number(records[0]["cause"])), FallCause.Cause.PIN)
	assert_eq(s.run.registry.get_entity(ann.entity_id).tile(), Vector2i(10, 5), "the body lies at the wall's foot")
	assert_eq(lamp.state(), GauzeLamp.State.SET_DOWN_OPEN, "the lamp lies at the wall, still burning")
	assert_eq(Vector2i(floori(lamp.at.x), floori(lamp.at.y)), Vector2i(10, 5))
	assert_eq(s.run.inventory.hands_of(ann.entity_id).slots[0].kind, ItemKinds.Kind.SPANNER, "the belt stays on the body")
