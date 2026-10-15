extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-09's stones: taken one a second from a rubble heap; thrown along the facing, the distance
## clamped to 2-8 tiles; a rib 4 tiles ahead stops a 6-tile throw on the last open tile; landing is
## one 14 np stone_landing event at the landing tile, with no thrower in it, after the flight at 12
## tiles/s; a set man-trap stub under it springs; none with both hands full, the revolver drawn,
## Grabbed or unconscious, and Caught miners may.

func before_all() -> void:
	assert_true(Tuning.load_server())


## A road east from 'a'; `rib_at` (tiles east of 'a', 0 for none) closes it with rock.
func _road(seed_value: int, rib_at: int = 0) -> Array:
	var rows: PackedStringArray = ["#".repeat(20), "#" + ".".repeat(18) + "#", "#..a" + ".".repeat(15) + "#",
		"#" + ".".repeat(18) + "#", "#".repeat(20)]
	if rib_at > 0:
		for y: int in range(1, 4):
			rows[y] = rows[y].substr(0, 3 + rib_at) + "#" + rows[y].substr(4 + rib_at)
	var s: Scenario = make({"seed": seed_value, "fixture": FixtureMap.from_ascii(rows)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	s.step(1)
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.STONE, 3)))
	return [s, ann]


func _throw(s: Scenario, ann: MinerHandle, tiles: float, wait: int = 20) -> Dictionary:
	var before: int = s.run.stones.throws.size()
	ann.at(s.run.tick + 1).select_slot(0)
	ann.at(s.run.tick + 2).press(ActionRecord.Kind.THROW, roundi(tiles * 100.0), 0.0)
	s.step(wait)
	return s.run.stones.throws[before] if s.run.stones.throws.size() > before else {}


func test_taken_from_rubble_one_a_second() -> void:
	var got: Array = _road(921)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	h.slots[0] = null
	var me: Vector2i = s.run.registry.get_entity(ann.entity_id).tile()
	s.run.stones.add_heap(me + Vector2i(1, 0))
	for n: int in range(1, 5):
		ann.at(s.run.tick + 1).hold(InputRecord.HOLD_INTERACT, 24)
		s.step(28)
		assert_eq(h.count_of(ItemKinds.Kind.STONE), n, "%d taken" % n)
	assert_eq(h.slots[0].count, 3, "3 a slot")
	assert_true(s.run.stones.heaps.has(me + Vector2i(1, 0)), "the heap never runs out")


func test_distance_clamps_and_the_landing() -> void:
	var got: Array = _road(922)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var events_before: int = s.run.noise.event_log.size()
	var short: Dictionary = _throw(s, ann, 0.5)
	assert_false(Variants.flag(short["refused"]))
	assert_almost_eq(float(Variants.number(short["distance"])), 2.0, 1e-6, "a short throw goes 2")
	var tile: Vector2i = short["tile"]
	assert_eq(tile, Vector2i(me + Vector2(2.0, 0.0)), "2 tiles along the facing")
	var long: Dictionary = _throw(s, ann, 20.0, 30)
	assert_almost_eq(float(Variants.number(long["distance"])), 8.0, 1e-6, "a long one 8")
	var far: Vector2i = long["tile"]
	assert_eq(far, Vector2i(me + Vector2(8.0, 0.0)))
	assert_eq(int(Variants.number(long["land_tick"])) - int(Variants.number(long["tick"])), ceili(8.0 / 12.0 * 20.0), "12 tiles/s")
	var landings: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		if e.type == NoiseTypes.Type.STONE_LANDING:
			landings.append(e)
	assert_eq(landings.size(), 2, "one event a landing")
	for e: NoiseSystem.Event in landings:
		assert_almost_eq(e.level_np, 14.0, 1e-6, "14 np")
		assert_eq(e.source_entity, 0, "no thrower in the event")
	assert_eq(landings[1].tick, int(Variants.number(long["land_tick"])), "at the landing tick")
	assert_eq(s.run.inventory.hands_of(ann.entity_id).count_of(ItemKinds.Kind.STONE), 1, "each throw spends one")


func test_a_rib_stops_it_on_the_last_open_tile() -> void:
	var got: Array = _road(923, 4)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var t: Dictionary = _throw(s, ann, 6.0)
	var stopped: Vector2i = t["tile"]
	assert_eq(stopped, Vector2i(me) + Vector2i(3, 0), "the tile before the rib")
	assert_eq(s.run.stones.landings.size(), 1)
	var landed_at: Vector2i = s.run.stones.landings[0]["tile"]
	assert_eq(landed_at, Vector2i(me) + Vector2i(3, 0))


func test_a_set_man_trap_springs_under_it() -> void:
	var got: Array = _road(924)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var me: Vector2i = s.run.registry.get_entity(ann.entity_id).tile()
	var traps: Dictionary = {me + Vector2i(5, 0): "set"}
	s.run.stones.landed.connect(func(tile: Vector2i) -> void:
		if traps.get(tile, "") == "set":
			traps[tile] = "sprung")
	_throw(s, ann, 3.0)
	assert_eq(str(traps[me + Vector2i(5, 0)]), "set", "not under a stone at 3")
	_throw(s, ann, 5.0)
	assert_eq(str(traps[me + Vector2i(5, 0)]), "sprung", "sprung by a stone at 5")


func test_restrictions() -> void:
	var got: Array = _road(925)
	var s: Scenario = got[0]
	var ann: MinerHandle = got[1]
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	h.free_hand = s.run.inventory.world.make(ItemKinds.Kind.REVOLVER)
	assert_true(Variants.flag(_throw(s, ann, 4.0)["refused"]), "the revolver drawn")
	h.free_hand = null
	assert_true(s.run.inventory.begin_two_handed(s.run, ann.entity_id))
	assert_true(Variants.flag(_throw(s, ann, 4.0)["refused"]), "both hands full")
	s.run.inventory.end_two_handed(ann.entity_id)
	assert_true(s.run.holds.catch(s.run, ann.entity_id, CaughtHold.Kind.MAN_TRAP, 77))
	s.step(2)
	assert_false(Variants.flag(_throw(s, ann, 4.0)["refused"]), "Caught: still thrown")
	s.run.holds.release_caught(s.run, ann.entity_id, CaughtHold.Outcome.FREED)
	s.step(2)
	assert_gt(s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 400), 0)
	s.step(2)
	assert_true(Variants.flag(_throw(s, ann, 4.0)["refused"]), "Grabbed")
	var g: GrabHold = s.run.holds.grab_of(ann.entity_id)
	s.run.holds.end_grab(s.run, g.id, GrabHold.Outcome.RETREAT)
	s.step(2)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(2)
	assert_true(Variants.flag(_throw(s, ann, 4.0)["refused"]), "unconscious")
	assert_eq(h.count_of(ItemKinds.Kind.STONE), 2, "only the Caught throw spent one")
