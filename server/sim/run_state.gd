class_name RunState
extends RefCounted
## The server-only container for one run (NET-01): header, tick counter, entity registry,
## systems in their stages, sessions, the change feed and tick timings. Nothing here is
## ever sent to a client; the header holds the run seed (Gameplay §5.10).

## NET-07's gate (RSC-06 drives it): the true view is served only during Lamp Check, and the run
## record is discarded when it ends. MOD-03: a hosted run waits at the Pithead, seating its crew,
## until the host starts it (nothing ticks there).
enum Phase { PLAYING, LAMP_CHECK, ENDED, PITHEAD }

signal phase_changed(phase: Phase)


class Header:
	extends RefCounted
	var run_seed: int = 0
	var mode: ServerConfig.Mode = ServerConfig.Mode.FRIENDS
	var offline: bool = false
	var hash_version: int = 1
	var tuning_hash: String = ""
	## FND-08: a state-changing debug command ran (set once, never cleared; telemetry carries it).
	var debug_tainted: bool = false
	## NET-09: the run's identity for its saves (random; the scenario kit's from its seed), and the
	## fixed map it plays on (GEN-03), which a resume loads again.
	var run_uuid: String = ""
	var map_name: String = ""
	## GEN-08: a generated run's header and plan, as LbLayouts serialises it (RunPlan).
	var plan: PackedByteArray = PackedByteArray()
	## MOD-05: the generator and template set a generated mine comes from (RunPlan records them),
	## which a resume must load again; and whether this run was resumed from a save (MOD-04's cold
	## open plays only for a new run).
	var generator: String = ""
	var templates: String = ""
	var resumed: bool = false
	## MOD-03: the lobby's options, the humans seated at the start (RSC-09's "began with exactly
	## two", DIR-05's lobby kind), the staging (DIR-06's stage, "" unstaged), the draw (HAZ-07's run
	## conditions) and the rule flags {public, saved, solo_rules, hands_fill}, fixed at creation and
	## kept through every save. Never sent.
	var options: RunOptions = RunOptions.new()
	var humans_at_start: int = 0
	var staging: String = ""
	var draw: PackedStringArray = PackedStringArray()
	var rule_flags: Dictionary = {}


