extends "res://tests/scenario/kit/scenario_test.gd"
## The client's wanted lamp state follows the lamp's real one. A shutter press the server refuses (a
## pinned miner has no hands, MNR-03) or a change it makes itself (a douse, a snuff) would leave
## the wanted state apart from the lamp's, so the next press did nothing: once
## movement.lamp_resync_s has passed since the last lamp press, the router takes the lamp's state
## back from the inventory. (Found in the first playtest: after a pin, Q did nothing.)

const F = preload("res://tests/unit/mnr/input_frames.gd")
const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _inv(shut: bool, wick: int) -> Dictionary:
	return {"lamp": [ItemKinds.Kind.GAUZE_LAMP, 1], "hooked": false, "free": [0, 0], "slots": [], "lamp_shut": shut,
		"lamp_wick": wick}


func test_a_refused_press_is_taken_back_after_the_resync_time() -> void:
	var r: InputRouter = F.router()
	var open: Dictionary = _inv(false, LampRules.WICK_NORMAL)
	r.know_inventory(open)
	r.sample(F.frame(0.0))
	assert_eq(r.record.desired & InputRecord.DESIRED_LAMP_MASK, LampRules.WICK_NORMAL << 1, "open, normal wick")
	r.sample(F.frame(0.05, {"shutter": true}))
	r.sample(F.frame(0.1))
	assert_eq(r.record.desired & 1, 1, "the press wants it shut")
	var resync: float = Tuning.f(&"movement.lamp_resync_s")
	r.know_inventory(open)  # the server refused it: the lamp stays open
	r.sample(F.frame(0.05 + resync * 0.5))
	assert_eq(r.record.desired & 1, 1, "still wanted shut within the resync time (the step may be under way)")
	r.know_inventory(open)
	r.sample(F.frame(0.1 + resync))
	assert_eq(r.record.desired & 1, 0, "taken back: the lamp is open")
	r.sample(F.frame(0.2 + resync, {"shutter": true}))
	assert_eq(r.record.desired & 1, 1, "so the next press shuts it")


func test_a_douse_the_server_made_is_followed() -> void:
	var r: InputRouter = F.router()
	r.know_inventory(_inv(true, LampRules.WICK_NORMAL))
	r.sample(F.frame(5.0))
	assert_eq(r.record.desired & 1, 1, "the server shut it: followed at once, no press pending")
	r.sample(F.frame(5.05, {"shutter": true}))
	assert_eq(r.record.desired & 1, 0, "the next press opens it")


func test_the_server_refuses_while_pinned_and_the_resynced_press_then_acts() -> void:
	var s: Scenario = make({"seed": 71, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.brain = null
	ann.at(0).lamp(false, LampRules.WICK_NORMAL)
	s.step(1)
	var l: GauzeLamp = L.lit_in_hand(s, ann, LampRules.WICK_NORMAL)
	s.step(2)
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 0, 400)
	s.step(2)
	ann.at(s.run.tick).lamp(true, LampRules.WICK_NORMAL)  # Q while pinned
	s.step(10)
	assert_false(l.shutter_closed, "refused: a pinned miner has no hands")
	s.run.holds.end_grab(s.run, id, GrabHold.Outcome.BROKEN)
	s.step(2)
	# The router takes the open lamp back (the test above), then the next press shuts it.
	ann.at(s.run.tick).lamp(false, LampRules.WICK_NORMAL)
	s.step(2)
	ann.at(s.run.tick).lamp(true, LampRules.WICK_NORMAL)
	s.step(10)
	assert_true(l.shutter_closed, "after the resync, one press shuts it")
