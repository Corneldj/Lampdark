extends RefCounted
## One miner in a scenario (FND-09): its client connection over the in-process transport, its
## link emulation, the capture of everything the server sent it, and its input script. The
## helpers forward to the script, so tests read: miner.at(5).move(90.0, InputRecord.Gait.WALK, 10).

const InputScript = preload("res://tests/scenario/kit/input_script.gd")
const Capture = preload("res://tests/scenario/kit/capture.gd")
const KitLink = preload("res://tests/scenario/kit/kit_link.gd")

var name: String = ""
var slot: int = -1
var entity_id: int = 0
## Null for a replay's miners, which have no client.
var connection: ClientConnection = null
var capture: Capture = null
var link_filter: KitLink = null
var inputs: InputScript = InputScript.new()
## The options add_miner was given (facing_deg, state, lamp, belt); MNR tickets apply them.
var options: Dictionary = {}
## A bot brain driving this miner instead of a script (accelerated soaks), and its context.
var brain: RefCounted = null
var withheld: int = 0
var inputs_sent: int = 0
## NET-05's client-side prediction, when enabled (Scenario.enable_prediction).
var prediction: Prediction = null
var reconciler: Reconciler = null
## The error measured on each frame that acknowledged a predicted input (tiles).
var prediction_errors: Array[float] = []
## [seq, shown tick] of every input packet sent, in order.
var sent_stamps: Array[PackedInt64Array] = []
var voice_frames_sent: int = 0


func at(tick: int) -> InputScript:
	return inputs.at(tick)


func move(dir_deg: float, gait: InputRecord.Gait, ticks: int) -> InputScript:
	return inputs.move(dir_deg, gait, ticks)


func face(deg: float) -> InputScript:
	return inputs.face(deg)


func press(kind: ActionRecord.Kind, arg: int = 0, aim_deg: float = 0.0) -> InputScript:
	return inputs.press(kind, arg, aim_deg)


func hold(bit: int, ticks: int) -> InputScript:
	return inputs.hold(bit, ticks)


func select_slot(belt_slot: int) -> InputScript:
	return inputs.select_slot(belt_slot)


func walk_to(tile: Vector2i, gait: InputRecord.Gait = InputRecord.Gait.WALK) -> InputScript:
	return inputs.walk_to(tile, gait)


func say(band: int, ticks: int) -> InputScript:
	return inputs.say(band, ticks)


func callout(id: int, band: int) -> InputScript:
	return inputs.callout(id, band)


## Emulated link on this client's connection, both directions (NET-12's filter when it lands).
func link(rtt_ms: int, loss_pct: float) -> void:
	link_filter.configure(rtt_ms, loss_pct)


## Sends nothing for the next `ticks` client ticks (tests the 200 ms cut-off).
func withhold_inputs(ticks: int) -> void:
	withheld = ticks


func is_connected_now() -> bool:
	return connection != null and connection.state == ClientConnection.State.CONNECTED


## Everything the server sent this client.
func client() -> Capture:
	return capture
