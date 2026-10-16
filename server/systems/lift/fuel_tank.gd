class_name FuelTank
extends SimSystem
## LFT-06 (stage WORLD): the winder's paraffin tank, filled at GEN-02's tank_filler (Gameplay §3.3,
## §3.6, §10.7). Paraffin is one store: a can is one tank unit (lift.tank_unit_fills lamp fills),
## and a part-used can pours by its fills, so every lamp fill taken from a can is a quarter unit
## the engine never gets. The level is kept in burn ticks (one tank unit is lift.engine_s_per_can
## of running), so LFT-08's burn is exact; the capacity is the repair list's cans.
##
## A pour is lift.fuel_pour_s of held interact at the filler, standing still, with a can in the free
## hand: it moves what fits, up to the brim, and the can keeps the rest; a full tank or a dry can
## is refused, and released early, moved or felled, nothing moves. Hired Hands never pour. Fuel is
## done (LFT-03's mark_done) the first time the tank is full, and stays done; it can be topped up
## at any time after, running or not. Pouring is silent (Proposed).
##
## The tank shows its level only on a sight glass (Proposed): a FIXTURE entity at the filler whose
## identity record (FixtureKinds.tank_glass) carries a mark per can and the paraffin's line, seen
## only lit to 0.30. The level never reaches a client as a number. Server-only otherwise.

signal filled_first_time()
signal emptied()

var level_ticks: int = 0
var done: bool = false
## The filler's tile centre, (-1, -1) until base camp is known.
var filler: Vector2 = Vector2(-1, -1)
## The sight glass's FIXTURE entity, 0 until made.
var glass: int = 0
## Every pour: {tick, miner, fills, ticks}; every refusal: {tick, miner, why}.
var pours: Array[Dictionary] = []
var refused: Array[Dictionary] = []
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 36


func system_name() -> String:
	return "fuel_tank"


func bind(run: RunState) -> void:
	_run = run
	if run.inventory != null:
		run.inventory.targets.providers.append(_targets)


#region Units

## Burn ticks in one tank unit (a can).
static func unit_ticks() -> int:
	return roundi(Tuning.f(&"lift.engine_s_per_can") * Tuning.f(&"net.tick_hz"))


## Burn ticks in one lamp fill.
static func fill_ticks() -> int:
	return unit_ticks() / Tuning.i(&"lift.tank_unit_fills")


## The list's cans in burn ticks (0 before the list is drawn).
func capacity_ticks(run: RunState) -> int:
	var list: RepairList = run.repair.list if run != null and run.repair != null else null
	return list.cans_required * unit_ticks() if list != null else 0


func is_empty() -> bool:
	return level_ticks <= 0


func is_full(run: RunState) -> bool:
	var cap: int = capacity_ticks(run)
	return cap > 0 and level_ticks >= cap


## LFT-08's Start need: Fuel done and something in the tank.
func is_fuelled() -> bool:
	return done and not is_empty()

#endregion


#region Pouring

## Why `miner` may not pour now ("" when they may): no list, a Hand, no can, a dry can, a full tank.
func why_not_pour(run: RunState, miner: int) -> String:
	if capacity_ticks(run) <= 0:
		return "no list"
	if ToolsParts.is_hand(run, miner):
		return "a Hand"
	var can: Item = run.inventory.hands_of(miner).free_hand if run.inventory != null else null
	if can == null or can.kind != ItemKinds.Kind.PARAFFIN_CAN:
		return "no can"
	if LampOil.oil_in(can) <= 0.0:
		return "a dry can"
	if is_full(run):
		return "full"
	return ""


## The pour: lift.fuel_pour_s of held interact in touch range of the filler, standing still, the
## same can in the free hand throughout (Proposed: the same time however full the can is).
func pour_action(run: RunState, miner: int) -> TimedAction:
	var hands: HandsAndBelt = run.inventory.hands_of(miner)
	var can: Item = hands.free_hand
	var a: TimedAction = TimedAction.make(miner, &"pour_fuel", Tuning.f(&"lift.fuel_pour_s"), InputRecord.HOLD_INTERACT)
	a.needs_still = true
	a.target_point = filler
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool: return hands.free_hand == can and why_not_pour(run, miner).is_empty()
	a.effect = func() -> void: pour(run, miner, can)
	return a


