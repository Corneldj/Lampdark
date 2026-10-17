class_name Snapshot
extends RefCounted
## NET-09 (Gameplay §13.11, GDD §15.10): a run's state as save sections, and a resume from them.
##
## Sections: "run" (the header with the seed and mode, the tick and phase, every random stream's
## state, the seats), "registry" (every entity but items, which GEN-13's log keeps, and a Tapper's
## arm), "state" (each system's save_state(), by name), "diff_log" (GEN-13's, with the map table and
## the Pocket Books, compacted at each snapshot) and "windows" (NET-07's fall and death windows).
##
## A resume restores the registry, the log (replaying every loaded cell), then each system in stage
## order, the seats held for their players, and lets journaled falls and deaths after the snapshot
## stand (Journal.apply_after). Lamps and flames adopt their items again; transient state (actions,
## wind-ups, a creature's hunt) starts afresh, each creature calm where it stood (Proposed). A
## snapshot waits for a tick with no grab under way (Proposed: a drag in flight cannot be resumed).
## Server-only.

const SECTION_RUN: String = "run"
const SECTION_REGISTRY: String = "registry"
const SECTION_STATE: String = "state"
const SECTION_DIFF_LOG: String = "diff_log"
const SECTION_WINDOWS: String = "windows"
## Entities a resume makes again from elsewhere (items: the diff log; a Tapper's arm: its hunt).
const NOT_KEPT: Array[WorldIds.EntityKind] = [WorldIds.EntityKind.ITEM, WorldIds.EntityKind.TAPPER_ARM]


## Whether a snapshot may be taken now (no grab under way).
static func may_capture(run: RunState) -> bool:
	if run.holds == null:
		return true
	for raw: Variant in run.holds.grabs.values():
		var g: GrabHold = raw
		if g.is_live():
			return false
	return true


static func capture(run: RunState, net: ServerNet) -> Dictionary:
	var seats: Dictionary = {}
	if net != null:
		for raw: Variant in net.seats.seats.keys():
			var s: SeatTable.Seat = net.seats.seats[raw]
			var miner: int = s.miner
			if run.movement != null and run.movement.miner(s.slot) != null:
				miner = run.movement.miner(s.slot).entity_id
			seats[raw] = {"slot": s.slot, "miner": miner, "state": s.state, "token": s.token}
	var head: Dictionary = {"run_seed": run.header.run_seed, "mode": run.header.mode, "offline": run.header.offline,
		"run_uuid": run.header.run_uuid, "map_name": run.header.map_name, "tick": run.tick, "phase": run.phase,
		"streams": run.stream_states(), "seats": seats, "plan": run.header.plan,
		# MOD-03: the run's setup, fixed at creation, and each place's seated miner.
		"options": run.header.options.to_dict(), "humans_at_start": run.header.humans_at_start, "staging": run.header.staging,
		"draw": run.header.draw, "rule_flags": run.header.rule_flags, "crew": net.crew.to_dict() if net != null else {}}
	var state: Dictionary = {}
	for sys: SimSystem in run.stages.all_systems():
		var d: Dictionary = sys.save_state()
		if not d.is_empty():
			state[sys.system_name()] = d
	var out: Dictionary = {SECTION_RUN: var_to_bytes(head), SECTION_REGISTRY: registry_bytes(run), SECTION_STATE: var_to_bytes(state)}
	if run.diff_log != null:
		run.diff_log.compact(run)
		out[SECTION_DIFF_LOG] = run.diff_log.serialise(run)
	if run.record != null:
		out[SECTION_WINDOWS] = var_to_bytes(run.record.export_windows())
	return out


## The registry as EntityRegistry.read_state takes it, without the entities kept elsewhere.
static func registry_bytes(run: RunState) -> PackedByteArray:
	var w: SimStateWriter = SimStateWriter.new()
	var kept: Array[int] = []
	for id: int in run.registry.ids():
		if not NOT_KEPT.has(run.registry.get_entity(id).kind):
			kept.append(id)
	w.put_i64(run.registry.next_id())
	w.put_i64(kept.size())
	for id: int in kept:
		var e: SimEntity = run.registry.get_entity(id)
		w.put_i64(id)
		w.put_i32(e.kind)
		w.put_f64(e.position.x)
		w.put_f64(e.position.y)
		w.put_i32(e.flags)
	return w.bytes()


