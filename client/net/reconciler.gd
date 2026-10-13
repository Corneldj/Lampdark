class_name Reconciler
extends RefCounted
## NET-05's reconciliation. On each frame, the server's own position for the input it acked is
## compared with the prediction for that input; on a mismatch the prediction resets to the
## server's state and re-simulates every later input against the geometry now held. The drawn
## position keeps the old one's offset, decaying to nothing over net.correction_blend_ms, or
## snaps when the jump exceeds net.correction_snap_tiles. While the own block says the server
## drives the miner, the prediction follows the server and local input moves nothing.

## The own block's position is in 1/256 tile: closer than this is a match.
const MATCH_TILES: float = 1.5 / 256.0

var prediction: Prediction
var blend_usec: float = 100000.0
var snap_tiles: float = 2.0
var offset: Vector2 = Vector2.ZERO
var _offset_from: Vector2 = Vector2.ZERO
var _offset_at: int = 0
## The last mismatch measured (tiles), for the probes.
var last_error: float = 0.0
var corrections: int = 0
var snaps: int = 0


func _init(of: Prediction) -> void:
	prediction = of
	if Tuning.current.has_key(&"net.correction_blend_ms"):
		blend_usec = Tuning.f(&"net.correction_blend_ms") * 1000.0
		snap_tiles = Tuning.f(&"net.correction_snap_tiles")


## A decoded frame: its own block and the input it acknowledges. Returns the error measured
## against the prediction (tiles), or -1 when nothing could be compared.
func on_frame(own: Dictionary, input_ack: int, is_solid: Callable, now_usec: int) -> float:
	var flags: int = int(Variants.number(own["flags"]))
	var server_pos: Vector2 = own["position"]
	var was_driven: bool = prediction.server_driven
	prediction.server_driven = (flags >> 15) & 1 == 1
	prediction.factor = float(Variants.number(own["speed_q"])) / 100.0
	var c: MinerMotion.Constraints = MinerMotion.Constraints.new()
	c.movement_off = (flags & 1) != 0
	c.run_allowed = (flags & 2) == 0
	c.walk_only = (flags & 4) != 0
	c.facing_lock = (flags & 8) != 0
	prediction.constraints = c
	if not prediction.initialized:
		# The first own block places the miner; inputs the server has not yet applied are replayed.
		prediction.initialized = true
		_replay_after(server_pos, input_ack, is_solid)
		return -1.0
	if prediction.server_driven or was_driven:
		_reset_to(server_pos)
		prediction.state.facing = int(Variants.number(own["facing"]))
		prediction.history.clear()
		return -1.0
	prediction.on_server_radius(input_ack, float(Variants.number(own.get("lamp_radius", 0.0))))
	if not prediction.history.has(input_ack):
		return -1.0
	var predicted: MinerMotion.State = prediction.history[input_ack]
	var error: float = Vector2(predicted.x - server_pos.x, predicted.y - server_pos.y).length()
	last_error = error
	if error <= MATCH_TILES:
		return error
	var before: Vector2 = draw_position(now_usec)
	var state: MinerMotion.State = predicted.duplicate_state()
	state.x = server_pos.x
	state.y = server_pos.y
	var dt: float = 1.0 / Tuning.f(&"net.tick_hz")
	var replay: bool = false
	for seq: int in prediction.order:
		if replay:
			var input: InputRecord = prediction.inputs[seq]
			state = MinerMotion.step(state, input, prediction.constraints, prediction.factor, is_solid, dt, prediction.params).state
			prediction.history[seq] = state.duplicate_state()
		elif seq == input_ack:
			replay = true
			prediction.history[seq] = state.duplicate_state()
	prediction.state = state
	corrections += 1
	var jump: Vector2 = before - Vector2(state.x, state.y)
	if jump.length() > snap_tiles:
		offset = Vector2.ZERO
		_offset_from = Vector2.ZERO
		snaps += 1
	else:
		_offset_from = jump
		_offset_at = now_usec
	return error


## Where to draw the own miner now: the prediction plus the decaying correction offset.
func draw_position(now_usec: int) -> Vector2:
	var t: float = clampf((now_usec - _offset_at) / blend_usec, 0.0, 1.0) if blend_usec > 0.0 else 1.0
	offset = _offset_from * (1.0 - t)
	return Vector2(prediction.state.x, prediction.state.y) + offset


func _replay_after(p: Vector2, input_ack: int, is_solid: Callable) -> void:
	var state: MinerMotion.State = prediction.state.duplicate_state()
	state.x = p.x
	state.y = p.y
	var dt: float = 1.0 / Tuning.f(&"net.tick_hz")
	var after: bool = not prediction.history.has(input_ack)
	for seq: int in prediction.order:
		if after:
			var input: InputRecord = prediction.inputs[seq]
			state = MinerMotion.step(state, input, prediction.constraints, prediction.factor, is_solid, dt, prediction.params).state
		elif seq == input_ack:
			after = true
		prediction.history[seq] = state.duplicate_state()
	prediction.state = state


func _reset_to(p: Vector2) -> void:
	prediction.state.x = p.x
	prediction.state.y = p.y
	offset = Vector2.ZERO
	_offset_from = Vector2.ZERO
