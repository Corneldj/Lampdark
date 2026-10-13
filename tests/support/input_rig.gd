extends RefCounted
## NET-03's scenario rig: one server and one client over the in-process transport, both behind
## a deterministic lossy link, on a virtual clock of 10 ms steps (five per server tick). The
## client sends one input per tick, between server ticks.

const LossyLink = preload("res://tests/support/lossy_link.gd")
const STEPS_PER_TICK: int = 5

var hub: InProcessTransport.Hub = InProcessTransport.Hub.new()
var server_link: LossyLink
var client_link: LossyLink
var run: RunState
var net: ServerNet
var connection: ClientConnection
var step_count: int = 0
## Called with (rig) after every server tick.
var on_tick: Callable = Callable()
## Returns the InputRecord to send this tick, or null to send nothing (inputs cut).
var make_input: Callable = Callable()


func _init(seed_value: int, extra_systems: Array[SimSystem] = []) -> void:
	server_link = LossyLink.new(InProcessTransport.new(hub), seed_value)
	server_link.listen("server", 1)
	run = RunState.create(seed_value, ServerConfig.Mode.FRIENDS, false)
	net = ServerNet.new(server_link)
	ServerSystems.install(run, net)
	for system: SimSystem in extra_systems:
		run.add_system(system)
	client_link = LossyLink.new(InProcessTransport.new(hub), seed_value ^ 0x5A5A)
	connection = ClientConnection.new(client_link)
	connection.identity = "rig"
	connection.start("server", 1)


## One-way delay, loss and duplication on the unreliable lanes, both directions.
func set_link(delay_ms: int, loss_ppm: int, duplicate_ppm: int = 0) -> void:
	for link: LossyLink in [server_link, client_link]:
		link.delay_steps = maxi(delay_ms / 10 - 1, 0)
		link.loss_ppm = loss_ppm
		link.duplicate_ppm = duplicate_ppm


func step() -> void:
	server_link.advance()
	client_link.advance()
	connection.poll()
	var phase: int = step_count % STEPS_PER_TICK
	if phase == 2 and connection.state == ClientConnection.State.CONNECTED and make_input.is_valid():
		var record: Variant = make_input.call()
		if record is InputRecord:
			var input: InputRecord = record
			connection.inputs.send_tick(connection, input, maxi(connection.last_frame_tick, 0))
	if phase == 0:
		run.run_tick()
		if on_tick.is_valid():
			on_tick.call(self)
	step_count += 1


func ticks(count: int) -> void:
	for _i: int in count * STEPS_PER_TICK:
		step()


func connect_and_settle() -> bool:
	for _i: int in 200:
		step()
		if connection.state == ClientConnection.State.CONNECTED and connection.frames_received > 2:
			return true
	return false


## The input consumed this tick for the rig's client.
func consumed() -> InputBuffer.Consumed:
	return run.input_for(connection.welcome.slot) if connection.welcome != null else null


func buffer() -> InputBuffer:
	return run.inputs.buffer_for(connection.welcome.slot)
