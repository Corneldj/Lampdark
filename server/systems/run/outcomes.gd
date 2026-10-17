class_name RunOutcomes
extends SimSystem
## LFT-11 (stage RECORD, after MNR-03's flush and DIR-05's census): how the run ends and each miner's
## outcome (Gameplay §3.8, §11.1, §11.9, §11.11, §13.9, §13.11).
## - The wipe: every tick until the cage leaves, if no counted miner is conscious (Upright, Caught or
##   Grabbed: a hold is conscious) and no self-revive is pending (RSC-09's deferral_active), the run
##   is wiped there and then: every miner Left Below, the map table frozen. Counted: every player
##   miner, whoever drives it (a Hand-driven dropped one included); never a Hired Hand's own
##   (CrewCensus.is_hired_hand) or an absent player's miner waiting in base camp (is_absent).
## - At departure (Cage's cage_departed) the riders are provisionally Escaped and everyone else Left
##   Below, and nothing below can wipe the run any more: a conscious miner left below plays on
##   through the 40 s ride.
## - At the surface (cage_surfaced) each miner's outcome is set once (MNR-03's set_outcome, the life
##   state kept, so a dead rider reads Dead, brought home) and the run ends for everyone that tick.
## - The end: RunEnd's record goes out by run_ended for Lamp Check (RSC-06), the run record (NET-07),
##   the map card (LFT-14) and telemetry (QA-04), and NET-09's save chain closes (its journal's last
##   entry: no resume opens a finished run).
## - An abnormal end records no outcome (the run resumes later); a public one is void (NET-09's
##   voided): no outcome and no run_ended, ever.
## - An absent player's miner waiting in base camp (MOD-05) takes no outcome here, at a wipe or the
##   last ride, and is not in the record: its outcome is MOD-05's to decide (Proposed).
## Server-only: no outcome, and nothing of who is conscious or below, is sent before Lamp Check.

signal run_ended(record: Dictionary)

var ended: bool = false
var ended_tick: int = -1
var wiped: bool = false
var departed: bool = false
var voided: bool = false
## miner -> MinerTransitions.Outcome (provisional from departure, final at the surface or a wipe).
var outcomes: Dictionary = {}
var deepest_ring: int = 0
## The run's first tick (its time below counts from here).
var start_tick: int = 0
var record: Dictionary = {}
## MOD-03: (miner) -> {name, lamp_number} from the seated roster miner. Default: none (the record
## then carries the lamp check's number and no name).
var identity_of: Callable = Callable()
var log: Array[Dictionary] = []


func stage() -> int:
	return StageTable.Stage.RECORD


## After MNR-03's flush (0), DIR-05's census (10) and RSC-09's alone watch (12): this tick's falls
## stand.
func order() -> int:
	return 14


func system_name() -> String:
	return "outcomes"


func bind(run: RunState) -> void:
	if run.cage != null:
		run.cage.cage_departed.connect(func(snapshot: Dictionary) -> void: _on_departed(run, snapshot))
		run.cage.cage_surfaced.connect(func(_top: Dictionary) -> void: _on_surfaced(run))
	if run.saves != null:
		run.saves.voided.connect(func(why: String) -> void:
			voided = true
			_note(run, "voided", {"why": why}))


## The miners who count for the wipe and the crew: player miners, no Hired Hand, nobody absent.
static func counted(run: RunState) -> Array[int]:
	var out: Array[int] = []
	var ids: Array = Array(run.registry.ids())
	ids.sort()
	for raw: Variant in ids:
		var id: int = int(Variants.number(raw))
		var e: SimEntity = run.registry.get_entity(id)
		if e == null or e.kind != WorldIds.EntityKind.MINER:
			continue
		if run.crew != null and (Variants.flag(run.crew.is_hired_hand.call(id)) or Variants.flag(run.crew.is_absent.call(id))):
			continue
		out.append(id)
	return out


## Upright, Caught or Grabbed.
static func conscious(run: RunState, miner: int) -> bool:
	return run.miner_state == null or run.miner_state.miner(miner) == null or run.miner_state.life(miner) < MinerTransitions.Life.UNCONSCIOUS


