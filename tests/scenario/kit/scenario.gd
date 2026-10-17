extends RefCounted
## FND-09's scenario kit: the real server systems in-process from a fixed seed, miners whose
## clients connect over NET-02's in-process transport (so lanes, framing and encoding are the
## shipping code), inputs scripted tick by tick, and time that moves only through step().
## Every client's received stream is captured. Nothing reads the wall clock: the transport
## runs on a virtual clock, and session tokens come from a seeded stream.
##
##   var s: Scenario = Scenario.create({"seed": 7, "fixture": FixtureMap.from_ascii(rows)})
##   var ann: MinerHandle = s.add_miner("ann", Vector2i(2, 2))
##   ann.at(1).move(0.0, InputRecord.Gait.WALK, 10)
##   s.step(20)
##
## A step is one 50 ms tick: five 10 ms sub-steps of virtual time in which clients poll and
## links deliver, each client sends its input for the tick at the third, then the server runs
## the tick. Script tick t is the input sent just before server tick t.

const Self = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const InputScript = preload("res://tests/scenario/kit/input_script.gd")
const Capture = preload("res://tests/scenario/kit/capture.gd")
const KitLink = preload("res://tests/scenario/kit/kit_link.gd")
const KitCreature = preload("res://tests/scenario/kit/kit_creature.gd")
const Brain = preload("res://tools/bots/brain.gd")
const BotContext = preload("res://tools/bots/bot_context.gd")

const TICK_USEC: int = 50000
const SUBSTEPS: int = 5
const SEND_SUBSTEP: int = 2
const CLOCK_ORIGIN_USEC: int = 1000000
const HOST: String = "scenario"
const PORT: int = 1
## A path that never exists, so a developer's user://tuning_overrides.json cannot leak in.
const NO_OVERRIDES: String = "user://fnd09_no_overrides.json"


## Read-only views of authoritative truth. Fields owned by later tickets read null until then.
class StateView:
	extends RefCounted
	var run: RunState

	func _init(of_run: RunState) -> void:
		run = of_run

	## Position and tile from the registry; the input applied this tick. Facing, gait, state,
	## stamina, belt and lamp arrive with MNR-01 to MNR-05 and read null until then.
	func miner(handle: MinerHandle) -> Dictionary:
		var entity: SimEntity = run.registry.get_entity(handle.entity_id)
		var applied: InputBuffer.Consumed = run.input_for(handle.slot) if handle.slot >= 0 else null
		return {
			"position": entity.position if entity != null else Vector2(-1, -1),
			"tile": entity.tile() if entity != null else Vector2i(-1, -1),
			"input": applied.record if applied != null else null,
			"input_real": applied.real if applied != null else false,
			"starved": applied.starved if applied != null else false,
			"actions": applied.actions if applied != null else ([] as Array[ActionRecord]),
			"facing": null, "gait": null, "state": null, "stamina": null, "belt": null, "lamp": null,
		}

	func light_at(tile: Vector2i) -> float:
		return run.light.light_at(tile) if run.light != null else 0.0

	## VIS-03's seen set; empty until it lands.
	func seen_set(_handle: MinerHandle) -> Array:
		return []

	## Road Graph events (np, source, tick); SND-02's catalogue logs them. Empty until then.
	func road_graph_events() -> Array:
		return []

	## DIR-01's Draught intensity of a miner (0-100); -1 untracked or with the Director off.
	func intensity(handle: MinerHandle) -> float:
		return run.draught.intensity_of(handle.entity_id) if run.draught != null else -1.0

	## DIR-03's Pull of a miner (0-100); 0 untracked, -1 with the Director off.
	func pull(handle: MinerHandle) -> float:
		return run.pull.value_of(handle.entity_id) if run.pull != null else -1.0

	## The lie log and the run record (NET-08): later.
	func lie_log() -> Array:
		return []


