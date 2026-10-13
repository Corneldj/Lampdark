extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-04: four slots; selection rides the input as state; give refuses a fifth item whole; a
## fifth item picked up swaps with the selected slot's item, which lies where the new one was.
## Property: across 10,000 random pick-up, set-down, swap, take, use, spend and cancel sequences,
## no item is duplicated or lost.

const W = preload("res://tests/unit/mnr/belt_world.gd")

const SEQUENCES: int = 10000
const OPS: int = 8
const KINDS: Array[ItemKinds.Kind] = [ItemKinds.Kind.GAUZE_LAMP, ItemKinds.Kind.ELECTRIC_LAMP, ItemKinds.Kind.CANDLE,
	ItemKinds.Kind.FLARE, ItemKinds.Kind.STONE, ItemKinds.Kind.PARAFFIN_CAN, ItemKinds.Kind.SPANNER, ItemKinds.Kind.FUSE,
	ItemKinds.Kind.ROPE_CLAMP, ItemKinds.Kind.ROUNDS, ItemKinds.Kind.NOTE]


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_selection_rides_the_input() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(2)
	assert_eq(W.belt(s, ann.entity_id).selected, 0)
	ann.at(s.run.tick).select_slot(3)
	s.step(6)
	assert_eq(W.belt(s, ann.entity_id).selected, 3)
	ann.at(s.run.tick).lamp(true, 2)
	s.step(6)
	assert_eq(W.belt(s, ann.entity_id).selected, 3, "the lamp state leaves the selection alone")


func test_fifth_item_swaps_with_the_selected() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.room()})
	W.light(s)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	s.step(1)
	var inv: InventorySystem = s.run.inventory
	var kinds: Array[ItemKinds.Kind] = [ItemKinds.Kind.SPANNER, ItemKinds.Kind.HAMMER, ItemKinds.Kind.CROWBAR, ItemKinds.Kind.MAGNETO]
	for k: ItemKinds.Kind in kinds:
		assert_true(inv.give(s.run, ann.entity_id, inv.world.make(k)))
	assert_false(inv.give(s.run, ann.entity_id, inv.world.make(ItemKinds.Kind.FLARE)), "four slots: a fifth item does not fit")
	var flare: int = W.put(s, ItemKinds.Kind.FLARE, a + Vector2i(1, 0))
	var at: Vector2 = s.run.registry.get_entity(flare).position
	ann.at(s.run.tick).select_slot(2)
	ann.at(s.run.tick + 2).face(0.0).hold(InputRecord.HOLD_INTERACT, 25)
	s.step(40)
	var b: HandsAndBelt = W.belt(s, ann.entity_id)
	assert_eq(b.slots[2].kind, ItemKinds.Kind.FLARE, "the flare takes the selected slot")
	var crowbar: Array[int] = []
	for raw: Variant in inv.world.items.keys():
		if inv.world.items[raw].kind == ItemKinds.Kind.CROWBAR:
			crowbar.append(int(Variants.number(raw)))
	assert_eq(crowbar.size(), 1, "the crowbar was set down")
	assert_eq(s.run.registry.get_entity(crowbar[0]).position, at, "where the flare lay")


func test_nothing_duplicated_or_lost() -> void:
	var s: Scenario = make({"seed": 3, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	s.step(1)
	var run: RunState = s.run
	var inv: InventorySystem = run.inventory
	var me: int = ann.entity_id
	var b: HandsAndBelt = inv.hands_of(me)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 404
	var expected: Dictionary = {}
	var failures: Array[String] = []
	for seq: int in SEQUENCES:
		for _op: int in OPS:
			match rng.randi_range(0, 7):
				0:
					var kind: ItemKinds.Kind = KINDS[rng.randi_range(0, KINDS.size() - 1)]
					if inv.world.items.size() >= 12 or (kind == ItemKinds.Kind.NOTE and b.notes.size() >= 4):
						continue
					var n: int = rng.randi_range(1, ItemKinds.stack_size(kind))
					inv.world.put(run, inv.world.make(kind, n), Vector2(a) + Vector2(rng.randf_range(0.0, 1.0), rng.randf_range(0.0, 1.0)))
					expected[kind] = int(Variants.number(expected.get(kind, 0))) + n
				1, 2:
					var ids: Array = inv.world.items.keys()
					if not ids.is_empty():
						ids.sort()
						inv._start_pick_up(run, me, int(Variants.number(ids[rng.randi_range(0, ids.size() - 1)])))
						_settle(inv, me, rng)
				3:
					b.selected = rng.randi_range(0, 3)
					inv._start_set_down(run, me, ann.slot)
					_settle(inv, me, rng)
				4:
					var out: Item = inv.take(run, me, rng.randi_range(0, 3))
					if out != null:
						inv.world.put(run, out, Vector2(a) + Vector2(0.5, 0.5))
				5:
					b.selected = rng.randi_range(0, 3)
					inv._use(run, me, ann.slot)
					_settle(inv, me, rng)
				6:
					var kind: ItemKinds.Kind = KINDS[rng.randi_range(0, KINDS.size() - 1)]
					if kind != ItemKinds.Kind.NOTE and inv.consume(run, me, kind, 1):
						expected[kind] = int(Variants.number(expected[kind])) - 1
				7:
					if inv.begin_two_handed(run, me):
						inv.end_two_handed(me)
		var problem: String = _check(run, inv, b, expected)
		if not problem.is_empty():
			failures.append("sequence %d: %s" % [seq, problem])
			break
	assert_eq(failures, [] as Array[String])
	gut.p("conservation: %d sequences, %d items in the world, %d held" % [SEQUENCES, inv.world.items.size(), b.held_items().size()])


## Completes or cancels the action just started, as the runner would (a lost target cancels).
func _settle(inv: InventorySystem, me: int, rng: RandomNumberGenerator) -> void:
	var a: TimedAction = inv.actions.get(me, null)
	if a == null:
		return
	inv.actions.erase(me)
	if rng.randi_range(0, 2) == 0:
		a.cancel(TimedAction.RELEASED)
	elif a.valid.is_valid() and not Variants.flag(a.valid.call()):
		a.cancel(TimedAction.TARGET)
	else:
		a.finish()


func _check(run: RunState, inv: InventorySystem, b: HandsAndBelt, expected: Dictionary) -> String:
	var seen: Dictionary = {}
	var totals: Dictionary = {}
	var everything: Array[Item] = b.held_items()
	for raw: Variant in inv.world.items.keys():
		if not run.registry.has(int(Variants.number(raw))):
			return "item entity %d has no registry entity" % int(Variants.number(raw))
		everything.append(inv.world.items[raw])
	for it: Item in everything:
		var key: int = it.get_instance_id()
		if seen.has(key):
			return "item %d (%s) is in two places" % [it.uid, ItemKinds.Kind.find_key(it.kind)]
		seen[key] = true
		if it.count <= 0 or it.count > ItemKinds.stack_size(it.kind):
			return "a stack of %d %s" % [it.count, ItemKinds.Kind.find_key(it.kind)]
		totals[it.kind] = int(Variants.number(totals.get(it.kind, 0))) + it.count
	for raw: Variant in expected.keys():
		if int(Variants.number(totals.get(raw, 0))) != int(Variants.number(expected[raw])):
			return "%s: %d, expected %d" % [ItemKinds.Kind.find_key(raw), int(Variants.number(totals.get(raw, 0))), int(Variants.number(expected[raw]))]
	return ""
