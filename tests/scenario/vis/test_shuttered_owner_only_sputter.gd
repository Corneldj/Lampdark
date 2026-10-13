extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-08 (stream test): Ann's shuttered lamp under the Stythe's tell, a stirring Moth and firedamp
## still reacts, but her own block carries only GUTTER (the sputter) and Bob, who sees her, gets no
## flame state on her record. Opened, both get every state.

const FW = preload("res://tests/scenario/vis/flame_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_owner_gets_only_the_sputter() -> void:
	var s: Scenario = make({"seed": 61, "fixture": FW.hall(24)})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(12, 3))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(6, 3), {"facing_deg": 0.0})
	bob.at(0).face(0.0)
	ann.at(0).lamp(true, LampRules.WICK_NORMAL)
	s.step(1)
	var l: GauzeLamp = preload("res://tests/unit/mnr/lamp_world.gd").lit_in_hand(s, ann)
	s.run.lamps.shutter(s.run, l, false, "test")
	ann.at(s.run.tick).lamp(true, LampRules.WICK_NORMAL)
	s.run.light.grid.add_spot(0, Vector2i(12, 3), 0.40, 0)
	var at: Vector2 = Vector2(12.5, 3.5)
	var active: Array[bool] = [true]
	FW.stythe(s, at, active)
	s.run.flame_states.causes.append(func(_run: RunState) -> Array:
		return [{"state": FlameFlags.TREMBLE, "point": at, "reach": 20.0, "cause": "moth#1"}])
	s.run.flame_states.firedamp_at = func(_tile: Vector2i) -> bool: return true
	s.step(LampRules.step_ticks() + 6)
	assert_true(l.shutter_closed, "shuttered")
	var all_three: int = FlameFlags.TREMBLE | FlameFlags.GUTTER | FlameFlags.CAP
	assert_eq(s.run.flame_states.flags_of(l.source), all_three, "it still reacts")
	var own: Dictionary = ann.connection.view.own
	assert_eq(int(Variants.number(own["flame"])), FlameFlags.GUTTER, "Ann's own block: the sputter only")
	var seen: Array[Dictionary] = FW.near(bob.connection.view, at)
	assert_eq(seen.size(), 1, "Bob sees Ann")
	assert_eq(int(Variants.number(seen[0]["level"])), 2, "with identity")
	assert_eq(int(Variants.number(seen[0].get("flame", 0))), 0, "but no flame state: it is shuttered")
	# Opened: both read the flame.
	ann.at(s.run.tick).lamp(false, LampRules.WICK_NORMAL)
	s.step(LampRules.step_ticks() + 6)
	assert_eq(int(Variants.number(ann.connection.view.own["flame"])), all_three)
	seen = FW.near(bob.connection.view, at)
	assert_eq(int(Variants.number(seen[0].get("flame", 0))), all_three, "Bob reads her flame now")