var config: Dictionary = {}
var run: RunState
var net: ServerNet
var hub: InProcessTransport.Hub
var server_transport: InProcessTransport
## What the server received, with virtual arrival times (for link timing checks).
var server_capture: Capture
var mine: Mine = null
var fixture: FixtureMap = null
## GEN-11: a generated mine's lazy generation (cfg "generated"), synchronous so tests repeat.
var generation: Generation = null
## CRT-18: CreatureStarts.spawn's report, when a generated run asked for its creatures.
var starts: Dictionary = {}
var miners: Array[MinerHandle] = []
var recorder: InputLog
var state: StateView
## Called with (scenario) after every tick.
var on_tick: Callable = Callable()
## NET-12: (scenario) -> void after every client poll (each 10 ms of the virtual clock), for probes.
var on_poll: Callable = Callable()
var _seed: int = 0
var _replaying: bool = false
var _replay_log: InputLog = null
var _closed: bool = false


## Builds a scenario. Config keys (all optional): seed (int), fixture (FixtureMap or map name),
## mode (ServerConfig.Mode), tuning_profile (String), overrides ({key: value}), slots (int),
## creatures ({kind: bool}; CRT tickets), director (bool: the Director's systems, DIR-*), systems (extra SimSystems,
## for test stand-ins of systems that do not exist yet), generated ({pack: PackedByteArray, workers:
## int, centres: [Vector2i], plan: bool, plan_overrides: {}, creatures: bool}: a mine generated from
## that template pack round the seed, GEN-11, instead of a fixture, with run start's windows round
## base camp and each of the centres' cells (homes, creature starts); synchronous unless workers is
## above 0; with plan, GEN-08's plan (RunPlan.fix's inputs overridden by plan_overrides) and GEN-10's
## homes; with creatures, CRT-18's creature starts; with home_windows (creatures' value by default),
## the homes' windows committed at start as server_main does).
static func create(cfg: Dictionary = {}) -> Self:
	var s: Self = Self.new()
	s._build(cfg)
	return s


func _build(cfg: Dictionary) -> void:
	config = cfg
	_seed = int(Variants.number(cfg.get("seed", 1)))
	Tuning.overrides_path = NO_OVERRIDES
	var profile: String = str(cfg.get("tuning_profile", ""))
	if not Tuning.load_server(profile):
		push_error("Scenario: tuning failed to load (profile '%s')" % profile)
	var overlay: Dictionary = {}
	var overrides: Dictionary = Variants.dict(cfg.get("overrides", {}))
	for key: Variant in overrides.keys():
		overlay[key] = {"value": overrides[key]}
	var errors: Array[String] = Tuning.set_bundle(overlay)
	if not errors.is_empty():
		push_error("Scenario: bad tuning overrides: %s" % "; ".join(errors))
	if not Variants.dict(cfg.get("creatures", {})).is_empty():
		push_warning("Scenario: creatures arrive with CRT-01; the setting is ignored")
	Transport.virtual_clock_usec = CLOCK_ORIGIN_USEC
	hub = InProcessTransport.Hub.new()
	server_transport = InProcessTransport.new(hub)
	server_capture = Capture.new(server_transport)
	server_capture.listen(HOST, PORT)
	var mode: ServerConfig.Mode = int(Variants.number(cfg.get("mode", ServerConfig.Mode.FRIENDS))) as ServerConfig.Mode
	run = RunState.create(_seed, mode, false)
	net = ServerNet.new(server_capture, int(Variants.number(cfg.get("slots", 5))))
	net.sessions.token_rng = LbRng.from_seed(_seed ^ 0x70CE2)
	var raw_fixture: Variant = cfg.get("fixture", null)
	if raw_fixture is String:
		fixture = FixtureMap.named(str(raw_fixture))
	elif raw_fixture is FixtureMap:
		fixture = raw_fixture
	if fixture != null:
		mine = Mine.new()
		if fixture.load_into(mine) <= 0:
			push_error("Scenario: the fixture loaded no cells")
	var generated: Dictionary = Variants.dict(cfg.get("generated", {}))
	var layouts: LbLayouts = null
	if not generated.is_empty():
		mine = Mine.new()
		layouts = LbLayouts.new()
		var pack: PackedByteArray = generated.get("pack", PackedByteArray())
		if not layouts.load_pack(pack):
			push_error("Scenario: the generated mine's pack does not load")
		MineLayouts.configure(layouts, run.header.run_seed)
	ServerSystems.install(run, net, mine, LbHash.sub_seed(_seed, HashDomain.NET_TOKEN, PackedInt64Array([-1]), 0) | 1)
	if layouts != null:
		# GEN-08's plan and GEN-10's homes when asked ("plan": true); placement always.
		if Variants.flag(generated.get("plan", false)):
			RunPlan.fix(layouts, run, PackedByteArray(), Variants.dict(generated.get("plan_overrides", {})))
		PlacementSpawner.install(run, layouts)
		var workers: int = int(Variants.number(generated.get("workers", 0)))
		generation = Generation.new(mine, layouts, run.header.run_seed, workers <= 0, workers)
		run.add_system(generation)
		var centres: Array[Vector2i] = []
		for raw: Variant in Variants.array(generated.get("centres", [])):
			var c: Vector2i = raw
			centres.append(c)
		if Variants.flag(generated.get("home_windows", generated.get("creatures", false))):
			centres.append_array(PlacementSpawner.start_cells(layouts)) # the homes' windows, as server_main commits them
		generation.start(centres)
		# CRT-18: the creatures at their homes, when asked ("creatures": true).
		if Variants.flag(generated.get("creatures", false)):
			starts = CreatureStarts.spawn(run, layouts)
	# DIR-*: off unless asked, as on a fixed map (QA-01's kill test runs without).
	if Variants.flag(cfg.get("director", false)):
		Director.install(run)
	# NET-09: a scenario writes no save unless it asks ("saves": true), each into its own folder.
	run.header.run_uuid = "%016x" % LbHash.sub_seed(_seed, HashDomain.NET_TOKEN, PackedInt64Array([-9]), 0)
	run.saves.enabled = Variants.flag(cfg.get("saves", false)) and mode != ServerConfig.Mode.PUBLIC
	run.saves.journal.enabled = run.saves.enabled
	run.saves.save_dir = "user://kit_saves/%d" % _seed
	for raw: Variant in Variants.array(cfg.get("systems", [])):
		var system: SimSystem = raw
		run.add_system(system)
	recorder = InputLog.begin(run, fixture.spec() if fixture != null else "", "", profile)
	run.inputs.recorder = recorder
	state = StateView.new(run)


