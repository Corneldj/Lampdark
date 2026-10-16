class_name TwoMinerJobs
extends SimSystem
## LFT-04 (stage WORLD): the one component that runs every job for two (Gameplay §3.3, §3.6, §11.11;
## GDD §15.2). Job tickets (LFT-05, LFT-07, LFT-08) add their CuePress and PairedWork instances with
## add(); this system keeps their places and drives them each tick.
##
## - A place is MNR-04's interaction target (kind job_place) in touch range: interact held at it
##   takes a free place and keeps it while held, in reach and allowed; a fresh press at a CuePress's
##   presser place is the press, judged against the cue as the presser's screen showed it.
## - Who may take a place: a conscious miner (Upright or Caught) with a free hand; never a Hired
##   Hand or a Hand-driven dropped miner (refused and logged), never Bess or a creature (not miners),
##   never Grabbed or carrying two-handed. One miner, one place.
## - The alone rules (AloneRules, RSC-09's solo_jobs): a CuePress's H stays ready
##   lift.alone_place_hold_s after release; PairedWork goes at 1 / lift.alone_work_multiplier.
## - SND-11's job page: at_two_person_job() is true for a miner holding a place or in touch range of
##   one; the owner's client is told through its status (StatusWire.AT_JOB).
## - Cues, presses, successes and misses are logged for NET-07's run record (Inquiry lines).
## Nothing of a window, a hold-over, progress or a ruling ever reaches a client; the jobs' own events
## are the outcome. Server-only.

## The jobs: CuePress and PairedWork.
var jobs: Array = []
## {tick, job, what, ...}: cues, presses, successes, misses and completions (NET-07 reads it).
var log: Array[Dictionary] = []
## Refused takes: {tick, entity, place, why} (a Hand's injected input, say).
var refused: Array[Dictionary] = []
var _places: Dictionary = {}
var _next_place: int = 1
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 35


func system_name() -> String:
	return "two_miner_jobs"


func bind(run: RunState) -> void:
	_run = run
	if run.inventory != null:
		run.inventory.targets.providers.append(_targets)
	if run.callouts != null:
		run.callouts.at_two_miner_job = func(_r: RunState, entity: int) -> bool: return at_two_person_job(entity)
	if run.lone != null:
		run.lone.register("solo_jobs", func(r: RunState, miner: int) -> bool: return AloneRules.is_alone(r, miner))


## A job ticket's CuePress or PairedWork joins; its places are numbered.
func add(job: RefCounted) -> RefCounted:
	jobs.append(job)
	for p: JobPlace in _places_of(job):
		p.id = _next_place
		_next_place += 1
		_places[p.id] = [p, job]
	return job


func remove(job: RefCounted) -> void:
	jobs.erase(job)
	for p: JobPlace in _places_of(job):
		_places.erase(p.id)


## SND-11's job page: holding a place, or in touch range of one.
func at_two_person_job(entity: int) -> bool:
	if _run == null:
		return false
	var e: SimEntity = _run.registry.get_entity(entity)
	if e == null:
		return false
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	for raw: Variant in _places.values():
		var p: JobPlace = Variants.array(raw)[0]
		if p.holder == entity or e.position.distance_to(p.anchor) <= reach:
			return true
	return false


## "" when `entity` may take a place now, else why not.
func why_not_take(run: RunState, entity: int) -> String:
	var e: SimEntity = run.registry.get_entity(entity)
	if e == null or e.kind != WorldIds.EntityKind.MINER:
		return "not a miner"
	if run.crew != null and Variants.flag(run.crew.is_hand_driven.call(entity)):
		return "a hand"
	if run.miner_state != null:
		var life: int = run.miner_state.life(entity)
		if life != MinerTransitions.Life.UPRIGHT and life != MinerTransitions.Life.CAUGHT:
			return "not standing"
	if run.inventory != null and run.inventory.free_hand_blocked(entity, &"job"):
		return "no free hand"
	return ""


