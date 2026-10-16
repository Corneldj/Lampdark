class_name WinderEngine
extends SimSystem
## LFT-08 (stage WORLD, after the jobs for two and the tank): the winder's paraffin engine at GEN-02's
## engine_prime, engine_crank and engine_throttle anchors (Gameplay §3.3, §3.6, §3.9; GDD §2.5).
##
## Cold, it is primed by one miner in lift.prime_s of held interact, standing still, once every
## other job on the list is done (LFT-03's can_start) and the tank is not dry. Primed, the start is
## LFT-04's CuePress: a miner holds the crank (lift.crank_s, a 20 np heave from the stroke's start);
## at the top a clank (the cue, a TimedCues ENGINE_CRANK event) and the winder shudders; a second
## miner throttles on 'Now!' within the window and it catches. A miss backfires (30 np) and keeps
## the prime (Proposed), so one more crank can catch (§3.9); alone, the crank holds at the top
## for LFT-04's hold-over. The crank and throttle exist only while primed.
##
## Running, it knocks at 24 np every noise.engine_interval_s, heard from the winder and from every
## gate's inner face at once (base camp's arches carry it to the gates: 24 beyond an open gate, 12
## beyond a shut one, SND-01), burns one tick of the tank a tick (LFT-06; a can lasts
## lift.engine_s_per_can) and runs up: the clutch engages only after lift.clutch_run_up_s of
## running since the latest catch (LFT-10 reads run_up_complete). Dry, it stops (Cold: a new start
## needs fuel, a prime, a crank and a throttle) and the run-up resets. The first catch marks Start
## done. Hired Hands never prime, crank or throttle. Clients get only sounds and the winder's look
## (cold, shuddering, running) on its FIXTURE records; never the fuel, the run-up, the state as data
## or the window.

signal engine_caught(tick: int)
signal engine_stopped(why: StringName)

enum State { COLD = 0, PRIMED = 1, RUNNING = 2, DEPARTED = 3 }

const DRY: StringName = &"dry"
const ANCHORS: Array[String] = ["engine_prime", "engine_crank", "engine_throttle"]

var state: State = State.COLD
## The latest catch's tick, -1 when not running.
var caught_at: int = -1
## Start marked done (the first catch).
var started: bool = false
## The crank and throttle while primed.
var crank: CuePress = null
## Anchor name -> tile centre; anchor name -> its FIXTURE entity.
var anchors: Dictionary = {}
var fixtures: Dictionary = {}
## NET-07: {tick, what, ...} for primes, catches, backfires and stops (the crank's cues and presses
## are LFT-04's log).
var log: Array[Dictionary] = []
var refused: Array[Dictionary] = []
var _drop_crank: bool = false
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 38


func system_name() -> String:
	return "engine"


func bind(run: RunState) -> void:
	_run = run
	if run.inventory != null:
		run.inventory.targets.providers.append(_targets)


#region Queries

func is_running() -> bool:
	return state == State.RUNNING


## Seconds of running since the latest catch (0 when not running).
func running_s(run: RunState) -> float:
	return (run.tick - caught_at) / Tuning.f(&"net.tick_hz") if state == State.RUNNING else 0.0


## LFT-10: the clutch engages only after lift.clutch_run_up_s of continuous running.
func run_up_complete(run: RunState) -> bool:
	return state == State.RUNNING and running_s(run) >= Tuning.f(&"lift.clutch_run_up_s") - 1e-9


## The winder's look: 0 cold, 1 shuddering (the crank at its top), 2 running.
func look() -> int:
	if state == State.RUNNING:
		return 2
	return 1 if crank != null and crank.state == CuePress.State.READY else 0


## Why `miner` may not prime now, or "".
func why_not_prime(run: RunState, miner: int) -> String:
	if ToolsParts.is_hand(run, miner):
		return "a Hand"
	if state != State.COLD:
		return "not cold"
	if run.repair == null or not run.repair.can_start():
		return "jobs left"
	if run.fuel == null or run.fuel.is_empty():
		return "dry"
	return ""

#endregion


#region The start