## Ends the scenario: closes every connection and hands the transport back the wall clock.
func close() -> void:
	if _closed:
		return
	_closed = true
	for h: MinerHandle in miners:
		if h.connection != null:
			h.connection.close()
	server_transport.close()
	Transport.virtual_clock_usec = -1
	Tuning.overrides_path = Tuning.OVERRIDES_PATH
	Tuning.set_bundle({})


#region Populate

## Adds a miner on a tile: its client connects and is welcomed before this returns, without
## advancing the tick. Options: facing_deg, state, lamp, belt (applied by MNR tickets), qa_token
## (FND-08: the token its client presents for the debug channel).
func add_miner(name: String, tile: Vector2i, options: Dictionary = {}) -> MinerHandle:
	var h: MinerHandle = _new_handle(name)
	h.options = options
	if not _connect(h, ""):
		push_error("Scenario: %s was not welcomed" % name)
	_place(h, tile)
	recorder.append_op(run.tick, {"op": "add_miner", "name": name, "tile": [tile.x, tile.y], "slot": h.slot})
	return h


## NET-09: a player of a resumed run comes back. Their client connects and retakes the seat the save
## held for them; no miner is placed (the run has theirs). Returns the handle (entity_id 0 if the
## save held no seat for `name`).
func rejoin(name: String) -> MinerHandle:
	var h: MinerHandle = _new_handle(name)
	if not _connect(h, ""):
		push_error("Scenario: %s was not welcomed back" % name)
	var seat: SeatTable.Seat = net.seats.seat_of(name)
	h.entity_id = seat.miner if seat != null else 0
	return h


## Adds a miner driven by a bot brain instead of a script (accelerated soaks).
func add_bot(name: String, tile: Vector2i, brain_spec: String, bot_seed: int) -> MinerHandle:
	var h: MinerHandle = add_miner(name, tile)
	h.brain = Brain.create(brain_spec, bot_seed)
	return h


