extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-02, the M1 kill test's loop: Bob is smothered on the west road; Ann lifts him, carries him
## home and sets him down beside a medbay table, where he lands at once; Cat takes the cupboard's
## kit, opens the ring on him and revives him in exactly 100 ticks. He rises Upright with an empty
## lamp hand, his belt unchanged and his voice back; the cupboard is empty; MNR-03's state change
## (the hook DIR-01 and DIR-03 restart intensity and the Pull from) fires.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const M = preload("res://tests/unit/rescue/medbay_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _face(s: Scenario, h: MinerHandle, to: Vector2) -> void:
	var from: Vector2 = s.run.registry.get_entity(h.entity_id).position
	h.at(s.run.tick).face(rad_to_deg((to - from).angle()))


func test_fall_carry_table_revive() -> void:
	var s: Scenario = make({"seed": 101, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	var out: Vector2i = west.middle() + west.outward * 8
	var ann: MinerHandle = s.add_miner("ann", out)
	var bob: MinerHandle = s.add_miner("bob", out)
	var cat: MinerHandle = s.add_miner("cat", M.beside(s, camp.cupboard().cupboard))
	s.step(1)
	L.lit_in_hand(s, ann)
	assert_true(s.run.inventory.give(s.run, bob.entity_id, s.run.inventory.world.make(ItemKinds.Kind.SPANNER)))
	var belt_before: Array = []
	for item: Item in s.run.inventory.hands_of(bob.entity_id).slots:
		belt_before.append(item.kind if item != null else 0)
	# The smother.
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(2)
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	# Ann lifts him and carries him home.
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(44)
	assert_true(s.run.carry.is_carrying(ann.entity_id))
	var table: Vector2i = camp.medbay_tables()[0]
	ann.at(s.run.tick).walk_to(M.beside(s, table))
	# Meanwhile Cat takes the cupboard's kit.
	cat.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 25)
	s.step(600)
	assert_eq(camp.cupboard().kits, 0, "the cupboard's kit taken")
	assert_eq(M.kits(s, cat.entity_id), 1)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 3)
	s.step(4)
	var b: BodyState = s.run.falls.body_of(bob.entity_id)
	assert_true(b.on_table, "set down beside the table: on it at once")
	# Ann steps away; Cat comes over, opens the ring on Bob and revives him.
	ann.at(s.run.tick).walk_to(west.middle())
	cat.at(s.run.tick).walk_to(M.beside(s, table))
	s.step(300)
	var on_table: Vector2 = Vector2(table) + Vector2(0.5, 0.5)
	_face(s, cat, on_table)
	s.step(16)  # NET-12: turning is rate-capped
	cat.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
	s.step(4)
	assert_true(s.run.ring.rings.has(cat.entity_id), "the ring opens on Bob")
	var ring: Dictionary = s.run.ring.rings[cat.entity_id]
	assert_eq(int(Variants.number(ring["target"])), bob.entity_id)
	var options: Array = Variants.array(ring["options"])
	assert_true(options.has("revive"), "Revive offered on the table")
	cat.at(s.run.tick).press(ActionRecord.Kind.RING_CHOICE, options.find("revive"))
	s.step(3)
	var changed: Array = []
	s.run.miner_state.state_changed.connect(func(entity: int, old: int, new: int, _c: String) -> void:
		if entity == bob.entity_id:
			changed.append([old, new, s.run.tick]))
	var started: Array[int] = [-1]
	var done: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		var act: TimedAction = sc.run.inventory.actions.get(cat.entity_id, null)
		if act != null and act.verb == &"kit_revive" and started[0] < 0:
			started[0] = act.started_tick
		if act == null and started[0] >= 0 and done[0] < 0:
			done[0] = sc.run.tick - 1
	cat.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 130)
	s.step(140)
	assert_gte(started[0], 0, "the revive ran")
	assert_eq(done[0] - started[0], 100, "exactly 100 ticks")
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UPRIGHT, "Upright")
	assert_null(s.run.inventory.hands_of(bob.entity_id).lamp_hand, "an empty lamp hand")
	var belt_after: Array = []
	for item: Item in s.run.inventory.hands_of(bob.entity_id).slots:
		belt_after.append(item.kind if item != null else 0)
	assert_eq(belt_after, belt_before, "the belt unchanged")
	assert_true(Variants.flag(s.run.miner_state.capabilities(bob.entity_id)["voice"]), "his voice back")
	assert_eq(M.kits(s, cat.entity_id), 0, "the kit spent")
	assert_eq(camp.cupboard().kits, 0, "the cupboard is empty")
	assert_eq(changed.size(), 1, "MNR-03's state change fires (DIR-01, DIR-03 restart from it)")
	if changed.size() == 1:
		var c: Array = changed[0]
		assert_eq([c[0], c[1]], [MinerTransitions.Life.UNCONSCIOUS, MinerTransitions.Life.UPRIGHT])
