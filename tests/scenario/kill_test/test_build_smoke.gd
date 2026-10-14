extends "res://tests/scenario/kit/scenario_test.gd"
## QA-01's kill-test smoke on GEN-03's grey box, populated as the kill-test server populates it: four
## miners join over the kit's network; Dan walks out to a chamber and home; Bob falls beyond base camp;
## Ann lifts him and carries him to a medbay table; Cat takes the cupboard's kit and revives him.

const L = preload("res://tests/unit/mnr/lamp_world.gd")
const M = preload("res://tests/unit/rescue/medbay_world.gd")
const MAP: String = "m1_greybox"


func before_all() -> void:
	assert_true(Tuning.load_server())


func _face(s: Scenario, h: MinerHandle, to: Vector2) -> void:
	var from: Vector2 = s.run.registry.get_entity(h.entity_id).position
	h.at(s.run.tick).face(rad_to_deg((to - from).angle()))


func _tile(s: Scenario, h: MinerHandle) -> Vector2i:
	return Vector2i(s.run.registry.get_entity(h.entity_id).position.floor())


func test_four_join_walk_fall_carry_and_revive() -> void:
	var s: Scenario = make({"seed": 131, "fixture": MAP})
	FixedMapLoader.populate(s.run, MAP, true, true)
	var camp: BaseCampState = s.run.base_camp
	assert_not_null(camp, "the grey box's base camp")
	var inside: Array = Basecamp.inside_tiles(FixedMapLoader.run_seed(FixedMapLoader.manifest(MAP)),
		FixedMapLoader.blind_side(FixedMapLoader.manifest(MAP))).keys()
	inside.sort()
	var starts: Array[Vector2i] = []
	for raw: Variant in inside:
		var t: Vector2i = raw
		var last: Vector2i = starts.back() if not starts.is_empty() else Vector2i(-99, -99)
		if s.mine.native.is_walkable(t) and Vector2(t).distance_to(Vector2(last)) > 3.0:
			starts.append(t)
		if starts.size() == 4:
			break
	var ann: MinerHandle = s.add_miner("ann", starts[0])
	var bob: MinerHandle = s.add_miner("bob", starts[1])
	var cat: MinerHandle = s.add_miner("cat", starts[2])
	var dan: MinerHandle = s.add_miner("dan", starts[3])
	s.step(3)
	for h: MinerHandle in [ann, bob, cat, dan]:
		assert_true(h.is_connected_now(), "%s joined" % h.name)
	L.lit_in_hand(s, ann)
	for raw: Variant in s.run.air_doors.doors.values():
		var d: AirDoorSystem.Door = raw
		s.run.air_doors._flip(s.run, d, true)  # as GEN-03's walk: the hoard behind the door worked open
	for g: Gate in camp.gate_system.gates:
		s.run.mine.native.set_barrier(Vector2i.ZERO, g.barrier, true)  # the gates worked open (LFT-02's levers)
	# Dan walks out to the nearest chamber or dead end and home again.
	var targets: Array[Vector2i] = M1GreyboxCheck.walk_targets(s.mine, MAP)
	targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_to(Vector2(starts[3])) < Vector2(b).distance_to(Vector2(starts[3])))
	var goal: Vector2i = targets[0]
	dan.at(s.run.tick).walk_to(goal)
	var out_ok: bool = s.run_until(func(sc: Scenario) -> bool: return _tile(sc, dan) == goal, 2400)
	assert_true(out_ok, "Dan reached %s (stopped at %s, life %d)" % [goal, _tile(s, dan), M.life(s, dan.entity_id)])
	dan.at(s.run.tick).walk_to(starts[3])
	# Bob walks out with Ann beside him, and falls.
	var spot: Vector2i = goal
	var beside: Vector2i = spot
	for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if s.mine.native.is_walkable(spot + o):
			beside = spot + o
			break
	bob.at(s.run.tick).walk_to(spot)
	ann.at(s.run.tick).walk_to(beside)
	var there: bool = s.run_until(func(sc: Scenario) -> bool: return _tile(sc, bob) == spot and _tile(sc, ann) == beside, 2400)
	assert_true(there, "Bob and Ann out at %s" % spot)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UNCONSCIOUS, "Bob is down")
	# Ann lifts him and carries him home to a medbay table.
	_face(s, ann, s.run.registry.get_entity(bob.entity_id).position)
	s.step(16)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(44)
	assert_true(s.run.carry.is_carrying(ann.entity_id), "a fireman's carry")
	var table: Vector2i = camp.medbay_tables()[0]
	ann.at(s.run.tick).walk_to(M.beside(s, table))
	cat.at(s.run.tick).walk_to(M.beside(s, camp.cupboard().cupboard))
	s.run_until(func(sc: Scenario) -> bool: return _tile(sc, ann) == M.beside(sc, table), 3000)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 3)
	s.step(4)
	assert_true(s.run.falls.body_of(bob.entity_id).on_table, "set down on the medbay table")
	# Cat takes the kit and revives him.
	s.run_until(func(sc: Scenario) -> bool: return _tile(sc, cat) == M.beside(sc, camp.cupboard().cupboard), 1500)
	_face(s, cat, Vector2(camp.cupboard().cupboard) + Vector2(0.5, 0.5))
	s.step(16)
	cat.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 25)
	s.step(30)
	assert_eq(M.kits(s, cat.entity_id), 1, "the cupboard's kit")
	ann.at(s.run.tick).walk_to(starts[0])
	cat.at(s.run.tick).walk_to(M.beside(s, table))
	s.run_until(func(sc: Scenario) -> bool: return _tile(sc, cat) == M.beside(sc, table), 1500)
	_face(s, cat, Vector2(table) + Vector2(0.5, 0.5))
	s.step(16)
	cat.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
	s.step(4)
	assert_true(s.run.ring.rings.has(cat.entity_id), "the ring opens on Bob")
	var options: Array = Variants.array(Variants.dict(s.run.ring.rings.get(cat.entity_id, {})).get("options", []))
	cat.at(s.run.tick).press(ActionRecord.Kind.RING_CHOICE, options.find("revive"))
	s.step(3)
	cat.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 130)
	s.step(140)
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UPRIGHT, "Bob revived")
	s.run_until(func(sc: Scenario) -> bool: return _tile(sc, dan) == starts[3], 2400)
	assert_eq(_tile(s, dan), starts[3], "Dan home again")
	for h: MinerHandle in [ann, bob, cat, dan]:
		assert_true(h.is_connected_now(), "%s still connected" % h.name)


func test_no_draught_or_pull_is_active() -> void:
	# QA-01's build has no Draught or Pull: the hunt gate's DIR-01 and DIR-03 hooks keep their
	# defaults (never building, every Pull 0) and no Director system runs, on the populated grey box.
	var s: Scenario = make({"seed": 132, "fixture": MAP})
	FixedMapLoader.populate(s.run, MAP, true, true)
	var inside: Array = Basecamp.inside_tiles(FixedMapLoader.run_seed(FixedMapLoader.manifest(MAP)),
		FixedMapLoader.blind_side(FixedMapLoader.manifest(MAP))).keys()
	inside.sort()
	var start: Vector2i = inside[0]
	var ann: MinerHandle = s.add_miner("ann", start)
	s.step(300)
	var gate: HuntGate = s.run.creatures.gate
	assert_false(Variants.flag(gate.build_active.call()), "no Draught building")
	assert_eq(PullReader.new(gate).pull_of(ann.entity_id), 0, "no Pull")
	for system: SimSystem in s.run.stages.all_systems():
		var n: String = system.system_name().to_lower()
		assert_false(n.contains("director") or n.contains("draught") or n.contains("pull"), "no %s" % n)