## Places the run's single instance of a creature through CRT-01's spawner: the real Moth
## (CRT-03) and Tapper (CRT-08), and the stand-in KitCreature for kinds whose ticket has not landed. Returns its entity id,
## or 0 when refused or waiting for its start tile to leave every seen set and margin.
func place_creature(kind: WorldIds.EntityKind, tile: Vector2i, _creature_state: int = 0) -> int:
	if not CreatureSystem.DOMAINS.has(kind):
		push_error("Scenario.place_creature(%s): not a creature (CRT-01)" % WorldIds.EntityKind.keys()[kind])
		return 0
	# Each kind's own creature once its ticket lands; the stand-in until then.
	var c: Creature = KitCreature.new(kind)
	if kind == WorldIds.EntityKind.MOTH:
		c = Moth.new()
	elif kind == WorldIds.EntityKind.TAPPER:
		c = Tapper.new()
	elif kind == WorldIds.EntityKind.STYTHE:
		c = StytheCreature.new()
	if run.creatures.spawn(run, c, tile) != OK:
		return 0
	return c.entity_id


## The stand-in KitCreature of any creature kind, whatever has landed: for framework and
## navigation tests that drive a creature directly. Same rules as place_creature.
func place_stand_in(kind: WorldIds.EntityKind, tile: Vector2i) -> int:
	if not CreatureSystem.DOMAINS.has(kind):
		push_error("Scenario.place_stand_in(%s): not a creature (CRT-01)" % WorldIds.EntityKind.keys()[kind])
		return 0
	var c: Creature = KitCreature.new(kind)
	if run.creatures.spawn(run, c, tile) != OK:
		return 0
	return c.entity_id


## Items arrive with their tickets (MNR, GEN); until then this fails.
func place_item(item_type: String, _tile: Vector2i) -> int:
	push_error("Scenario.place_item(%s): items arrive with their tickets" % item_type)
	return 0


## Opens or shuts a fixture gate (a 4-connected group of 'G' tiles, numbered from 1).
func set_gate(id: int, open: bool) -> bool:
	if fixture == null or not fixture.gates.has(id):
		push_error("Scenario.set_gate: no gate %d" % id)
		return false
	recorder.append_op(run.tick, {"op": "set_gate", "id": id, "open": open})
	return _set_gate(id, open)


func _set_gate(id: int, open: bool) -> bool:
	var gate: Array = fixture.gates[id]
	var cell: Vector2i = gate[0]
	return mine.native.set_barrier(cell, id, open)


## Forces the next draws of a runtime stream (debug builds only; absent in release).
func script_rolls(domain: int, entity: int, values: PackedInt64Array) -> bool:
	recorder.append_op(run.tick, {"op": "script_rolls", "domain": domain, "entity": entity, "values": Array(values)})
	return run.script_rolls(domain, PackedInt64Array([entity]), values)

#endregion

#region Step

func step(n: int = 1) -> void:
	for _i: int in n:
		_step_once()


func step_seconds(seconds: float) -> void:
	step(roundi(seconds * 20.0))


## Steps until predicate(scenario) is true; fails the run (push_error) after max_ticks.
func run_until(predicate: Callable, max_ticks: int) -> bool:
	for _i: int in max_ticks:
		var done: bool = predicate.call(self)
		if done:
			return true
		_step_once()
	var finished: bool = predicate.call(self)
	if not finished:
		push_error("Scenario.run_until: not reached within %d ticks" % max_ticks)
	return finished


func _step_once() -> void:
	var t: int = run.tick
	for sub: int in SUBSTEPS:
		Transport.virtual_clock_usec += TICK_USEC / SUBSTEPS
		_poll_clients()
		# As the server's loop does between ticks: answer pings and forward voice (SND-07) on arrival.
		net.service()
		if on_poll.is_valid():
			on_poll.call(self)
		if sub == SEND_SUBSTEP:
			for h: MinerHandle in miners:
				_client_tick(h, t)
	server_capture.tick = t
	_report_link_rtt()
	if _replaying:
		for op: Variant in Variants.array(_replay_log.ops_by_tick.get(t, [])):
			_apply_op(Variants.dict(op))
	# As SimLoop does: a frozen run (Lamp Check, a knock-off) pumps only the network stage.
	if run.frozen:
		run.run_frozen_pump()
	else:
		run.run_tick()
	if on_tick.is_valid():
		on_tick.call(self)


## The in-process transport measures no round trip; ENet would report each link's, which NET-03's
## stamp sanity check reads, so the kit reports its emulated one.
func _report_link_rtt() -> void:
	for session: Sessions.Session in net.sessions.welcomed():
		for h: MinerHandle in miners:
			if h.slot == session.slot and h.link_filter != null:
				net.transport.stats(session.peer).rtt_ms = h.link_filter.rtt_ms


