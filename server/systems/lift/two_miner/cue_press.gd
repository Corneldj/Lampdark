class_name CuePress
extends RefCounted
## LFT-04: a job timed by a cue and a press (Gameplay §3.3, §3.6): the main switch (one miner holds
## the trip while another throws the switch on 'Now!') and the start (the crank's clank, then the
## throttle). The holder's place H, held, becomes ready after `hold_to_ready_s` (the trip at once,
## the crank at its top): that is the cue, a server audio event of a TimedCues type that each
## possible presser's client reports as shown (NET-06). A press at the presser's place P counts if,
## on the presser's own screen, it came 0 to lift.now_window_s after the cue, and H was still ready
## when it was pressed (GDD §15.2). A press before the cue, after the window, or after H let go is a
## miss; with no press, a miss is ruled once no press can still count (lift.now_late_press_grace_ticks
## on top of NET-06's rule). Alone (AloneRules: solo or a lone human), H stays ready
## lift.alone_place_hold_s after its miner lets go, and a press counts while it does (Proposed), so
## one miner may hold H, let go and press P. After a success or a miss, H must be let go and taken
## again for a new cue. Each job ticket builds one from data and supplies the effects. Server-only.

enum State { IDLE = 0, ARMED = 1, READY = 2, SPENT = 3 }

var name: String = ""
var holder_place: JobPlace = JobPlace.new()
var presser_place: JobPlace = JobPlace.new()
var window_s: float = 1.0
## How long H must be held before it is ready (the crank's stroke; 0 for the trip).
var hold_to_ready_s: float = 0.0
## (run, job) -> int: emits the cue now and returns its TimedCues type (the job's event).
var on_cue: Callable = Callable()
## (run, job, presser) -> void
var on_success: Callable = Callable()
## (run, job, why: String) -> void ("early", "late", "let go")
var on_miss: Callable = Callable()
var state: State = State.IDLE
var armed_at: int = -1
var cue_tick: int = -1
var cue_type: int = -1
## slot -> the cue's id as NET-06 names it for that slot's client.
var cue_ids: Dictionary = {}
## The alone rules held at the cue.
var alone: bool = false
## When H stopped being ready on the press timeline (its release, plus the hold-over alone); -1 while held.
var ready_until: float = -1.0


## {holder_anchor, presser_anchor, window_s, hold_to_ready_s, on_cue, on_success, on_miss, name}
static func make(cfg: Dictionary) -> CuePress:
	var j: CuePress = CuePress.new()
	j.name = str(cfg.get("name", "cue_press"))
	var h: Vector2 = cfg["holder_anchor"]
	var p: Vector2 = cfg["presser_anchor"]
	j.holder_place = JobPlace.at(h)
	j.presser_place = JobPlace.at(p)
	j.window_s = float(Variants.number(cfg.get("window_s", Tuning.f(&"lift.now_window_s"))))
	j.hold_to_ready_s = float(Variants.number(cfg.get("hold_to_ready_s", 0.0)))
	j.on_cue = cfg.get("on_cue", Callable())
	j.on_success = cfg.get("on_success", Callable())
	j.on_miss = cfg.get("on_miss", Callable())
	return j


func places() -> Array[JobPlace]:
	return [holder_place, presser_place] as Array[JobPlace]


## The places a miner holds (the presser's is pressed, never held).
func held_places() -> Array[JobPlace]:
	return [holder_place] as Array[JobPlace]


func window_ticks() -> float:
	return window_s * Tuning.f(&"net.tick_hz")


## Each tick, after the places: arming, the cue, H letting go, and a miss with no press.
func step(run: RunState, jobs: TwoMinerJobs) -> void:
	var h: JobPlace = holder_place
	match state:
		State.IDLE:
			if h.holder != 0:
				state = State.ARMED
				armed_at = run.tick
				step(run, jobs)
		State.ARMED:
			if h.holder == 0:
				state = State.IDLE
			elif run.tick - armed_at >= roundi(hold_to_ready_s * Tuning.f(&"net.tick_hz")):
				_cue(run, jobs)
		State.READY:
			if h.holder == 0 and ready_until < 0.0:
				ready_until = h.released_at + (Tuning.f(&"lift.alone_place_hold_s") * Tuning.f(&"net.tick_hz") if alone else 0.0)
			var why: String = _miss_due(run, jobs)
			if not why.is_empty():
				_resolve(run, jobs, false, 0, why)
		State.SPENT:
			if h.holder == 0:
				state = State.IDLE