## Takes `place` for `entity` if allowed and free (the scenario's and the job tickets' hook too).
func take(run: RunState, place: JobPlace, entity: int) -> bool:
	var why: String = why_not_take(run, entity)
	if why.is_empty() and place.holder != 0:
		why = "taken"
	if why.is_empty() and holds_any(entity):
		why = "one place"
	if not why.is_empty():
		_refuse(run, entity, place, why)
		return false
	place.holder = entity
	place.since = run.tick
	return true


func holds_any(entity: int) -> bool:
	for raw: Variant in _places.values():
		var p: JobPlace = Variants.array(raw)[0]
		if p.holder == entity:
			return true
	return false


func tick(run: RunState) -> void:
	_run = run
	if run.movement == null:
		return
	for raw: Variant in _places.values():
		var pair: Array = raw
		var place: JobPlace = pair[0]
		var job: RefCounted = pair[1]
		_keep_or_release(run, place, job)
	# Takes first, then each job's step (a cue comes the tick its place is ready), then presses: a
	# press the tick the trip is taken is judged against that cue, before it reached anyone.
	var presses: Array[Array] = []
	for slot: int in run.movement.miner_slots():
		_input(run, slot, presses)
	for raw: Variant in jobs:
		var job: RefCounted = raw
		job.call(&"step", run, self)
	for p: Array in presses:
		var cp: CuePress = p[0]
		var c: InputBuffer.Consumed = p[3]
		cp.press(run, self, int(Variants.number(p[1])), int(Variants.number(p[2])), c)


## A holder keeps a held place while interact stays held, in touch range and allowed.
func _keep_or_release(run: RunState, place: JobPlace, job: RefCounted) -> void:
	if place.holder == 0 or not _held_place(job, place):
		return
	var entity: int = place.holder
	var c: InputBuffer.Consumed = _input_of(run, entity)
	var holding: bool = c != null and (c.record.holds & InputRecord.HOLD_INTERACT) != 0
	var e: SimEntity = run.registry.get_entity(entity)
	var near: bool = e != null and e.position.distance_to(place.anchor) <= Tuning.f(&"vision.touch_range_tiles")
	if holding and near and why_not_take(run, entity).is_empty():
		return
	place.holder = 0
	place.released_by = entity
	# Let go by the miner's own hand: when their screen showed it; otherwise now.
	place.released_at = float(c.shown_tick) if c != null and not holding else float(run.tick)
	note(run, job, "release", {"miner": entity})


## Interact at a place this tick: a take now, or a press at a presser place for after the steps.
func _input(run: RunState, slot: int, presses: Array[Array]) -> void:
	var c: InputBuffer.Consumed = run.input_for(slot)
	if c == null or (c.record.holds & InputRecord.HOLD_INTERACT) == 0 or run.inventory == null:
		return
	var entity: int = run.movement.miner(slot).entity_id
	var target: Dictionary = run.inventory.targets.pick(run, entity, slot, run.inventory.world)
	if StringName(str(target.get("kind", ""))) != &"job_place":
		return
	var pair: Array = Variants.array(_places.get(int(Variants.number(target["id"])), []))
	if pair.is_empty():
		return
	var place: JobPlace = pair[0]
	var job: RefCounted = pair[1]
	var fresh: bool = run.inventory.is_fresh(entity, c.record.holds, InputRecord.HOLD_INTERACT)
	if not _held_place(job, place):
		# A presser's place: a fresh press is the press.
		if not fresh:
			return
		run.inventory.mark_spent(entity, InputRecord.HOLD_INTERACT)
		var why: String = why_not_take(run, entity)
		if not why.is_empty():
			_refuse(run, entity, place, why)
			return
		if job is CuePress:
			presses.append([job, entity, slot, c])
		return
	if place.holder == entity or not fresh:
		return
	run.inventory.mark_spent(entity, InputRecord.HOLD_INTERACT)
	if take(run, place, entity):
		note(run, job, "take", {"miner": entity})


