class_name Prediction
extends RefCounted
## NET-05's own-miner prediction: each client tick applies the input to the predicted state with
## MNR-01's shared step against the geometry the client holds, and keeps the state after each
## input by seq for reconciliation. Facing is drawn from the live input every frame unless the
## own block locks it. The own lamp pool follows the predicted position, its shutter and wick
## following the input's wanted state after the 0.2 s steps (lamp.shutter_time, lamp.wick_step_time).
## Nothing else is ever predicted: not creatures, other miners, flame states or any other light.

const KEEP: int = 128

var params: MinerMotion.Params = MinerMotion.Params.from_tuning()
var state: MinerMotion.State = MinerMotion.State.new()
## seq -> MinerMotion.State after that input; seq -> the input
var history: Dictionary = {}
var inputs: Dictionary = {}
var order: Array[int] = []
## From the own block: the server drives the miner (no prediction), the speed factor, the
## gait constraints.
var server_driven: bool = false
## False until the first own block places the miner; inputs before it are kept, not simulated.
var initialized: bool = false
var factor: float = 1.0
var constraints: MinerMotion.Constraints = MinerMotion.Constraints.new()
## The predicted lamp: wanted state (InputRecord.desired) and what shows after the step delay.
var lamp_desired: int = 2
var lamp_shown: int = 2
var _lamp_change_tick: int = 0
var _ticks: int = 0
var lamp_step_ticks: int = 4
## seq -> the predicted pool radius before modifiers after that input (mid-step included), to
## compare with the server's radius for the same input.
var lamp_at: Dictionary = {}
## The server's effective radius over the nominal one (guttering, blackdamp: VIS-04).
var radius_mult: float = 1.0
var _ramp_from: float = 4.0
## lamp.radius_wick_down, _normal, _wick_up, _shuttered.
var _radius: PackedFloat64Array = []


func _init() -> void:
	if Tuning.current.has_key(&"lamp.shutter_time"):
		lamp_step_ticks = roundi(Tuning.f(&"lamp.shutter_time") * Tuning.f(&"net.tick_hz"))
		_radius = PackedFloat64Array([Tuning.f(&"lamp.radius_wick_down"), Tuning.f(&"lamp.radius_normal"),
			Tuning.f(&"lamp.radius_wick_up"), Tuning.f(&"lamp.radius_shuttered")])
	_ramp_from = nominal_radius(lamp_shown)


## One client tick: apply this input (unless the server drives the miner).
func apply(seq: int, record: InputRecord, is_solid: Callable) -> void:
	_ticks += 1
	inputs[seq] = record.duplicate_record()
	order.append(seq)
	var wanted_lamp: int = record.desired & InputRecord.DESIRED_LAMP_MASK
	if wanted_lamp != lamp_desired:
		_ramp_from = _ramped_nominal()
		lamp_desired = wanted_lamp
		_lamp_change_tick = _ticks
	if lamp_shown != lamp_desired and _ticks - _lamp_change_tick >= lamp_step_ticks:
		lamp_shown = lamp_desired
	if initialized and not server_driven:
		state = MinerMotion.step(state, record, constraints, factor, is_solid, 1.0 / Tuning.f(&"net.tick_hz"), params).state
	history[seq] = state.duplicate_state()
	lamp_at[seq] = _ramped_nominal()
	while order.size() > KEEP:
		var old: int = order.pop_front()
		history.erase(old)
		inputs.erase(old)
		lamp_at.erase(old)


## The facing to draw this frame: the live input's, unless the own block locks it.
func facing_for_render(live_facing: int) -> int:
	return state.facing if constraints.facing_lock else live_facing


## The predicted own lamp: where it is, the wanted state that shows, and the pool's radius,
## growing or shrinking over the 0.2 s step and scaled by the server's modifiers.
func lamp() -> Dictionary:
	return {"position": Vector2(state.x, state.y), "shutter_closed": (lamp_shown & 1) != 0, "wick": lamp_shown >> 1,
		"radius": _ramped_nominal() * radius_mult}


## A lamp state's radius in the hand before modifiers: MNR-06's shared rule (LampRules).
func nominal_radius(desired: int) -> float:
	if _radius.is_empty():
		return 4.0
	return LampRules.hand_radius(desired)


## The server's own block gives its effective radius for the state after input `seq`.
func on_server_radius(seq: int, server_radius: float) -> void:
	if not lamp_at.has(seq):
		return
	var nominal: float = Variants.number(lamp_at[seq])
	# A nearly closed pool says little about the modifier at the wire's 1/16 tile.
	if nominal >= 1.0:
		radius_mult = server_radius / nominal


func _ramped_nominal() -> float:
	var target: float = nominal_radius(lamp_desired)
	if lamp_step_ticks <= 0:
		return target
	var t: float = clampf(float(_ticks - _lamp_change_tick) / lamp_step_ticks, 0.0, 1.0)
	return lerpf(_ramp_from, target, t)