## A fresh interact at P by `presser` (their input `c`): judged now.
func press(run: RunState, jobs: TwoMinerJobs, presser: int, slot: int, c: InputBuffer.Consumed) -> void:
	match state:
		State.IDLE, State.SPENT:
			return  # nothing to time
		State.ARMED:
			if presser != holder_place.holder:
				_resolve(run, jobs, false, presser, "early")
			return
	if presser == holder_place.holder:
		return  # one miner, one place: the holder never presses while holding
	var stamp: float = float(c.shown_tick)
	jobs.note(run, self, "press", {"miner": presser, "slot": slot, "stamp": stamp})
	var id: int = int(Variants.number(cue_ids.get(slot, -1)))
	var verdict: NowJudge.Verdict = NowJudge.Verdict.ON_TIME
	if run.now_judge != null and id >= 0:
		verdict = run.now_judge.judge(slot, id, stamp, INF if alone else window_ticks())
	elif stamp < cue_tick:
		verdict = NowJudge.Verdict.EARLY
	elif not alone and stamp - cue_tick > window_ticks():
		verdict = NowJudge.Verdict.LATE
	if verdict == NowJudge.Verdict.EARLY:
		_resolve(run, jobs, false, presser, "early")
	elif verdict == NowJudge.Verdict.LATE:
		_resolve(run, jobs, false, presser, "late")
	elif ready_until >= 0.0 and stamp > ready_until:
		_resolve(run, jobs, false, presser, "let go")
	else:
		_resolve(run, jobs, true, presser, "")


func _cue(run: RunState, jobs: TwoMinerJobs) -> void:
	state = State.READY
	cue_tick = run.tick
	ready_until = -1.0
	alone = AloneRules.is_alone(run, holder_place.holder)
	cue_type = int(Variants.number(on_cue.call(run, self))) if on_cue.is_valid() else -1
	cue_ids.clear()
	for slot: int in jobs.presser_slots(run, holder_place.holder):
		cue_ids[slot] = run.now_judge.register_cue(slot, cue_type, cue_tick) if run.now_judge != null else -1
	jobs.note(run, self, "cue", {"type": cue_type, "alone": alone})


## Why a miss is ruled now with no press, or "": for each possible presser, the latest press that
## could count (the cue as their screen showed it, plus the window, or H's letting go if sooner) is
## behind their newest input, by lift.now_late_press_grace_ticks, or they have starved (NET-03).
## lift.now_ruling_cap_s after the cue it is ruled whatever.
func _miss_due(run: RunState, jobs: TwoMinerJobs) -> String:
	var grace: float = float(Tuning.i(&"lift.now_late_press_grace_ticks"))
	var why: String = "let go" if ready_until >= 0.0 else "late"
	if alone:
		# The lone miner presses on their own timeline, within the hold-over.
		if ready_until < 0.0:
			return ""
		return why if jobs.newest_stamp_of(run, holder_place.released_by) > ready_until + grace else ""
	if run.tick - cue_tick > roundi(Tuning.f(&"lift.now_ruling_cap_s") * Tuning.f(&"net.tick_hz")):
		return why
	if run.now_judge == null:
		return why if float(run.tick) > cue_tick + window_ticks() + grace else ""
	for raw: Variant in cue_ids.keys():
		var slot: int = int(Variants.number(raw))
		if Variants.flag(run.now_judge.starved.get(slot, false)):
			continue
		var shown: float = run.now_judge.displayed_tick_of(slot, int(Variants.number(cue_ids[raw])))
		if shown < 0.0:
			return ""  # this client has not shown the cue yet
		var latest: float = shown + window_ticks()
		if ready_until >= 0.0:
			latest = minf(latest, ready_until)
		if float(Variants.number(run.now_judge.newest_stamp.get(slot, -1))) <= latest + grace:
			return ""
	return why


func _resolve(run: RunState, jobs: TwoMinerJobs, ok: bool, presser: int, why: String) -> void:
	state = State.SPENT
	for raw: Variant in cue_ids.keys():
		if run.now_judge != null:
			run.now_judge.forget(int(Variants.number(raw)), int(Variants.number(cue_ids[raw])))
	cue_ids.clear()
	if ok:
		jobs.note(run, self, "success", {"miner": presser})
		if on_success.is_valid():
			on_success.call(run, self, presser)
	else:
		jobs.note(run, self, "miss", {"miner": presser, "why": why})
		if on_miss.is_valid():
			on_miss.call(run, self, why)