var header: Header = Header.new()
var phase: Phase = Phase.PLAYING
## Completed ticks. The tick being run is `tick` while systems run, then it advances.
var tick: int = 0
var feed: ChangeFeed = ChangeFeed.new()
var registry: EntityRegistry = EntityRegistry.new(feed)
var stages: StageTable = StageTable.new()
var timer: TickTimer = TickTimer.new()
## Connected sessions, filled by NET-02.
var sessions: Dictionary = {}
## NET-03's input service; systems read each slot's consumed input through input_for().
var inputs: InputService = null
## The world, when the run has one (GEN-01, VIS-02); ServerSystems sets them.
var mine: Mine = null
## GEN-13: what play changed in the mine, by cell.
var diff_log: DiffLog = null
## CRT-15: the Stythe's lair: its layout, row, trail and air.
var stythe_lair: StytheLair = null
var light: LightSystem = null
var road_graph: RoadGraphService = null
## VIS-03's seen sets, the only door to NET-04's encoder.
var vision: VisionSystem = null
## SND-02's emission point for every sound.
var noise: NoiseSystem = null
## MNR-01's miners: positions, facing, gaits, steps.
var movement: MovementSystem = null
## NET-04's per-client frames.
var replication: Replication = null
## MNR-03's life states, overlays and cues.
var miner_state: MinerStateSystem = null
## MNR-04's hands, belts, items in the world and timed actions (server-only).
var inventory: InventorySystem = null
## VIS-07's feeling and wall bumps (server-only, but for each owner's own FEEL messages).
var feel: FeelSystem = null
## MNR-05's interact ring (server-only, but for each actor's own RING messages).
var ring: RingSystem = null
## MNR-06's gauze lamps: state machines and their light (server-only).
var lamps: LampSystem = null
## MNR-08: electric hand lamps.
var electric: ElectricLamps = null
## NET-06: the body history and rewinds, the defender rule, the 'Now!' judge. Creature
## perception, pacing and illusions never read rewind (check_module_deps.sh).
var rewind: Rewind = null
var defender: DefenderRule = null
var now_judge: NowJudge = null
## CRT-01's creatures: registry, spawner, hunt gate, guards and log (server-only).
var creatures: CreatureSystem = null
## DIR-05's crew census and active-hunter cap (server-only).
var crew: CrewCensus = null
var cap: ActiveCap = null
## DIR-01's Draught (server-only); null when the Director is off (Director.install).
var draught: Draught = null
## DIR-02's relax rules: the relax provider, the illusion gate, the cooling seam, the Fan roll.
var relax: RelaxRules = null
## DIR-03's Pull (server-only); null when the Director is off.
var pull: Pull = null
## RSC-03's holds: every grab and trap (server-only).
var holds: Holds = null
## RSC-01's falls and bodies (server-only).
var falls: FallSystem = null
## LFT-01's base camp state, once base camp's cell is loaded (install it then).
var base_camp: BaseCampState = null
## MNR-13's fireman's carry.
var carry: FiremanCarry = null
## MNR-14: the stretcher and the drum gear, tubs on their rails, and the paraffin can.
var loads: LoadCarry = null
var tubs: TubRails = null
var cans: CanCarry = null
## RSC-02's medbay revival and healing-kit cure.
var revival: Revival = null
## VIS-08's flame states.
var flame_states: FlameStates = null
## SND-03's audio delivery stage.
var audio: AudioDelivery = null
## FND-08's debug channel (DebugServer), dev and QA servers only; null in release.
var debug: SimSystem = null
## GEN-15's air doors.
var air_doors: AirDoorSystem = null
## VIS-09's overhead tells (the Moth's dust, the Tapper's puffs, bursts); output only.
var tells: OverheadTells = null
## SND-04's deafened state.
var deafen: Deafen = null
## SND-07's voice forwarding (routes, direct lines, shared channels); outside the state hash.
var voice: VoiceSystem = null
## SND-09's band events (voice as noise) and the heard rule with the unheard timer.
var voice_noise: VoiceNoise = null
var heard: HeardTracker = null
var voice_facts: VoiceFacts = null
## RSC-04's Dark: windows, the dream channel, watching.
var dark: DarkSystem = null
## MNR-09: candles, flares and stones.
var candles: Candles = null
var flares: Flares = null
var stones: Stones = null
## SND-12: lamp signals and rock taps.
var lamp_signals: LampSignals = null
var rock_taps: RockTaps = null
## MNR-12: tools, parts and springing a known trap on purpose.
var tools_parts: ToolsParts = null
## MNR-10: chalk marks and the 2 s mark.
var chalk: Chalk = null
## MNR-16: the revolver, its shots and its retreat counters.
var revolver: Revolver = null
## NET-11: drops, seats held and retaken.
var drops: DropHandler = null
## MOD-08's Hired Hands: the miners a Hand drives (server-only).
var hands: HandController = null
## MOD-05: knocking off, and an absent player's miner waiting off the map.
var knock_off: KnockOff = null
var absent: AbsentMiners = null
## NET-09: snapshots, knock-off saves and the journal.
var saves: Saves = null
## RSC-09: the solo self-revive, the alone watch and the substitutions' switchboard.
var self_revive: SelfRevive = null
var alone_watch: AloneWatch = null
var lone: LoneSwitchboard = null
## LFT-04: the jobs for two (cue-and-press and shared work) and their places.
var two_miner: TwoMinerJobs = null
## LFT-03: the run's repair list and which jobs are done.
var repair: RepairListState = null
## LFT-06: the winder's paraffin tank.
var fuel: FuelTank = null
## LFT-08: the winder's paraffin engine.
var engine: WinderEngine = null
## LFT-05: the Power job at the District Substation.
var power: PowerJob = null
## LFT-09: the pit wakes, from the engine's catch until the cage leaves.
var apex: ApexController = null
## LFT-10: the cage, the signal cord and the ride.
var cage: Cage = null
## GEN-10: a generated mine's placements, spawned cell by cell, and the run-start homes.
var placed: PlacementSpawner = null
## LFT-11: the wipe, each miner's outcome and the run's end.
var outcomes: RunOutcomes = null
## RSC-06: Lamp Check at the pithead, after the run's end.
var lamp_check: LampCheck = null
## SND-11's callouts.
var callouts: CalloutSystem = null
## UI-02's close-ups: who reads which, and the board's seat.
var closeups: CloseupState = null
## LFT-14: the map table's sheet, its checks and its sync.
var sheets: SheetService = null
## NET-07's run record (server-only, outside the state hash).
var record: RunRecord = null
## SND-15's fall scream, cut and knocks.
var fall_audio: FallAudio = null
## DIR-04's depth helpers are static (Depth): which ring counts, D, the relax lengths, Level names.
## True while frozen (knock-off, host migration): only the network stage runs.
var frozen: bool = false
var _startup_errors: PackedStringArray = PackedStringArray()
## Every stream handed out, by domain and keys, so a debug build can script its next draws.
var _streams: Dictionary = {}
## NET-09: stream states from a save, for streams not handed out yet.
var _restored_streams: Dictionary = {}
var _scripted: Dictionary = {}


static func create(run_seed: int, mode: ServerConfig.Mode, offline: bool) -> RunState:
	var run: RunState = RunState.new()
	run.header.run_seed = run_seed
	run.header.mode = mode
	run.header.offline = offline or mode == ServerConfig.Mode.NIGHTSHIFT
	run.header.hash_version = LbHash.VERSION
	run.header.tuning_hash = Tuning.content_hash() if Tuning.current.entries.size() > 0 else ""
	if Tuning.current.has_key(&"net.tick_timing_window"):
		run.timer = TickTimer.new(Tuning.i(&"net.tick_timing_window"))
	return run


## RSC-06 moves the run into Lamp Check and out of it (NET-07 reads it).
func set_phase(to: Phase) -> void:
	if to == phase:
		return
	phase = to
	phase_changed.emit(to)


