extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-08: the electric hand lamp. On: radius 6 (core 3.6), white, no flame; off, slotted or empty:
## no light. A full battery gives exactly 7,200 ticks of light and none drains while off. Each snuff
## drains 30 s, never below empty, never putting it Out or moving it. Never a flame, never taken; a
## smothered carrier's lamp lies beside them still on. The shutter key switches it; on the belt hook
## it lights at 2.5. Its battery reaches only its holder's Check Lamp, in 5 s steps.

const C = preload("res://tests/unit/mnr/chalk_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int, on: bool = true, battery: int = -1) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": C.B.room()})
	var ann: MinerHandle = C.miner(s, "ann", Vector2i(4, 3))
	s.step(2)
	var it: Item = ElectricLamps.make(s.run, battery, on)
	s.run.inventory.hands_of(ann.entity_id).lamp_hand = it
	return [s, ann, it]


func _source(s: Scenario, it: Item) -> Dictionary:
	if not s.run.electric.sources.has(it.uid):
		return {}
	return s.run.light.grid.source_info(int(Variants.number(s.run.electric.sources[it.uid])))


func test_on_radius_six_off_slotted_or_empty_dark() -> void:
	var w: Array = _world(1101)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var it: Item = w[2]
	s.step(1)
	var info: Dictionary = _source(s, it)
	assert_false(info.is_empty(), "on: a light")
	assert_eq(float(Variants.number(info["radius"])), 6.0, "radius 6")
	assert_almost_eq(6.0 * Tuning.f(&"light.core_fraction"), 3.6, 1e-9, "core 3.6")
	assert_eq(str(info["kind"]), ElectricLamps.KIND)
	var flags: int = int(Variants.number(info["flags"]))
	assert_eq(flags & LbLightGrid.FLAG_FLAME, 0, "no flame")
	assert_ne(flags & LbLightGrid.FLAG_CANNOT_TAKE, 0, "never taken")
	assert_ne(flags & LbLightGrid.FLAG_NO_FLAME_STATES, 0, "no flame states")
	assert_ne(flags & LbLightGrid.FLAG_CARRIED, 0)
	assert_eq(int(Variants.number(info["colour"])), LbLightGrid.COLOUR_WHITE)
	s.run.electric.switch(s.run, it, false)
	s.step(1)
	assert_true(_source(s, it).is_empty(), "off: dark")
	s.run.electric.switch(s.run, it, true)
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	h.lamp_hand = null
	h.slots[0] = it
	s.step(1)
	assert_true(_source(s, it).is_empty(), "slotted: dark")
	assert_false(ElectricLamps.is_on(it), "and switched off")
	h.slots[0] = null
	h.lamp_hand = it
	it.state["battery_ticks"] = 0
	assert_false(s.run.electric.switch(s.run, it, true), "empty: it will not come on")


func test_a_full_battery_gives_exactly_7200_ticks() -> void:
	var w: Array = _world(1102, false)
	var s: Scenario = w[0]
	var it: Item = w[2]
	assert_eq(ElectricLamps.full_ticks(), 7200)
	s.step(200)
	assert_eq(ElectricLamps.battery_ticks(it), 7200, "none spent while off")
	s.run.electric.switch(s.run, it, true)
	var lit: int = 0
	for _i: int in 7300:
		s.step(1)
		if not _source(s, it).is_empty():
			lit += 1
	assert_eq(lit, 7200, "exactly 7,200 ticks of light")
	assert_false(ElectricLamps.is_on(it), "then off")
	assert_eq(ElectricLamps.battery_ticks(it), 0)


func test_a_snuff_drains_thirty_seconds_never_below_empty() -> void:
	var w: Array = _world(1103)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var it: Item = w[2]
	s.step(1)
	var source: int = int(Variants.number(s.run.electric.sources[it.uid]))
	assert_true(s.run.electric.drain_source(s.run, source, Tuning.f(&"stythe.electric_snuff_drain_s")))
	assert_eq(ElectricLamps.battery_ticks(it), 7200 - 1 - 600, "30 s gone")
	assert_true(ElectricLamps.is_on(it), "never Out")
	assert_eq(s.run.inventory.hands_of(ann.entity_id).lamp_hand, it, "never moved")
	it.state["battery_ticks"] = 100
	s.run.electric.drain(s.run, it, 30.0)
	assert_eq(ElectricLamps.battery_ticks(it), 0, "never below empty")
	assert_false(ElectricLamps.is_on(it), "empty: dark")
	assert_eq(s.run.inventory.hands_of(ann.entity_id).lamp_hand, it, "still in her hand")


func test_never_a_flame_never_taken_and_left_on_beside_a_smothered_carrier() -> void:
	var w: Array = _world(1104)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var it: Item = w[2]
	var flames: Array[String] = []
	s.run.lamps.naked_flame.connect(func(_t: Vector2i, cause: String) -> void: flames.append(cause))
	s.step(5)
	assert_true(MothPerception.cannot_take_info(_source(s, it)), "the Moth may never take it")
	assert_false(ElectricLamps.can_be_taken())
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(4)
	assert_null(s.run.inventory.hands_of(ann.entity_id).lamp_hand, "dropped")
	var place: Array[Dictionary] = ItemPlaces.of_kind(s.run, ItemKinds.Kind.ELECTRIC_LAMP)
	assert_eq(place.size(), 1)
	assert_eq(StringName(str(place[0]["where"])), &"floor", "beside her")
	assert_true(ElectricLamps.is_on(it), "still on")
	assert_ne(int(Variants.number(_source(s, it).get("flags", 0))) & LbLightGrid.FLAG_UNHELD, 0, "lighting where it lies")
	assert_eq(flames, [] as Array[String], "never a naked flame")


func test_the_shutter_key_switches_it_and_the_hook_dims_it() -> void:
	var w: Array = _world(1105, false)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var it: Item = w[2]
	ann.at(s.run.tick).lamp(true, 0)
	s.step(3)
	ann.at(s.run.tick).lamp(false, 0)
	s.step(20)
	assert_true(ElectricLamps.is_on(it), "the shutter opened: on")
	s.run.inventory.hands_of(ann.entity_id).hooked = true
	s.step(1)
	assert_eq(float(Variants.number(_source(s, it)["radius"])), Tuning.f(&"lamp.electric_hook_radius"), "on the belt hook: 2.5")
	s.run.inventory.hands_of(ann.entity_id).hooked = false
	ann.at(s.run.tick).lamp(true, 0)
	s.step(20)
	assert_false(ElectricLamps.is_on(it), "the shutter shut: off")


func test_check_lamp_shows_the_battery_to_its_holder_alone() -> void:
	var w: Array = _world(1106, false, 1234)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	assert_eq(s.run.electric.check_record(ann.entity_id), {"battery5": 13}, "1,234 ticks: 13 steps of 5 s")
	var d: Dictionary = {"lamp": [ItemKinds.Kind.ELECTRIC_LAMP, 1], "hooked": false, "chalk": true, "pocket_book": true, "free": [0, 0],
		"selected": 0, "slots": [], "lamp_check": 7, "notes": 0, "check": {"battery5": 13}}
	assert_eq(Variants.dict(InventoryWire.decode(InventoryWire.encode(d))["check"]), {"battery5": 13}, "on the owner's inventory wire")
	assert_eq(s.run.electric.check_record(4242), {}, "nobody else's")