func _poll_clients() -> void:
	for h: MinerHandle in miners:
		if h.connection != null:
			h.capture.tick = run.tick
			h.connection.poll()
			if h.connection.state == ClientConnection.State.CONNECTED and h.connection.welcome != null:
				h.slot = h.connection.welcome.slot


## An action's tick is the frame the client shows when it is issued (NET-03), as client_main
## stamps it: what NET-06 rewinds a trigger to.
func _shown_tick(h: MinerHandle, t: int) -> int:
	if h.connection == null or not h.is_connected_now():
		return t
	return int(h.connection.shown_stamp(Transport.now_usec())[0])


func _client_tick(h: MinerHandle, t: int) -> void:
	if h.connection == null:
		return
	for raw: Variant in h.inputs.events_at(t):
		var event: Array = Variants.array(raw)
		match str(event[0]):
			"disconnect":
				h.connection.close()
			"reconnect":
				_connect(h, h.connection.session_token, false)
			"voice":
				_send_voice(h, int(Variants.number(event[1])), Brain.VOICE_BYTES_PER_TICK)
	var record: InputRecord
	if h.brain != null:
		record = _think(h, t)
	else:
		_steer_walk(h, t)
		record = h.inputs.record_at(t)
		for raw: Variant in h.inputs.actions_at(t):
			var action: Array = Variants.array(raw)
			h.connection.inputs.queue_action(int(Variants.number(action[0])) as ActionRecord.Kind,
				int(Variants.number(action[1])), _shown_tick(h, t), int(Variants.number(action[2])))
	if not h.is_connected_now():
		return
	var stamp: PackedInt64Array = h.connection.stamp_for_send(Transport.now_usec())
	var shown: int = stamp[0]
	if h.withheld > 0:
		# Dropped outright: the client still samples its tick (its sequence moves on), but that
		# input never reaches the server, not even as a later packet's redundant copy.
		h.withheld -= 1
		var seq: int = h.connection.inputs.sample(record, shown)
		h.link_filter.withheld_seqs[seq] = true
		return
	if h.connection.inputs.send_tick(h.connection, record, shown, stamp[1]) == OK:
		h.inputs_sent += 1
		if h.prediction != null:
			var view: ReceivedView = h.connection.view
			h.prediction.apply((h.connection.inputs.next_seq - 1) & 0xFFFF, record,
				HeldGeometry.query(view.geometry if view != null else {}))
		h.sent_stamps.append(PackedInt64Array([(h.connection.inputs.next_seq - 1) & 0xFFFF, shown]))


func _think(h: MinerHandle, t: int) -> InputRecord:
	var ctx: BotContext = BotContext.new()
	ctx.tick = t
	ctx.frame_tick = h.connection.last_frame_tick
	for m: Dictionary in h.capture.messages_at(t - 1):
		ctx.received.append(m)
	var record: InputRecord = h.brain.call(&"think", ctx)
	for action: Array in ctx.actions:
		h.connection.inputs.queue_action(int(Variants.number(action[0])) as ActionRecord.Kind,
			int(Variants.number(action[1])), _shown_tick(h, t), int(Variants.number(action[2])))
	for voice: Array in ctx.voice:
		_send_voice(h, int(Variants.number(voice[0])), int(Variants.number(voice[1])))
	return record


func _send_voice(h: MinerHandle, band: int, payload_bytes: int) -> void:
	if not h.is_connected_now():
		return
	# SND-07's upstream packet; the kit's audio is a dummy payload in place of Opus.
	var filler: PackedByteArray = PackedByteArray()
	filler.resize(payload_bytes)
	if h.connection.send_voice(VoicePackets.up(h.voice_frames_sent & 0xFFFF, band, 0, filler)) == OK:
		h.voice_frames_sent += 1


