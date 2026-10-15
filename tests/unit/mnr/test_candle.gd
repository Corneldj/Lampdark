extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-09's candles: lit in 20 ticks only from a burning flame within 1.5 tiles (never the electric
## lamp); radius 2.5 (core 1.5) for 6,000 burning ticks, silent; snuffed it keeps its time and
## lights again; burnt out it is gone; with the lamp hand full it is set down lit on the faced tile,
## an unheld flame the Moth cannot take; HAZ-04 hears naked_flame on every tile it enters.

const B = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _room() -> Array:
	var s: Scenario = make({"seed": 901, "fixture": B.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	s.step(1)
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.CANDLE, 3)))
	return [s, ann]


func _lamp_at(s: Scenario, at: Vector2) -> GauzeLamp:
	return s.run.lamps.create(s.run, 1.0, 0, true, LampRules.WICK_NORMAL, at)


## Holds Use for `ticks` on slot 0; returns the tick the candle was lit, or -1.
func _light(s: Scenario, ann: MinerHandle, ticks: int) -> int:
	var from: int = s.run.tick
	ann.at(from + 1).select_slot(0)
	ann.at(from + 2).hold(InputRecord.HOLD_USE, ticks)
	s.step(ticks + 6)  # the whole hold, so the next press is a fresh one
	for e: Dictionary in s.run.candles.history:
		if StringName(str(e["what"])) == &"lit" and int(Variants.number(e["tick"])) > from:
			return int(Variants.number(e["tick"]))
	return -1


func test_lit_only_from_a_flame_in_touch_range() -> void:
	var got: Array = _room()
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	assert_eq(_light(s, ann, 30), -1, "no flame near: nothing")
	# The electric lamp is no flame.
	B.put(s, ItemKinds.Kind.ELECTRIC_LAMP, Vector2i(me) + Vector2i(1, 0))
	assert_eq(_light(s, ann, 30), -1, "the electric lamp lights nothing")
	var far: GauzeLamp = _lamp_at(s, me + Vector2(0.0, 1.6))
	s.step(1)
	assert_true(far.burning())
	assert_eq(_light(s, ann, 30), -1, "a lamp 1.6 tiles off is out of touch range")
	_lamp_at(s, me + Vector2(1.4, 0.0))
	s.step(1)
	var pressed: int = s.run.tick + 2
	var lit: int = _light(s, ann, 30)
	assert_gt(lit, 0, "a lamp 1.4 tiles off lights it")
	gut.p("Use held from tick %d, lit at %d" % [pressed, lit])
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	assert_eq(lit - pressed, roundi(Tuning.f(&"items.candle_light_time") * Tuning.f(&"net.tick_hz")), "20 ticks of Use")
	assert_true(HandsAndBelt.lit_candle(h.lamp_hand), "in the empty lamp hand")
	assert_eq(h.slots[0].count, 2, "one from the stack")
	# Another candle lights from the first.
	h.lamp_hand = null
	var first: Item = s.run.inventory.world.make(ItemKinds.Kind.CANDLE, 1, {"lit": true, "burn_ticks": 500})
	s.run.inventory.world.put(s.run, first, me + Vector2(0.0, -1.2))
	for l: GauzeLamp in s.run.lamps.lamps.values():
		s.run.lamps.snuff(s.run, l, "test")
	s.step(2)
	assert_gt(_light(s, ann, 30), 0, "a burning candle lights another")


