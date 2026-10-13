extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-06: a table-driven test of the §4.4 diagram. Every transition is attempted through the API
## from every state: the diagram's are accepted and land where it says; every other is refused
## and changes nothing (a lamp that is not burning may still be carried about: its state stays).

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## transition -> (scenario, miner, lamp) -> bool: the API call.
func _calls() -> Dictionary:
	return {
		&"shutter_close": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.shutter(s.run, l, false),
		&"shutter_open": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.shutter(s.run, l, true),
		&"douse": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.douse(s.run, l, 0),
		&"hook": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.hook(s.run, l),
		&"unhook": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.unhook(s.run, l),
		&"slot": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.slot(s.run, l),
		&"unslot": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.unslot(s.run, l),
		&"set_down": func(s: Scenario, h: MinerHandle, l: GauzeLamp) -> bool:
			return s.run.lamps.set_down(s.run, l, s.run.registry.get_entity(h.entity_id).tile()),
		&"shutter_in_place": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.shutter_in_place(s.run, l, 0),
		&"pick_up": func(s: Scenario, h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.pick_up(s.run, l, h.entity_id),
		&"snuff": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.snuff(s.run, l, "test"),
		&"mark_dry": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.mark_dry(s.run, l),
		&"take_by_moth": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.take_by_moth(s.run, l, 999),
		&"hoard": func(s: Scenario, h: MinerHandle, l: GauzeLamp) -> bool:
			return s.run.lamps.hoard(s.run, l, s.run.registry.get_entity(h.entity_id).tile()),
		&"drop_snuffed": func(s: Scenario, h: MinerHandle, l: GauzeLamp) -> bool:
			return s.run.lamps.drop_snuffed(s.run, l, s.run.registry.get_entity(h.entity_id).tile()),
		&"unhoard": func(s: Scenario, h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.unhoard(s.run, l, h.entity_id),
		&"oil_added": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.oil_added(s.run, l),
		&"relight": func(s: Scenario, _h: MinerHandle, l: GauzeLamp) -> bool: return s.run.lamps.relight(s.run, l),
	}


func test_every_transition_from_every_state() -> void:
	var calls: Dictionary = _calls()
	assert_eq(calls.size(), GauzeLamp.DIAGRAM.size(), "every diagram transition has an API call")
	var run_seed: int = 1
	var checked: int = 0
	for state: int in GauzeLamp.State.values():
		for raw: Variant in calls.keys():
			var transition: StringName = raw
			run_seed += 1
			var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
			var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
			s.step(1)
			var l: GauzeLamp = L.in_state(s, ann, state)
			assert_eq(l.state(), state, "set up %s" % L.state_name(state))
			# Picking a lamp up from the hoard is the unhoard (§7.2): an ordinary pick-up, left Out.
			var as_transition: StringName = &"unhoard" if transition == &"pick_up" and state == GauzeLamp.State.HOARDED else transition
			var allowed: bool = Variants.dict(GauzeLamp.DIAGRAM[as_transition]).has(state)
			var call: Callable = calls[transition]
			var accepted: bool = call.call(s, ann, l)
			s.step(LampRules.step_ticks() + 1)
			var label: String = "%s from %s" % [transition, L.state_name(state)]
			if allowed:
				assert_true(accepted, label + ": the diagram allows it")
				assert_eq(l.state(), int(Variants.number(Variants.dict(GauzeLamp.DIAGRAM[as_transition])[state])), label + ": lands where it says")
			elif accepted:
				assert_false(l.burning() and l.state() != state, label + ": refused or no change of state")
				assert_eq(l.state(), state, label + ": only a lamp that is not burning moves, and its state stays")
			else:
				assert_eq(l.state(), state, label + ": refused, nothing changed")
			checked += 1
			s.close()
	gut.p("diagram: %d transition attempts checked" % checked)


func test_nothing_relights_by_itself() -> void:
	var s: Scenario = make({"seed": 900, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	var l: GauzeLamp = L.lit_in_hand(s, ann)
	s.run.lamps.snuff(s.run, l, "test")
	ann.at(s.run.tick).lamp(true, 1)
	ann.at(s.run.tick + 5).lamp(false, 2)
	s.step(40)
	assert_eq(l.state(), GauzeLamp.State.OUT, "shutter and wick presses never relight it")
	assert_eq(s.run.lamps.openings.size(), 0)
