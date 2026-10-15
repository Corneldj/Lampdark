extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-09's flares: struck in 10 ticks with one 16 np event; radius 14 for exactly 160 ticks, held in
## the free hand; no flame states and beyond the Stythe's snuff; its 0.60 reaches 4.8 tiles; let go
## early and nothing is spent; dropped burning when its holder falls or is grabbed, burning its full
## 8 s; none with the revolver drawn, both hands full or unconscious.

const B = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## A long dark road, Ann at its west end facing east with a flare in slot 0.
func _road(seed_value: int) -> Array:
	var rows: PackedStringArray = ["#".repeat(30), "#" + ".".repeat(28) + "#", "#..a" + ".".repeat(25) + "#",
		"#" + ".".repeat(28) + "#", "#".repeat(30)]
	var s: Scenario = make({"seed": seed_value, "fixture": FixtureMap.from_ascii(rows)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	s.step(1)
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.FLARE, 1)))
	return [s, ann]


## Holds Use on slot 0 for `ticks`, then waits; returns the strike tick or -1.
func _strike(s: Scenario, ann: MinerHandle, ticks: int, wait: int = 6) -> int:
	var from: int = s.run.tick
	ann.at(from + 1).select_slot(0)
	ann.at(from + 2).hold(InputRecord.HOLD_USE, ticks)
	s.step(ticks + wait)
	for e: Dictionary in s.run.flares.history:
		if StringName(str(e["what"])) == &"lit" and int(Variants.number(e["tick"])) > from:
			return int(Variants.number(e["tick"]))
	return -1


func _strikes(s: Scenario, from_index: int) -> Array[NoiseSystem.Event]:
	var out: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from_index):
		if e.type == NoiseTypes.Type.FLARE_STRIKE:
			out.append(e)
	return out


func test_struck_burns_160_ticks_at_14() -> void:
	var got: Array = _road(911)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var events_before: int = s.run.noise.event_log.size()
	var pressed: int = s.run.tick + 2
	var lit: int = _strike(s, ann, 14, 0)
	assert_eq(lit - pressed, 10, "struck in 10 ticks")
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	var flare: Item = h.free_hand
	assert_true(HandsAndBelt.burning_flare(flare), "held in the free hand")
	assert_null(h.slots[0], "the slot is spent")
	assert_true(s.run.inventory.free_hand_blocked(ann.entity_id, &"pick_up"), "it blocks the free hand")
	var strikes: Array[NoiseSystem.Event] = _strikes(s, events_before)
	assert_eq(strikes.size(), 1, "one strike event")
	assert_almost_eq(strikes[0].level_np, 16.0, 1e-6, "16 np")
	assert_eq(strikes[0].source_entity, ann.entity_id, "at the striker")
	var source: int = s.run.flares.source_of(flare)
	var info: Dictionary = s.run.light.grid.source_info(source)
	assert_eq(str(info["kind"]), "flare")
	assert_almost_eq(float(Variants.number(info["radius"])), 14.0, 1e-6, "radius 14")
	var flags: int = int(Variants.number(info["flags"]))
	assert_eq(flags & LbLightGrid.FLAG_NO_FLAME_STATES, LbLightGrid.FLAG_NO_FLAME_STATES, "no flame states")
	assert_eq(flags & LbLightGrid.FLAG_BEYOND_SNUFF, LbLightGrid.FLAG_BEYOND_SNUFF, "beyond snuff")
	assert_eq(flags & LbLightGrid.FLAG_FLAME, LbLightGrid.FLAG_FLAME, "an open flame")
	assert_false(FlameSnuff.snuff(s.run, source, "stythe"), "the Stythe's snuff is refused")
	assert_true(HandsAndBelt.burning_flare(flare), "still burning")
	# 0.60 out to 4.8 tiles, not beyond (the road is otherwise dark).
	s.step(1)
	var me: Vector2i = s.run.registry.get_entity(ann.entity_id).tile()
	assert_gte(s.run.light.grid.value_from(me + Vector2i(4, 0), PackedInt64Array([ann.entity_id])), 600, "0.60 at 4 tiles (thousandths)")
	assert_lt(s.run.light.grid.value_from(me + Vector2i(5, 0), PackedInt64Array([ann.entity_id])), 600, "below 0.60 at 5 (beyond 4.8)")
	var gaps: int = 0
	var seen: int = 0
	for i: int in 200:
		if s.run.flares.source_of(flare) != 0:
			seen += 1
			gaps += 0 if seen == i + 1 else 1
		s.step(1)
	assert_eq(gaps, 0, "its light on every tick until it burnt out")
	var out_at: int = -1
	for e: Dictionary in s.run.flares.history:
		if StringName(str(e["what"])) == &"burnt_out":
			out_at = int(Variants.number(e["tick"]))
	assert_eq(out_at - lit, 160, "exactly 160 ticks")
	assert_null(h.free_hand, "then gone")
	assert_eq(s.run.flares.sources.size(), 0)