func test_burns_6000_ticks_at_2_5_silently() -> void:
	var got: Array = _room()
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var lamp: GauzeLamp = _lamp_at(s, me + Vector2(1.0, 0.0))
	s.step(1)
	var lit: int = _light(s, ann, 30)
	assert_gt(lit, 0)
	s.run.lamps.snuff(s.run, lamp, "test")
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	var candle: Item = h.lamp_hand
	var events_before: int = s.run.noise.event_log.size()
	var burning: int = 0
	var checked: bool = false
	var gaps: int = 0
	for _i: int in 6100:
		if s.run.candles.source_of(candle) != 0:
			burning += 1
			gaps += 0 if burning == _i + 1 else 1
			if not checked:
				var info: Dictionary = s.run.light.grid.source_info(s.run.candles.source_of(candle))
				assert_eq(str(info["kind"]), "candle")
				assert_almost_eq(float(Variants.number(info["radius"])), 2.5, 1e-6, "radius 2.5")
				assert_almost_eq(2.5 * Tuning.f(&"light.core_fraction"), 1.5, 1e-6, "core 1.5")
				var flags: int = int(Variants.number(info["flags"]))
				assert_eq(flags & LbLightGrid.FLAG_FLAME, LbLightGrid.FLAG_FLAME, "a flame")
				assert_eq(flags & LbLightGrid.FLAG_CARRIED, LbLightGrid.FLAG_CARRIED, "carried")
				assert_eq(flags & LbLightGrid.FLAG_NO_FLAME_STATES, 0, "every flame state")
				checked = true
		s.step(1)
	var out_at: int = -1
	for e: Dictionary in s.run.candles.history:
		if StringName(str(e["what"])) == &"burnt_out":
			out_at = int(Variants.number(e["tick"]))
	assert_eq(gaps, 0, "its light on every tick until it burnt out")
	assert_eq(out_at - lit, 6000, "6,000 burning ticks, lit to burnt out")
	assert_null(h.lamp_hand, "burnt out: gone")
	var mine: int = 0
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		if e.source_entity == ann.entity_id:
			mine += 1
	assert_eq(mine, 0, "silent")


func test_snuffed_keeps_its_time_and_lights_again() -> void:
	var got: Array = _room()
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	_lamp_at(s, me + Vector2(1.0, 0.0))
	s.step(1)
	assert_gt(_light(s, ann, 30), 0)
	s.step(100)
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	var candle: Item = h.lamp_hand
	var source: int = s.run.candles.source_of(candle)
	assert_true(FlameSnuff.snuff(s.run, source, "stythe"), "the Stythe's snuff puts a candle out")
	var left: int = int(Variants.number(candle.state["burn_ticks"]))
	s.step(5)
	assert_false(HandsAndBelt.burning_flare(candle) or Variants.flag(candle.state["lit"]), "out")
	assert_eq(int(Variants.number(candle.state["burn_ticks"])), left, "its time kept while out")
	assert_false(s.run.light.grid.has_source(source), "no light")
	# Back on the belt it keeps its own slot, then lights with what it had left.
	h.lamp_hand = null
	assert_eq(h.store(candle), 0)
	var own_slot: int = h.slots.find(candle)
	assert_ne(own_slot, 0, "not stacked with the fresh ones")
	var from: int = s.run.tick
	ann.at(from + 1).select_slot(own_slot)
	ann.at(from + 2).hold(InputRecord.HOLD_USE, 30)
	s.step(30)
	assert_eq(h.lamp_hand, candle, "relit into the lamp hand")
	assert_true(Variants.flag(candle.state["lit"]))
	assert_lte(int(Variants.number(candle.state["burn_ticks"])), left)
	assert_gt(int(Variants.number(candle.state["burn_ticks"])), left - 30, "with the time it had left")
	candle.state["burn_ticks"] = 2
	s.step(4)
	assert_null(h.lamp_hand, "burnt out: removed")
	assert_eq(s.run.candles.sources.size(), 0)


