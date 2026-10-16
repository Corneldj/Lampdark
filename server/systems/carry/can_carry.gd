class_name CanCarry
extends SimSystem
## MNR-14 (stage MINERS, after the inventory): a paraffin can in the free hand (Gameplay §4.3; it
## rides there only, never in a slot, MNR-04). It sloshes: its holder walks at most (no running)
## and every step makes noise.step_heavy_np, a walk's through MNR-01's step override and a crouched
## step (Proposed: crouching still steps every movement.step_interval, and sloshes) from here. The
## lamp hand stays free; MNR-04 already blocks other free-hand actions but feeling, levers and
## phones. Server-only; the holder's client predicts the gait from its own block.

const OWNER: StringName = &"can_carry"

## entity -> seconds of crouched movement not yet stepped
var _crouch_accum: Dictionary = {}
var _holders: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 21


func system_name() -> String:
	return "can_carry"


static func holds_can(run: RunState, entity: int) -> bool:
	if run.inventory == null or not run.inventory.hands.has(entity):
		return false
	var h: HandsAndBelt = run.inventory.hands_of(entity)
	return h.free_hand != null and h.free_hand.kind == ItemKinds.Kind.PARAFFIN_CAN


func tick(run: RunState) -> void:
	if run.movement == null:
		return
	var dt: float = 1.0 / Tuning.f(&"net.tick_hz")
	var interval: float = Tuning.f(&"movement.step_interval")
	for slot: int in run.movement.miner_slots():
		var m: MovementSystem.Miner = run.movement.miner(slot)
		var holding: bool = holds_can(run, m.entity_id)
		if holding != _holders.has(m.entity_id):
			_pace(run, slot, holding)
			if holding:
				_holders[m.entity_id] = true
			else:
				_holders.erase(m.entity_id)
				_crouch_accum.erase(m.entity_id)
		if not holding or m.state.gait != MinerMotion.CROUCH or m.state.speed <= 0.0:
			continue
		var accum: float = float(Variants.number(_crouch_accum.get(m.entity_id, 0.0))) + dt
		while accum >= interval - MinerMotion.SKIN:
			accum -= interval
			if run.noise != null:
				run.noise.emit(NoiseTypes.Type.STEP_HEAVY, Vector2i(floori(m.state.x), floori(m.state.y)), {"source": m.entity_id})
		_crouch_accum[m.entity_id] = accum


## Walk at most, on heavy steps; cleared when the can leaves the hand.
func _pace(run: RunState, slot: int, on: bool) -> void:
	if not on:
		run.movement.set_constraint(slot, OWNER, null)
		run.movement.modifiers(slot).clear(OWNER)
		return
	var c: MinerMotion.Constraints = MinerMotion.Constraints.new()
	c.run_allowed = false
	run.movement.set_constraint(slot, OWNER, c)
	run.movement.modifiers(slot).set_modifier(OWNER, 1.0, Tuning.f(&"noise.step_heavy_np"))


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = _holders.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		writer.put_i64(int(Variants.number(raw)))
		writer.put_f64(float(Variants.number(_crouch_accum.get(raw, 0.0))))