## walk_to's follower: each tick, toward the walkable neighbour nearest the target by GEN-01's
## path distance (ties to the first in a fixed order); stops on arrival.
func _steer_walk(h: MinerHandle, t: int) -> void:
	var walk: Array = h.inputs.walk_at(t)
	if walk.is_empty() or mine == null:
		return
	var entity: SimEntity = run.registry.get_entity(h.entity_id)
	var target: Vector2i = walk[1]
	if entity == null or entity.tile() == target:
		h.inputs.finish_walk(walk)
		return
	var next: Vector2i = next_step(mine, entity.tile(), target)
	if next == entity.tile():
		h.inputs.finish_walk(walk)
		return
	var toward: Vector2 = Vector2(next) + Vector2(0.5, 0.5) - entity.position
	h.inputs.record_at(t)
	h.inputs.held.move_dir = InputScript.direction_byte(rad_to_deg(toward.angle()))
	h.inputs.held.gait = walk[2]


## The follower's choice from a tile toward a target: a pure function of the mine.
static func next_step(of_mine: Mine, from: Vector2i, target: Vector2i) -> Vector2i:
	var best: Vector2i = from
	var best_cost: int = -1
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
			Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]:
		var n: Vector2i = from + offset
		if not of_mine.native.is_walkable(n):
			continue
		if offset.x != 0 and offset.y != 0 and (not of_mine.native.is_walkable(from + Vector2i(offset.x, 0)) \
				or not of_mine.native.is_walkable(from + Vector2i(0, offset.y))):
			continue
		var rest: Mine.PathAnswer = of_mine.path_distance(n, target)
		if rest.distance < 0.0:
			continue
		var cost: int = (1414 if offset.x != 0 and offset.y != 0 else 1000) + roundi(rest.distance * 1000.0)
		if best_cost < 0 or cost < best_cost:
			best_cost = cost
			best = n
	return best

#endregion

#region Clients

## Runs NET-05's prediction for a miner's client: every input it sends is predicted against the
## geometry its frames gave it, and every frame reconciles.
func enable_prediction(h: MinerHandle) -> void:
	h.prediction = Prediction.new()
	h.reconciler = Reconciler.new(h.prediction)
	_hook_prediction(h)


func _hook_prediction(h: MinerHandle) -> void:
	h.capture.on_decoded = func(decoded: FrameDecoder.Decoded) -> void:
		var err: float = h.reconciler.on_frame(decoded.view.own, decoded.input_ack, HeldGeometry.query(decoded.view.geometry), Transport.now_usec())
		if err >= 0.0:
			h.prediction_errors.append(err)


## Everything the server sent a miner's client.
func client(h: MinerHandle) -> Capture:
	return h.capture


func _new_handle(name: String) -> MinerHandle:
	var h: MinerHandle = MinerHandle.new()
	h.name = name
	miners.append(h)
	return h


## Connects (or reconnects) a handle's client. With `settle`, pumps the network stage until
## it is welcomed without running a tick.
func _connect(h: MinerHandle, token: String, settle: bool = true) -> bool:
	var base: InProcessTransport = InProcessTransport.new(hub)
	var link_seed: int = LbHash.sub_seed(_seed, 0, PackedInt64Array([miners.find(h)]), 0)
	var old_link: KitLink = h.link_filter
	h.link_filter = KitLink.new(base, link_seed)
	if old_link != null:
		h.link_filter.configure(old_link.rtt_ms, old_link.loss_pct)
	var old_capture: Capture = h.capture
	h.capture = Capture.new(h.link_filter)
	if old_capture != null:
		h.capture.carry_over(old_capture.messages, old_capture.index_by_tick())
	var previous: ClientConnection = h.connection
	h.connection = ClientConnection.new(h.capture)
	h.connection.identity = h.name
	h.connection.session_token = token
	h.connection.qa_token = str(h.options.get("qa_token", ""))
	# NET-09: each member keeps its copy of the saves in a folder of its own.
	h.connection.saves.root = "user://kit_client_saves/%d/%s" % [_seed, h.name]
	if previous != null:
		h.connection.inputs = previous.inputs
	if not h.connection.start(HOST, PORT):
		return false
	if not settle:
		return true
	for _i: int in 20:
		h.capture.tick = run.tick
		h.connection.poll()
		if h.connection.state == ClientConnection.State.CONNECTED:
			h.slot = h.connection.welcome.slot
			return true
		run.run_frozen_pump()
	return false


