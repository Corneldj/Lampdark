extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-02: revive works on either table; the revived miner rises Upright on a free tile beside it,
## belt unchanged, lamp hand empty, voice back, and the table is free again. A body on the floor
## beside a full table is offered no Revive. In Night Shift a kit only cures.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const M = preload("res://tests/unit/rescue/medbay_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _revive_on(table_index: int, run_seed: int) -> void:
	var s: Scenario = make({"seed": run_seed, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var table: Vector2i = camp.medbay_tables()[table_index]
	var spot: Vector2i = M.beside(s, table)
	var ann: MinerHandle = s.add_miner("ann", spot)
	var bob: MinerHandle = s.add_miner("bob", spot)
	s.step(1)
	M.give_kit(s, ann.entity_id)
	assert_true(s.run.inventory.give(s.run, bob.entity_id, s.run.inventory.world.make(ItemKinds.Kind.SPANNER)))
	var belt_before: Array = []
	for item: Item in s.run.inventory.hands_of(bob.entity_id).slots:
		belt_before.append(item.kind if item != null else 0)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	M.lay(s, bob.entity_id, table)
	s.step(1)
	var revived: Array = []
	s.run.revival.revived.connect(func(m: int, by: int, _t: int) -> void: revived.append([m, by]))
	M.start(s, ann, bob.entity_id, KitUse.Mode.REVIVE, 110)
	s.step(105)
	assert_eq(revived, [[bob.entity_id, ann.entity_id]], "table %d" % table_index)
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UPRIGHT, "Upright")
	assert_null(s.run.inventory.hands_of(bob.entity_id).lamp_hand, "no lamp")
	var belt_after: Array = []
	for item: Item in s.run.inventory.hands_of(bob.entity_id).slots:
		belt_after.append(item.kind if item != null else 0)
	assert_eq(belt_after, belt_before, "belt unchanged")
	assert_true(Variants.flag(s.run.miner_state.capabilities(bob.entity_id)["voice"]), "voice back")
	assert_null(s.run.falls.body_of(bob.entity_id), "no longer a body")
	assert_eq(int(Variants.number(camp.medbay.bodies[table])), 0, "the table is free")
	var at: Vector2i = s.run.registry.get_entity(bob.entity_id).tile()
	assert_ne(at, table, "standing beside the table")
	assert_lte(Vector2(at).distance_to(Vector2(table)), 1.5)
	assert_true(s.run.mine.native.is_walkable(at))


func test_first_table() -> void:
	_revive_on(0, 1)


func test_second_table() -> void:
	_revive_on(1, 2)


func test_floor_beside_a_full_table() -> void:
	var s: Scenario = make({"seed": 3, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var table: Vector2i = camp.medbay_tables()[0]
	var spot: Vector2i = M.beside(s, table)
	var ann: MinerHandle = s.add_miner("ann", spot)
	var bob: MinerHandle = s.add_miner("bob", spot)
	s.step(1)
	M.give_kit(s, ann.entity_id)
	for t: Vector2i in camp.medbay_tables():
		assert_true(camp.medbay.lay(t, 900 + t.x))
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	assert_false(s.run.ring.registry.offered(s.run, ann.entity_id, bob.entity_id).has("revive"))
	assert_false(s.run.revival.may_revive(s.run, ann.entity_id, bob.entity_id))


func test_night_shift_only_cures() -> void:
	var s: Scenario = make({"seed": 4, "fixture": C.scenario_fixture(), "mode": ServerConfig.Mode.NIGHTSHIFT})
	var camp: BaseCampState = C.load_camp(s)
	var table: Vector2i = camp.medbay_tables()[0]
	var spot: Vector2i = M.beside(s, table)
	var ann: MinerHandle = s.add_miner("ann", spot)
	var bob: MinerHandle = s.add_miner("bob", spot)
	s.step(1)
	M.give_kit(s, ann.entity_id)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	M.lay(s, bob.entity_id, table)
	s.step(1)
	var offered: Array[String] = s.run.ring.registry.offered(s.run, ann.entity_id, bob.entity_id)
	assert_false(offered.has("revive"), "Night Shift: no revive")
	assert_true(offered.has("cure"))


func test_cupboard_kit() -> void:
	var s: Scenario = make({"seed": 5, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var ann: MinerHandle = s.add_miner("ann", M.beside(s, camp.cupboard().cupboard))
	s.step(1)
	assert_eq(camp.cupboard().kits, 1)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(32)
	assert_eq(camp.cupboard().kits, 0, "taken")
	assert_eq(M.kits(s, ann.entity_id), 1, "into her belt")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(32)
	assert_eq(M.kits(s, ann.entity_id), 1, "the cupboard is empty")
