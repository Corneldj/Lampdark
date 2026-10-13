extends RefCounted
## RSC-02 test helpers: base camp loaded, Ann beside a medbay table with a healing kit, Bob fallen.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")


## A walkable tile beside `table`.
static func beside(s: Scenario, table: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if s.run.mine.native.is_walkable(table + d):
			return table + d
	return table


## A fallen body laid straight onto a table (as MNR-13's set-down leaves it).
static func lay(s: Scenario, body: int, table: Vector2i) -> void:
	assert(s.run.base_camp.cupboard().lay(table, body))
	var b: BodyState = s.run.falls.body_of(body)
	b.on_table = true
	b.on_floor = false
	s.run.movement.place(s.run, body, Vector2(table) + Vector2(0.5, 0.5))


## Gives a healing kit; returns the slot it went to.
static func give_kit(s: Scenario, entity: int) -> void:
	assert(s.run.inventory.give(s.run, entity, s.run.inventory.world.make(ItemKinds.Kind.HEALING_KIT)))


static func kits(s: Scenario, entity: int) -> int:
	var n: int = 0
	for item: Item in s.run.inventory.hands_of(entity).slots:
		if item != null and item.kind == ItemKinds.Kind.HEALING_KIT:
			n += item.count
	return n


static func life(s: Scenario, entity: int) -> int:
	return s.run.miner_state.life(entity)


## Starts a kit use by `user` on `target` with interact held for `hold` ticks.
static func start(s: Scenario, user: MinerHandle, target: int, mode: KitUse.Mode, hold: int) -> TimedAction:
	user.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, hold)
	s.step(1)
	var a: TimedAction = KitUse.make(s.run, s.run.revival, user.entity_id, target, mode)
	assert(s.run.inventory.start_action(s.run, a))
	return a