## Moves a can's paraffin into the tank, up to the brim; the can keeps the rest. Returns the fills
## moved (0 when the tank is full or the can dry, changing nothing).
func pour(run: RunState, miner: int, can: Item) -> float:
	var free: int = capacity_ticks(run) - level_ticks
	var in_can: float = LampOil.oil_in(can)
	var moved: int = mini(free, roundi(in_can * fill_ticks()))
	if moved <= 0:
		return 0.0
	var fills: float = float(moved) / fill_ticks()
	var left: float = in_can - fills
	can.state["fills"] = left if left > 1e-6 else 0.0
	level_ticks += moved
	pours.append({"tick": run.tick, "miner": miner, "fills": fills, "ticks": moved})
	Log.info("fuel tank: %.2f fills poured, %d of %d ticks" % [fills, level_ticks, capacity_ticks(run)])
	if not done and is_full(run):
		done = true
		filled_first_time.emit()
		if run.repair != null:
			run.repair.mark_done(run, &"fuel")
	return fills


## LFT-08's burn: takes up to `n` ticks of running; returns how many it had.
func consume_ticks(n: int) -> int:
	var taken: int = clampi(n, 0, level_ticks)
	level_ticks -= taken
	if taken > 0 and level_ticks == 0:
		emptied.emit()
	return taken

#endregion


func tick(run: RunState) -> void:
	_run = run
	_place(run)
	if run.movement == null or run.inventory == null or filler.x < 0.0:
		return
	for slot: int in run.movement.miner_slots():
		var c: InputBuffer.Consumed = run.input_for(slot)
		var miner: int = run.movement.miner(slot).entity_id
		if c == null or run.inventory.actions.has(miner) or run.inventory.is_partner(miner) \
				or not run.inventory.is_fresh(miner, c.record.holds, InputRecord.HOLD_INTERACT):
			continue
		var target: Dictionary = run.inventory.targets.pick(run, miner, slot, run.inventory.world)
		if StringName(str(target.get("kind", ""))) != &"tank_filler":
			continue
		run.inventory.mark_spent(miner, InputRecord.HOLD_INTERACT)
		var why: String = why_not_pour(run, miner)
		if not why.is_empty():
			refused.append({"tick": run.tick, "miner": miner, "why": why})
			continue
		run.inventory.start_action(run, pour_action(run, miner))


## The filler and its sight glass, once base camp is known.
func _place(run: RunState) -> void:
	if filler.x >= 0.0 or run.base_camp == null:
		return
	var anchors: Array[Dictionary] = Basecamp.fixture(run.base_camp.seed_value, "tank_filler", run.base_camp.side)
	if anchors.is_empty():
		return
	var tile: Vector2i = anchors[0]["position"]
	filler = Vector2(tile) + Vector2(0.5, 0.5)
	if glass == 0 or not run.registry.has(glass):
		glass = run.registry.create(WorldIds.EntityKind.FIXTURE, filler).id


## The glass's identity bits: a mark per can of capacity and the paraffin's line in whole fills.
func glass_bits(run: RunState) -> int:
	var fills: int = level_ticks / fill_ticks()
	return FixtureKinds.tank_glass(capacity_ticks(run) / unit_ticks(), fills)


## MNR-04's interaction targets: the filler in touch range.
func _targets(_run_state: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	if filler.x < 0.0 or at.distance_to(filler) > reach + 1e-9:
		return []
	return [{"kind": &"tank_filler", "id": glass, "point": filler}]


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(level_ticks)
	writer.put_bool(done)
	writer.put_i64(pours.size())


## NET-09: the level and the done latch with every snapshot and knock-off save.
func save_state() -> Dictionary:
	return {"level_ticks": level_ticks, "done": done, "glass": glass}


func load_state(run: RunState, state: Dictionary) -> void:
	level_ticks = int(Variants.number(state.get("level_ticks", 0)))
	done = Variants.flag(state.get("done", false))
	glass = int(Variants.number(state.get("glass", 0)))
	if glass != 0 and not run.registry.has(glass):
		glass = 0