## A section's plain bytes (an empty dictionary's when absent).
static func section(sections: Dictionary, name: String) -> PackedByteArray:
	if not sections.has(name):
		return var_to_bytes({})
	var b: PackedByteArray = sections[name]
	return b


## The run header a resume starts from: {run_seed, mode, offline, run_uuid, map_name, tick, ...}.
static func run_header(sections: Dictionary) -> Dictionary:
	return Variants.dict(bytes_to_var(section(sections, SECTION_RUN)))


## Puts a snapshot back into a fresh run of the same seed and mode, its systems installed and its
## map loaded (without placements), then lets the journal's later falls and deaths stand.
static func restore(run: RunState, net: ServerNet, sections: Dictionary, journal: Array[Dictionary] = []) -> Dictionary:
	var head: Dictionary = run_header(sections)
	run.tick = int(Variants.number(head.get("tick", 0)))
	run.phase = int(Variants.number(head.get("phase", 0))) as RunState.Phase
	run.header.run_uuid = str(head.get("run_uuid", ""))
	run.header.map_name = str(head.get("map_name", ""))
	run.header.resumed = true
	# GEN-08: the plan the mine was generated with (server_main loads it before any derive).
	var plan: Variant = head.get("plan", PackedByteArray())
	if plan is PackedByteArray:
		run.header.plan = plan
	run.restore_streams(Variants.dict(head.get("streams", {})))
	# MOD-03: the setup as created, never drawn again; the seats as they were.
	if head.has("options"):
		run.header.options = RunOptions.from_dict(Variants.dict(head["options"]))
		run.header.humans_at_start = int(Variants.number(head.get("humans_at_start", 0)))
		run.header.staging = str(head.get("staging", ""))
		var drawn: Variant = head.get("draw", PackedStringArray())
		run.header.draw = drawn if drawn is PackedStringArray else PackedStringArray()
		run.header.rule_flags = Variants.dict(head.get("rule_flags", {}))
	if net != null and head.has("crew"):
		net.crew.from_dict(Variants.dict(head["crew"]))
	var reader: SimStateReader = SimStateReader.new(section(sections, SECTION_REGISTRY))
	run.registry.read_state(reader)
	if run.diff_log != null and sections.has(SECTION_DIFF_LOG):
		run.diff_log.deserialise(section(sections, SECTION_DIFF_LOG))
		if run.mine != null:
			for c: Vector2i in run.mine.native.loaded_cells():
				run.diff_log.replay(run, c)
	var state: Dictionary = Variants.dict(bytes_to_var(section(sections, SECTION_STATE)))
	for sys: SimSystem in run.stages.all_systems():
		if state.has(sys.system_name()):
			sys.load_state(run, Variants.dict(state[sys.system_name()]))
	if run.record != null and sections.has(SECTION_WINDOWS):
		run.record.import_windows(Variants.array(bytes_to_var(section(sections, SECTION_WINDOWS))))
	# Every miner is watched again; its player retakes the seat on rejoining (NET-11).
	if run.movement != null and run.vision != null:
		for slot: int in run.movement.miner_slots():
			run.vision.watch(slot, run.movement.miner(slot).entity_id, 0)
	var seats: Dictionary = Variants.dict(head.get("seats", {}))
	if net != null:
		for raw: Variant in seats.keys():
			var d: Dictionary = seats[raw]
			var s: SeatTable.Seat = SeatTable.Seat.new()
			s.identity = str(raw)
			s.slot = int(Variants.number(d["slot"]))
			s.miner = int(Variants.number(d["miner"]))
			s.token = str(d.get("token", ""))
			var was: int = int(Variants.number(d["state"]))
			s.state = SeatTable.State.REMOVED if was == SeatTable.State.REMOVED else (SeatTable.State.HAND_KEEPS
				if was == SeatTable.State.HAND_KEEPS else SeatTable.State.RESERVED)
			s.dropped_tick = run.tick
			net.seats.seats[s.identity] = s
	var applied: int = Journal.apply_after(run, journal, run.tick)
	# Nobody is connected yet: every conscious miner is held as if dropped (NET-11).
	if run.drops != null and run.miner_state != null:
		for slot: int in run.movement.miner_slots():
			var m: int = run.movement.miner(slot).entity_id
			if run.miner_state.life(m) == MinerTransitions.Life.UPRIGHT:
				run.drops.take_over.call(run, m, DropHandler.Takeover.DROPPED)
	return {"tick": run.tick, "journal_applied": applied}