func _place(h: MinerHandle, tile: Vector2i) -> void:
	var entity: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(tile) + Vector2(0.5, 0.5))
	h.entity_id = entity.id
	var facing: int = InputScript.facing_u16(float(Variants.number(h.options.get("facing_deg", 0.0))))
	if run.movement != null and h.slot >= 0:
		run.movement.add_miner(h.slot, entity.id, entity.position, facing)
	if run.miner_state != null:
		run.miner_state.add_miner(entity.id, h.slot)
	if run.vision != null and h.slot >= 0:
		run.vision.watch(h.slot, entity.id, InputScript.facing_u16(float(Variants.number(h.options.get("facing_deg", 0.0)))))

#endregion

#region Determinism and replay

func state_hash() -> String:
	return run.state_hash()


## Runs build() twice for `ticks` ticks and compares every tick's state hash and every client's
## bytes. Returns {ok, ticks, mismatch_tick (-1), hashes, digests}.
static func assert_deterministic(build: Callable, ticks: int) -> Dictionary:
	var first: Dictionary = _trace(build, ticks)
	var second: Dictionary = _trace(build, ticks)
	var a: PackedStringArray = first["hashes"]
	var b: PackedStringArray = second["hashes"]
	var mismatch: int = -1
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			mismatch = i
			break
	var digests_equal: bool = str(first["digests"]) == str(second["digests"])
	return {"ok": mismatch < 0 and a.size() == b.size() and digests_equal, "ticks": ticks, "mismatch_tick": mismatch,
		"hashes": a, "digests": first["digests"], "digests_equal": digests_equal, "final_hash": a[a.size() - 1] if a.size() > 0 else ""}


static func _trace(build: Callable, ticks: int) -> Dictionary:
	var s: Self = build.call()
	var hashes: PackedStringArray = PackedStringArray()
	for _i: int in ticks:
		s.step()
		hashes.append(s.state_hash())
	var digests: Array[String] = []
	for h: MinerHandle in s.miners:
		digests.append(h.capture.digest() if h.capture != null else "")
	s.close()
	return {"hashes": hashes, "digests": digests}


## Writes the seed, fixture, tuning hash, setup steps and every applied input by tick.
func save_replay(path: String) -> Error:
	recorder.end_tick = run.tick
	recorder.end_hash = state_hash()
	return recorder.save(path)


## Rebuilds a run from an input log (the kit's own, or a soak server's) and steps it to its
## end. Compare state_hash() with the log's end_hash.
static func replay(path: String) -> Self:
	var log: InputLog = InputLog.load_file(path)
	if log == null:
		return null
	var cfg: Dictionary = {"seed": log.run_seed, "mode": LaunchArgs.MODES.get(log.mode, ServerConfig.Mode.FRIENDS),
		"tuning_profile": log.tuning_profile, "saves": log.saves}
	if not log.map_name.is_empty():
		cfg["fixture"] = FixtureMap.from_spec(log.map_name)
	var s: Self = create(cfg)
	if not log.tuning_hash.is_empty() and s.run.header.tuning_hash != log.tuning_hash:
		push_error("Scenario.replay: the log was recorded with different tuning (%s, now %s)" % [
			log.tuning_hash.left(12), s.run.header.tuning_hash.left(12)])
	s.run.inputs.replay = log
	s.run.inputs.recorder = null
	s._replaying = true
	s._replay_log = log
	s.step(maxi(log.end_tick, 0))
	return s


func _apply_op(op: Dictionary) -> void:
	match str(op.get("op", "")):
		"add_miner":
			var h: MinerHandle = _new_handle(str(op.get("name", "")))
			h.slot = int(Variants.number(op.get("slot", -1)))
			var tile: Array = Variants.array(op.get("tile", [0, 0]))
			_place(h, Vector2i(int(Variants.number(tile[0])), int(Variants.number(tile[1]))))
		"set_gate":
			_set_gate(int(Variants.number(op.get("id", 0))), Variants.flag(op.get("open", false)))
		"script_rolls":
			var values: PackedInt64Array = PackedInt64Array()
			for v: Variant in Variants.array(op.get("values", [])):
				values.append(int(Variants.number(v)))
			run.script_rolls(int(Variants.number(op.get("domain", 0))), PackedInt64Array([int(Variants.number(op.get("entity", 0)))]), values)
		var other:
			push_error("Scenario.replay: unknown op '%s'" % other)

#endregion