## Priming: lift.prime_s of held interact at the prime, standing still.
func prime_action(run: RunState, miner: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(miner, &"prime_engine", Tuning.f(&"lift.prime_s"), InputRecord.HOLD_INTERACT)
	a.needs_still = true
	a.target_point = anchors.get("engine_prime", Vector2.ZERO)
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool: return why_not_prime(run, miner).is_empty()
	a.effect = func() -> void: _prime(run, miner)
	return a


func _prime(run: RunState, miner: int) -> void:
	state = State.PRIMED
	_note(run, "prime", {"miner": miner})
	_crank_on(run)


## The crank (H, held lift.crank_s to its top) and the throttle (P) as LFT-04's CuePress.
func _crank_on(run: RunState) -> void:
	if crank != null or run.two_miner == null:
		return
	var at: Vector2 = anchors["engine_crank"]
	var cue: Callable = func(r: RunState, _job: CuePress) -> int:
		# The clank at the top: the cue every presser's client times.
		r.noise.emit(NoiseTypes.Type.ENGINE_CRANK, Vector2i(floori(at.x), floori(at.y)), {"duration_s": 0.0})
		return NoiseTypes.Type.ENGINE_CRANK
	var ok: Callable = func(r: RunState, _job: CuePress, presser: int) -> void: _catch(r, presser)
	var miss: Callable = func(r: RunState, _job: CuePress, why: String) -> void: _backfire(r, why)
	crank = CuePress.make({"name": "engine_start", "holder_anchor": at, "presser_anchor": anchors["engine_throttle"],
		"hold_to_ready_s": Tuning.f(&"lift.crank_s"), "on_cue": cue, "on_success": ok, "on_miss": miss})
	run.two_miner.add(crank)


func _crank_off(run: RunState) -> void:
	if crank != null and run.two_miner != null:
		run.two_miner.remove(crank)
	crank = null


func _catch(run: RunState, presser: int) -> void:
	state = State.RUNNING
	caught_at = run.tick
	_drop_crank = true
	_note(run, "catch", {"miner": presser})
	engine_caught.emit(run.tick)
	if not started:
		started = true
		if run.repair != null:
			run.repair.mark_done(run, &"start")


## A miss: a backfire at the winder, the prime kept (Proposed).
func _backfire(run: RunState, why: String) -> void:
	if run.noise != null:
		run.noise.emit(NoiseTypes.Type.BACKFIRE, _tile("engine_crank"))
	_note(run, "backfire", {"why": why})


## Stops the engine (dry: Cold again, the run-up reset).
func stop(run: RunState, why: StringName) -> void:
	state = State.COLD
	caught_at = -1
	_crank_off(run)
	_note(run, "stop", {"why": str(why)})
	engine_stopped.emit(why)


## LFT-10: the cage has left; the ride needs no more fuel (Proposed).
func depart(run: RunState) -> void:
	state = State.DEPARTED
	_crank_off(run)
	_note(run, "depart", {})

#endregion


func tick(run: RunState) -> void:
	_run = run
	_place(run)
	if anchors.is_empty():
		return
	if _drop_crank:
		_drop_crank = false
		_crank_off(run)
	_input(run)
	# The crank's heave, from the stroke's start (Proposed: one 20 np event lasting lift.crank_s).
	if crank != null and crank.state == CuePress.State.ARMED and crank.armed_at == run.tick and run.noise != null:
		run.noise.emit(NoiseTypes.Type.ENGINE_CRANK, _tile("engine_crank"), {"duration_s": Tuning.f(&"lift.crank_s")})
	if state != State.RUNNING:
		return
	# A tick of the tank a tick; the engine stops on the tick it runs dry.
	if run.tick > caught_at and (run.fuel == null or run.fuel.consume_ticks(1) == 0 or run.fuel.is_empty()):
		stop(run, DRY)
		return
	var every: int = roundi(Tuning.f(&"noise.engine_interval_s") * Tuning.f(&"net.tick_hz"))
	if (run.tick - caught_at) % every == 0 and run.noise != null:
		run.noise.emit(NoiseTypes.Type.ENGINE_RUNNING, _tile("engine_crank"), {"origins": _beat_origins(run), "source": _fixture("engine_crank")})


## A fresh interact at the prime starts the prime (or is refused).
func _input(run: RunState) -> void:
	if run.movement == null or run.inventory == null:
		return
	for slot: int in run.movement.miner_slots():
		var c: InputBuffer.Consumed = run.input_for(slot)
		var miner: int = run.movement.miner(slot).entity_id
		if c == null or run.inventory.actions.has(miner) or run.inventory.is_partner(miner) \
				or not run.inventory.is_fresh(miner, c.record.holds, InputRecord.HOLD_INTERACT):
			continue
		var target: Dictionary = run.inventory.targets.pick(run, miner, slot, run.inventory.world)
		if StringName(str(target.get("kind", ""))) != &"engine_prime":
			continue
		run.inventory.mark_spent(miner, InputRecord.HOLD_INTERACT)
		var why: String = why_not_prime(run, miner)
		if not why.is_empty():
			refused.append({"tick": run.tick, "miner": miner, "why": why})
			continue
		run.inventory.start_action(run, prime_action(run, miner))


## The beat's origins: the winder, and every gate's inner face (the arches carry it there).
func _beat_origins(run: RunState) -> Array[Vector2i]:
	var out: Array[Vector2i] = [_tile("engine_crank")]
	if run.base_camp != null and run.base_camp.gate_system != null:
		for g: Dictionary in run.base_camp.gates:
			var gate: Gate = run.base_camp.gate_system.gate(str(g["side"]))
			if gate != null:
				out.append(gate.middle() - gate.outward)
	return out


## The anchors and their fixtures, once base camp is known.
func _place(run: RunState) -> void:
	if not anchors.is_empty() or run.base_camp == null:
		return
	for name: String in ANCHORS:
		var found: Array[Dictionary] = Basecamp.fixture(run.base_camp.seed_value, name, run.base_camp.side)
		if found.is_empty():
			anchors.clear()
			return
		var tile: Vector2i = found[0]["position"]
		anchors[name] = Vector2(tile) + Vector2(0.5, 0.5)
	for name: String in ANCHORS:
		if int(Variants.number(fixtures.get(name, 0))) == 0 or not run.registry.has(int(Variants.number(fixtures[name]))):
			var at: Vector2 = anchors[name]
			fixtures[name] = run.registry.create(WorldIds.EntityKind.FIXTURE, at).id
	if state == State.PRIMED:
		_crank_on(run)


func _tile(name: String) -> Vector2i:
	var at: Vector2 = anchors.get(name, Vector2.ZERO)
	return Vector2i(floori(at.x), floori(at.y))


func _fixture(name: String) -> int:
	return int(Variants.number(fixtures.get(name, 0)))


## Each fixture's identity bits (FixtureKinds): the prime, the crank with the winder's look, the throttle.
func fixture_bits() -> Dictionary:
	var out: Dictionary = {}
	for name: String in ANCHORS:
		var e: int = _fixture(name)
		if e == 0:
			continue
		match name:
			"engine_prime":
				out[e] = FixtureKinds.Kind.ENGINE_PRIME
			"engine_crank":
				out[e] = FixtureKinds.engine(look())
			"engine_throttle":
				out[e] = FixtureKinds.Kind.ENGINE_THROTTLE
	return out


## MNR-04's interaction targets: the prime in touch range, while there is something to prime.
func _targets(_run_state: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	if not anchors.has("engine_prime"):
		return []
	var prime: Vector2 = anchors["engine_prime"]
	if at.distance_to(prime) > reach + 1e-9:
		return []
	return [{"kind": &"engine_prime", "id": _fixture("engine_prime"), "point": prime}]


func _note(run: RunState, what: String, fields: Dictionary) -> void:
	var entry: Dictionary = {"tick": run.tick, "what": what}
	entry.merge(fields)
	log.append(entry)
	Log.info("engine: %s %s" % [what, str(fields)])


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(state)
	writer.put_i64(caught_at)
	writer.put_bool(started)
	writer.put_i64(log.size())


## NET-09: the state, the run-up (as ticks run), the Start latch and the fixtures' entities.
func save_state() -> Dictionary:
	var ran: int = _run.tick - caught_at if state == State.RUNNING and _run != null else -1
	return {"state": state, "ran_ticks": ran, "started": started, "fixtures": fixtures.duplicate()}


func load_state(run: RunState, state_dict: Dictionary) -> void:
	state = int(Variants.number(state_dict.get("state", State.COLD))) as State
	started = Variants.flag(state_dict.get("started", false))
	var ran: int = int(Variants.number(state_dict.get("ran_ticks", -1)))
	caught_at = run.tick - ran if state == State.RUNNING and ran >= 0 else -1
	if state == State.RUNNING and caught_at < 0:
		state = State.COLD
	# The restored registry keeps the fixtures; _place makes any it lacks.
	fixtures = {}
	var saved: Dictionary = Variants.dict(state_dict.get("fixtures", {}))
	for name: String in ANCHORS:
		var e: int = int(Variants.number(saved.get(name, 0)))
		if e != 0 and run.registry.has(e):
			fixtures[name] = e
