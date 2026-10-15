extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-14's state machine: Lurk to Hunt on an eligible miner; Hunt to Circle when the target lights;
## Hunt to Check when they become ineligible; Check to Lurk once its places are visited; the revolver's
## threshold sends it to Retreat for 2,400 ticks with no tell, then Lurk.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(seed_value: int, ann_x: int = 20) -> H:
	var s: Scenario = make({"seed": seed_value, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 40, ann_x, 95)
	return h


func test_hunt_to_circle_when_lit() -> void:
	var h: H = _world(1461)
	assert_true(h.until_state(&"hunt", 40), "Lurk to Hunt")
	h.s.step(5)
	H.W.light(h.s, h.s.run.registry.get_entity(h.ann.entity_id).tile(), 0.5)
	h.s.step(2)
	assert_eq(h.st.state.name, &"circle", "lit: circled")
	assert_false(h.s.run.creatures.gate.is_hunting(h.st), "the hunt stood down")


func test_hunt_to_check_to_lurk() -> void:
	var h: H = _world(1462)
	assert_true(h.until_state(&"hunt", 40))
	h.s.step(10)
	h.pulls.clear()
	h.s.step(2)
	var went: Array[String] = []
	for row: Dictionary in h.st.hunt.log:
		went.append("%s:%s" % [row["to"], row["why"]])
	assert_true(went.has("check:target ineligible"), "ineligible: Check (%s)" % [went])
	assert_true(h.until_state(&"lurk", 600), "Check to Lurk once its places are visited")


func test_retreat_for_2400_ticks_without_a_tell() -> void:
	var h: H = _world(1463, 37)
	assert_true(h.until_state(&"drag", 300))
	assert_true(h.s.run.creatures.on_hit(h.s.run, h.st.entity_id, true), "the revolver's threshold")
	h.s.step(1)
	assert_eq(h.st.state.name, &"retreat")
	assert_eq(h.st.drag.victim, 0, "the victim dropped")
	var began: int = h.s.run.tick
	var tell: bool = false
	for _i: int in 2398:
		h.s.step(1)
		tell = tell or h.st.tell_active()
	assert_false(tell, "no tell while retreating")
	assert_eq(h.st.state.name, &"retreat")
	h.s.step(5)
	var ended: int = -1
	for e: Dictionary in h.s.run.creatures.log.entries:
		if StringName(str(e["type"])) == &"retreat_ended":
			ended = int(Variants.number(e["tick"]))
	assert_eq(ended - began + 1, 2400, "2,400 ticks of Retreat")
	assert_ne(h.st.state.name, &"retreat", "then Lurk (and on, to whom it may hunt)")
