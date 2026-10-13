extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-08: who gets a flame's states. An open lamp's states show on its holder's identity record and
## in the owner's own block; a shuttered or slotted lamp still reacts, but nobody sees it and its
## owner gets only GUTTER (the sputter: dousing costs the instrument); a lamp lying or hanging shows
## its states on its own record unless shuttered.

const L = preload("res://tests/unit/mnr/lamp_world.gd")
const W = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## Ann with a lit lamp, under every cause: a stand-in Stythe's gutter, firedamp, a stirring Moth.
func _setup(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	var l: GauzeLamp = L.lit_in_hand(s, ann)
	var at: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	s.run.flame_states.causes.append(func(_run: RunState) -> Array:
		return [{"state": FlameFlags.GUTTER, "point": at, "reach": 10.0, "cause": "stythe#1"},
			{"state": FlameFlags.TREMBLE, "point": at, "reach": 20.0, "cause": "moth#1"}])
	s.run.flame_states.firedamp_at = func(_tile: Vector2i) -> bool: return true
	return [s, ann, l]


const ALL_THREE: int = FlameFlags.TREMBLE | FlameFlags.GUTTER | FlameFlags.CAP


func test_open_lamp_shows_everything() -> void:
	var parts: Array = _setup(1)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	s.step(2)
	assert_eq(s.run.flame_states.own_flags(ann.entity_id), ALL_THREE, "the owner sees every state")
	assert_eq(s.run.flame_states.entity_flags(ann.entity_id), ALL_THREE, "and so does anyone who sees her")


func test_shuttered_lamp_owner_gets_only_the_sputter() -> void:
	var parts: Array = _setup(2)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[2]
	ann.at(s.run.tick).lamp(true, LampRules.WICK_NORMAL)
	s.step(LampRules.step_ticks() + 3)
	assert_true(l.shutter_closed)
	assert_eq(s.run.flame_states.flags_of(l.source), ALL_THREE, "it still reacts")
	assert_eq(s.run.flame_states.own_flags(ann.entity_id), FlameFlags.GUTTER, "the owner: only the sputter")
	assert_eq(s.run.flame_states.entity_flags(ann.entity_id), 0, "unseen by anyone")


func test_slotted_lamp_owner_gets_only_the_sputter() -> void:
	var parts: Array = _setup(3)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[2]
	# Into a belt slot, as MNR-04's use moves it; the lamp follows (MNR-06).
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	h.slots[0] = h.lamp_hand
	h.lamp_hand = null
	s.run.inventory.changed.emit(ann.entity_id)
	s.step(3)
	assert_eq(l.place, LampRules.Place.SLOT)
	assert_eq(s.run.flame_states.own_flags(ann.entity_id), FlameFlags.GUTTER)
	assert_eq(s.run.flame_states.entity_flags(ann.entity_id), 0)


func test_lamp_lying_shows_on_its_own_record() -> void:
	var parts: Array = _setup(4)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[2]
	var tile: Vector2i = s.run.registry.get_entity(ann.entity_id).tile() + Vector2i(1, 0)
	assert_true(s.run.lamps.set_down(s.run, l, tile))
	s.step(3)
	var item_entity: int = 0
	for raw: Variant in s.run.inventory.world.items.keys():
		var it: Item = s.run.inventory.world.items[raw]
		if it.uid == l.uid:
			item_entity = int(Variants.number(raw))
	assert_ne(item_entity, 0)
	assert_eq(s.run.flame_states.entity_flags(item_entity), ALL_THREE, "the lamp's own record")
	assert_eq(s.run.flame_states.own_flags(ann.entity_id), 0, "no longer Ann's flame")
	assert_true(s.run.lamps.shutter_in_place(s.run, l, ann.entity_id))
	s.step(LampRules.step_ticks() + 3)
	assert_eq(s.run.flame_states.entity_flags(item_entity), 0, "shuttered in place: unseen")