func test_let_go_early_spends_nothing() -> void:
	var got: Array = _road(912)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var events_before: int = s.run.noise.event_log.size()
	assert_eq(_strike(s, ann, 6), -1, "6 ticks of Use: not struck")
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	assert_eq(h.slots[0].kind, ItemKinds.Kind.FLARE, "still on the belt")
	assert_null(h.free_hand)
	assert_eq(_strikes(s, events_before).size(), 0, "no strike")


func test_dropped_burning_on_a_fall_and_a_grab() -> void:
	for how: String in ["fell", "grabbed"]:
		var got: Array = _road(913 if how == "fell" else 914)
		var s: Scenario = got[0]
		var ann: MinerHandle = got[1]
		var lit: int = _strike(s, ann, 12)
		assert_gt(lit, 0)
		var flare: Item = s.run.inventory.hands_of(ann.entity_id).free_hand
		if how == "fell":
			assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
		else:
			assert_gt(s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 400), 0)
		s.step(2)  # dropped in the falls stage; the light follows on the next tick
		assert_null(s.run.inventory.hands_of(ann.entity_id).free_hand, "%s: out of her hand" % how)
		var lying: Array[Dictionary] = ItemPlaces.of_kind(s.run, ItemKinds.Kind.FLARE)
		assert_eq(lying.size(), 1)
		assert_eq(StringName(str(lying[0]["where"])), &"floor", "%s: on the floor" % how)
		var at: Vector2 = lying[0]["position"]
		assert_eq(Vector2i(at), s.run.registry.get_entity(ann.entity_id).tile(), "where she is")
		assert_true(HandsAndBelt.burning_flare(flare), "still burning")
		var flags: int = int(Variants.number(s.run.light.grid.source_info(s.run.flares.source_of(flare))["flags"]))
		assert_eq(flags & LbLightGrid.FLAG_UNHELD, LbLightGrid.FLAG_UNHELD, "%s: unheld" % how)
		s.step(200)
		var out_at: int = -1
		for e: Dictionary in s.run.flares.history:
			if StringName(str(e["what"])) == &"burnt_out":
				out_at = int(Variants.number(e["tick"]))
		assert_eq(out_at - lit, 160, "%s: its full 8 s" % how)


func test_blocked_by_the_revolver_both_hands_and_being_out() -> void:
	var got: Array = _road(915)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	h.free_hand = s.run.inventory.world.make(ItemKinds.Kind.REVOLVER)
	assert_eq(_strike(s, ann, 14), -1, "the revolver drawn")
	h.free_hand = null
	assert_true(s.run.inventory.begin_two_handed(s.run, ann.entity_id))
	assert_eq(_strike(s, ann, 14), -1, "both hands full")
	s.run.inventory.end_two_handed(ann.entity_id)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(2)
	assert_eq(_strike(s, ann, 14), -1, "unconscious")
	assert_eq(h.slots[0].kind, ItemKinds.Kind.FLARE, "never spent")