func test_set_down_lit_when_the_lamp_hand_is_full_and_naked_flames() -> void:
	var got: Array = _room()
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var flames: Array[Vector2i] = []
	s.run.lamps.naked_flame.connect(func(tile: Vector2i, cause: String) -> void:
		if cause == "lit_candle":
			flames.append(tile))
	L.lit_in_hand(s, ann)
	s.step(1)
	assert_gt(_light(s, ann, 30), 0, "lit from her own lamp")
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	assert_eq(h.lamp_hand.kind, ItemKinds.Kind.GAUZE_LAMP, "her lamp stays in hand")
	var lying: Array[Dictionary] = []
	for place: Dictionary in ItemPlaces.of_kind(s.run, ItemKinds.Kind.CANDLE):
		if StringName(str(place["where"])) == &"floor":
			lying.append(place)
	assert_eq(lying.size(), 1, "the candle set down")
	var at: Vector2 = lying[0]["position"]
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	assert_eq(Vector2i(at), Vector2i(me) + Vector2i(1, 0), "on the faced tile")
	var lit_candle: Item = lying[0]["item"]
	var source: int = s.run.candles.source_of(lit_candle)
	var flags: int = int(Variants.number(s.run.light.grid.source_info(source)["flags"]))
	assert_eq(flags & LbLightGrid.FLAG_UNHELD, LbLightGrid.FLAG_UNHELD, "an unheld flame")
	assert_eq(flags & LbLightGrid.FLAG_CANNOT_TAKE, LbLightGrid.FLAG_CANNOT_TAKE, "never taken")
	assert_eq(flames, [Vector2i(at)] as Array[Vector2i], "a naked flame where it was lit")
	# Carried, every new tile is a naked flame.
	var lamp: Item = h.lamp_hand
	h.lamp_hand = null
	s.run.inventory.world.lift(s.run, int(Variants.number(lying[0]["entity"])))
	h.lamp_hand = lit_candle
	s.run.inventory.world.put(s.run, lamp, me)
	flames.clear()
	ann.at(s.run.tick + 1).move(0.0, InputRecord.Gait.WALK, 40)
	s.step(45)
	var walked: Vector2i = s.run.registry.get_entity(ann.entity_id).tile()
	gut.p("naked flames walking: %s" % [flames])
	assert_gte(flames.size(), walked.x - Vector2i(me).x, "one for each tile entered")
	assert_eq(flames[flames.size() - 1], walked)


func test_none_while_blocked_held_or_out() -> void:
	var got: Array = _room()
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	_lamp_at(s, me + Vector2(1.0, 0.0))
	s.step(1)
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	h.free_hand = s.run.inventory.world.make(ItemKinds.Kind.REVOLVER)
	assert_eq(_light(s, ann, 30), -1, "the revolver drawn")
	h.free_hand = s.run.inventory.world.make(ItemKinds.Kind.PARAFFIN_CAN)
	assert_eq(_light(s, ann, 30), -1, "a can in the free hand")
	h.free_hand = null
	assert_true(s.run.inventory.begin_two_handed(s.run, ann.entity_id))
	assert_eq(_light(s, ann, 30), -1, "both hands full")
	s.run.inventory.end_two_handed(ann.entity_id)
	assert_gt(s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 400), 0)
	s.step(2)
	assert_eq(_light(s, ann, 30), -1, "Grabbed")
	var g: GrabHold = s.run.holds.grab_of(ann.entity_id)
	s.run.holds.end_grab(s.run, g.id, GrabHold.Outcome.RETREAT)
	s.step(2)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(2)
	assert_eq(_light(s, ann, 30), -1, "unconscious")
	assert_eq(h.count_of(ItemKinds.Kind.CANDLE), 3, "nothing spent")


func test_every_flame_state_but_the_cap() -> void:
	var got: Array = _room()
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	s.run.flame_states.firedamp_at = func(_t: Vector2i) -> bool: return true
	s.run.flame_states.blackdamp_s = func(_id: int, _t: Vector2i) -> float: return 1.0
	var candle: Item = s.run.inventory.world.make(ItemKinds.Kind.CANDLE, 1, {"lit": true, "burn_ticks": 500})
	var flare: Item = s.run.inventory.world.make(ItemKinds.Kind.FLARE, 1, {"lit": true, "burn_ticks": 100})
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	s.run.inventory.world.put(s.run, candle, me + Vector2(2.0, 0.0))
	s.run.inventory.world.put(s.run, flare, me + Vector2(4.0, 0.0))
	s.step(3)
	var cbits: int = s.run.flame_states.flags_of(s.run.candles.source_of(candle))
	assert_eq(cbits & FlameFlags.SHRINK, FlameFlags.SHRINK, "a candle shrinks in blackdamp")
	assert_eq(cbits & FlameFlags.CAP, 0, "but never shows the blue cap")
	assert_eq(s.run.flame_states.flags_of(s.run.flares.source_of(flare)), 0, "a flare shows no flame state")