## Registers a system; a missing or clashing (stage, order) is a start-up error.
func add_system(system: SimSystem) -> bool:
	var error: String = stages.register(system)
	if not error.is_empty():
		_startup_errors.append(error)
		push_error("RunState: " + error)
		return false
	return true


func startup_errors() -> PackedStringArray:
	return _startup_errors


## The input consumed this tick for a slot (NET-03), or null before its first input.
func input_for(slot: int) -> InputBuffer.Consumed:
	return inputs.input_for(slot) if inputs != null else null


## A random stream for one system and entity, from the run seed (FND-06).
func stream(domain: int, keys: PackedInt64Array) -> LbRng:
	var rng: LbRng = LbRng.from_seed(LbHash.sub_seed(header.run_seed, domain, keys, 0))
	var key: String = _stream_key(domain, keys)
	_streams[key] = rng
	# NET-09: a resumed run's stream picks up where it was.
	if _restored_streams.has(key):
		rng.set_state(Variants.whole(_restored_streams[key]))
		_restored_streams.erase(key)
	if _scripted.has(key):
		var values: PackedInt64Array = _scripted[key]
		_scripted.erase(key)
		rng.call(&"script_values", values)
	return rng


## NET-09: every stream's state, by key (sealed in saves: FND-06's stream states never leave them).
## A resumed stream nobody has asked for yet keeps its saved state.
func stream_states() -> Dictionary:
	var out: Dictionary = _restored_streams.duplicate()
	for raw: Variant in _streams.keys():
		var rng: LbRng = _streams[raw]
		out[raw] = rng.get_state()
	return out


## NET-09: puts saved stream states back, now for streams that exist, later for the rest.
func restore_streams(states: Dictionary) -> void:
	for raw: Variant in states.keys():
		if _streams.has(raw):
			var rng: LbRng = _streams[raw]
			rng.set_state(Variants.whole(states[raw]))
		else:
			_restored_streams[raw] = states[raw]


## Debug builds only (FND-09, QA-02): the next draws of a stream return these raw values, then
## it resumes. A stream not yet handed out takes them when it is. Release builds lack
## LbRng.script_values, so this reports an error and changes nothing.
func script_rolls(domain: int, keys: PackedInt64Array, values: PackedInt64Array) -> bool:
	if not ClassDB.class_has_method(&"LbRng", &"script_values"):
		push_error("RunState.script_rolls: scripted rolls exist only in debug builds")
		return false
	var key: String = _stream_key(domain, keys)
	if _streams.has(key):
		var rng: LbRng = _streams[key]
		rng.call(&"script_values", values)
	else:
		_scripted[key] = values
	return true


static func _stream_key(domain: int, keys: PackedInt64Array) -> String:
	return "%d:%s" % [domain, ",".join(Array(keys).map(func(k: int) -> String: return str(k)))]


## Runs one full tick: every stage in order, each system timed.
func run_tick() -> void:
	feed.begin_tick(tick)
	var tick_start: int = TickTimer.now_usec()
	for stage: int in range(1, StageTable.STAGE_COUNT + 1):
		if stage == StageTable.Stage.LIGHT_PASS_1:
			_push_mirror()
		var stage_start: int = TickTimer.now_usec()
		for system: SimSystem in stages.systems_in(stage):
			var system_start: int = TickTimer.now_usec()
			system.tick(self)
			timer.record(TickTimer.system_key(system), TickTimer.now_usec() - system_start)
		timer.record(TickTimer.stage_key(stage), TickTimer.now_usec() - stage_start)
	timer.record(TickTimer.TICK, TickTimer.now_usec() - tick_start)
	tick += 1


## While frozen: pump only the network stage; the tick counter and every timer stand still.
func run_frozen_pump() -> void:
	for system: SimSystem in stages.systems_in(StageTable.Stage.RECEIVE):
		system.tick(self)


## The slowest stage of the last window, by p99 (for overrun logs).
func worst_stage() -> String:
	var worst: String = ""
	var worst_usec: int = -1
	for stage: int in range(1, StageTable.STAGE_COUNT + 1):
		var usec: int = timer.percentile(TickTimer.stage_key(stage), 99.0)
		if usec > worst_usec:
			worst_usec = usec
			worst = StageTable.stage_name(stage)
	return worst


## SHA-256 over the deterministic state: header, tick, registry, then every system in order.
func state_hash() -> String:
	var writer: SimStateWriter = SimStateWriter.new()
	writer.put_i64(header.run_seed)
	writer.put_i32(header.mode)
	writer.put_bool(header.offline)
	writer.put_i64(header.hash_version)
	writer.put_i64(tick)
	registry.write_state(writer)
	for system: SimSystem in stages.all_systems():
		if not system.hashed():
			continue
		writer.put_string(system.system_name())
		system.write_state(writer)
	return writer.sha256_hex()


func _push_mirror() -> void:
	if not registry.push_mirror(tick):
		push_error("RunState: the native entity mirror refused tick %d" % tick)