func tick(run: RunState) -> void:
	if ended or voided:
		return
	var crew: Array[int] = counted(run)
	for m: int in crew:
		deepest_ring = maxi(deepest_ring, Depth.ring_of_entity(run, m))
	if departed or crew.is_empty():
		return
	for m: int in crew:
		if conscious(run, m):
			return
	if run.self_revive != null and run.self_revive.deferral_active():
		return
	_wipe(run, crew)


func _wipe(run: RunState, crew: Array[int]) -> void:
	wiped = true
	for m: int in _takers(run):
		outcomes[m] = MinerTransitions.Outcome.LEFT_BELOW
	_note(run, "wipe", {"crew": crew})
	if run.sheets != null and run.sheets.table != null:
		run.sheets.table.freeze(run, "wipe")
	_end(run, crew)


func _on_departed(run: RunState, snapshot: Dictionary) -> void:
	if ended or voided:
		return
	departed = true
	var riders: Array = Variants.array(snapshot.get("miners", []))
	for m: int in _takers(run):
		outcomes[m] = MinerTransitions.Outcome.ESCAPED if riders.has(m) else MinerTransitions.Outcome.LEFT_BELOW
	_note(run, "departed", {"riders": riders.size()})


func _on_surfaced(run: RunState) -> void:
	if ended or voided:
		return
	_note(run, "surfaced", {})
	_end(run, counted(run))


## Sets every outcome once and hands the record off.
func _end(run: RunState, crew: Array[int]) -> void:
	ended = true
	ended_tick = run.tick
	for raw: Variant in outcomes.keys():
		if run.miner_state != null:
			run.miner_state.set_outcome(int(Variants.number(raw)), int(Variants.number(outcomes[raw])))
	record = RunEnd.build(run, crew, outcomes, wiped, deepest_ring, start_tick, identity_of)
	_note(run, "ended", {"wipe": wiped, "up": record["up_count"], "crew": record["crew_size"]})
	if run.saves != null:
		run.saves.close(run, "wipe" if wiped else "surfaced")
	run_ended.emit(record)


## The miners who take an outcome: every one but an absent player's.
func _takers(run: RunState) -> Array[int]:
	var out: Array[int] = []
	var ids: Array = Array(run.registry.ids())
	ids.sort()
	for raw: Variant in ids:
		var id: int = int(Variants.number(raw))
		var e: SimEntity = run.registry.get_entity(id)
		if e != null and e.kind == WorldIds.EntityKind.MINER and not (run.crew != null and Variants.flag(run.crew.is_absent.call(id))):
			out.append(id)
	return out


func _note(run: RunState, what: String, fields: Dictionary) -> void:
	var entry: Dictionary = {"tick": run.tick, "what": what}
	entry.merge(fields)
	log.append(entry)
	Log.info("outcomes: %s %s" % [what, str(fields)])


func write_state(writer: SimStateWriter) -> void:
	writer.put_bool(ended)
	writer.put_bool(wiped)
	writer.put_bool(departed)
	writer.put_i64(deepest_ring)


## NET-09: where the run stands (a resume can land during the ride, its outcomes provisional).
func save_state() -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in outcomes.keys():
		out[str(raw)] = outcomes[raw]
	return {"ended": ended, "ended_tick": ended_tick, "wiped": wiped, "departed": departed, "outcomes": out, "deepest_ring": deepest_ring,
		"start_tick": start_tick}


func load_state(_run_state: RunState, state: Dictionary) -> void:
	ended = Variants.flag(state.get("ended", false))
	ended_tick = int(Variants.number(state.get("ended_tick", -1)))
	wiped = Variants.flag(state.get("wiped", false))
	departed = Variants.flag(state.get("departed", false))
	deepest_ring = int(Variants.number(state.get("deepest_ring", 0)))
	start_tick = int(Variants.number(state.get("start_tick", 0)))
	outcomes.clear()
	var saved: Dictionary = Variants.dict(state.get("outcomes", {}))
	for raw: Variant in saved.keys():
		outcomes[int(str(raw))] = int(Variants.number(saved[raw]))