## The slots of every miner who could press a cue now, the holder aside.
func presser_slots(run: RunState, holder: int) -> Array[int]:
	var out: Array[int] = []
	for slot: int in run.movement.miner_slots():
		var entity: int = run.movement.miner(slot).entity_id
		if entity != holder and why_not_take(run, entity).is_empty():
			out.append(slot)
	if AloneRules.is_alone(run, holder):
		var own: int = _slot_of(run, holder)
		if own >= 0 and not out.has(own):
			out.append(own)  # alone, the holder may let go and press
	out.sort()
	return out


## The newest input stamp NET-06 has seen from `entity`'s client, -1 if none.
func newest_stamp_of(run: RunState, entity: int) -> float:
	var slot: int = _slot_of(run, entity)
	if slot < 0 or run.now_judge == null:
		return -1.0
	return float(Variants.number(run.now_judge.newest_stamp.get(slot, -1)))


func note(run: RunState, job: RefCounted, what: String, fields: Dictionary = {}) -> void:
	var entry: Dictionary = {"tick": run.tick, "job": str(job.get(&"name")), "what": what}
	entry.merge(fields)
	log.append(entry)
	if what in ["success", "miss", "complete"]:
		Log.info("two-miner job %s: %s %s" % [entry["job"], what, str(fields.get("why", ""))])


func _refuse(run: RunState, entity: int, place: JobPlace, why: String) -> void:
	refused.append({"tick": run.tick, "entity": entity, "place": place.id, "why": why})
	if why == "a hand" or why == "not a miner":
		Log.info("two-miner job: refused a place to %d (%s)" % [entity, why])


## MNR-04's interaction targets: every place in touch range.
func _targets(_r: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	var out: Array = []
	var ids: Array = _places.keys()
	ids.sort()
	for raw: Variant in ids:
		var p: JobPlace = Variants.array(_places[raw])[0]
		if at.distance_to(p.anchor) <= reach:
			out.append({"kind": &"job_place", "id": p.id, "point": p.anchor})
	return out


static func _places_of(job: RefCounted) -> Array[JobPlace]:
	var out: Array[JobPlace] = []
	for raw: Variant in Variants.array(job.call(&"places")):
		var p: JobPlace = raw
		out.append(p)
	return out


static func _held_place(job: RefCounted, place: JobPlace) -> bool:
	for raw: Variant in Variants.array(job.call(&"held_places")):
		if raw == place:
			return true
	return false


func _input_of(run: RunState, entity: int) -> InputBuffer.Consumed:
	var slot: int = _slot_of(run, entity)
	return run.input_for(slot) if slot >= 0 else null


func _slot_of(run: RunState, entity: int) -> int:
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


## NET-09: the shared work done, by job (a cue and its places start afresh: everyone rejoins).
func save_state() -> Dictionary:
	var work: Dictionary = {}
	for job: Variant in jobs:
		if job is PairedWork:
			var w: PairedWork = job
			work[w.name] = {"progress": w.progress, "done": w.done}
	return {"work": work}


func load_state(_r: RunState, state: Dictionary) -> void:
	var work: Dictionary = Variants.dict(state.get("work", {}))
	for job: Variant in jobs:
		if job is PairedWork:
			var w: PairedWork = job
			var saved: Dictionary = Variants.dict(work.get(w.name, {}))
			w.progress = float(Variants.number(saved.get("progress", w.progress)))
			w.done = Variants.flag(saved.get("done", w.done))


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = _places.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var p: JobPlace = Variants.array(_places[raw])[0]
		writer.put_i64(p.id)
		writer.put_i64(p.holder)
	for job: Variant in jobs:
		if job is PairedWork:
			var w: PairedWork = job
			writer.put_f64(w.progress)
		elif job is CuePress:
			var cp: CuePress = job
			writer.put_i64(cp.state)
