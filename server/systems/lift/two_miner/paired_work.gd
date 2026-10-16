class_name PairedWork
extends RefCounted
## LFT-04: shared work for two (Gameplay §3.3): the drum gear fitted and the cage levered free, 10 s
## each (LFT-07). It progresses only while two different miners hold its places A and B; alone
## (AloneRules: solo or a lone human) one miner holding either place progresses at
## 1 / lift.alone_work_multiplier the rate, so the work takes twice as long. In a crew that is not
## alone one miner holding makes no progress. Progress is kept when a place is let go
## (lift.paired_work_keeps_progress, Proposed); a fall, a grab or a drop lets go at once. No window:
## two at the gear time nothing with 'Now!' (Proposed). Server-only: progress never reaches a client.

var name: String = ""
var place_a: JobPlace = JobPlace.new()
var place_b: JobPlace = JobPlace.new()
var work_s: float = 10.0
## (run, holders: Array[int]) -> bool: the job's own needs (its tools in hand, its parts in place).
var requires: Callable = Callable()
## (run, job, fraction: float) -> void, each tick it progresses.
var on_progress: Callable = Callable()
## (run, job) -> void, once.
var on_complete: Callable = Callable()
## Work done, in ticks of two-miner work.
var progress: float = 0.0
var done: bool = false


## {anchor_a, anchor_b, work_s, requires, on_progress, on_complete, name}
static func make(cfg: Dictionary) -> PairedWork:
	var j: PairedWork = PairedWork.new()
	j.name = str(cfg.get("name", "paired_work"))
	var a: Vector2 = cfg["anchor_a"]
	var b: Vector2 = cfg["anchor_b"]
	j.place_a = JobPlace.at(a)
	j.place_b = JobPlace.at(b)
	j.work_s = float(Variants.number(cfg.get("work_s", 10.0)))
	j.requires = cfg.get("requires", Callable())
	j.on_progress = cfg.get("on_progress", Callable())
	j.on_complete = cfg.get("on_complete", Callable())
	return j


func places() -> Array[JobPlace]:
	return [place_a, place_b] as Array[JobPlace]


func held_places() -> Array[JobPlace]:
	return places()


func work_ticks() -> float:
	return work_s * Tuning.f(&"net.tick_hz")


## The fraction done, 0 to 1.
func fraction() -> float:
	return clampf(progress / maxf(1.0, work_ticks()), 0.0, 1.0)


func step(run: RunState, jobs: TwoMinerJobs) -> void:
	if done:
		return
	var holders: Array[int] = []
	for p: JobPlace in places():
		if p.holder != 0 and not holders.has(p.holder):
			holders.append(p.holder)
	var rate: float = 0.0
	if holders.size() >= 2:
		rate = 1.0
	elif holders.size() == 1 and AloneRules.is_alone(run, holders[0]):
		rate = 1.0 / maxf(1.0, Tuning.f(&"lift.alone_work_multiplier"))
	if rate > 0.0 and requires.is_valid() and not Variants.flag(requires.call(run, holders)):
		rate = 0.0
	if rate <= 0.0:
		if not Tuning.b(&"lift.paired_work_keeps_progress"):
			progress = 0.0
		return
	progress += rate
	if on_progress.is_valid():
		on_progress.call(run, self, fraction())
	if progress >= work_ticks() - 1e-6:
		done = true
		jobs.note(run, self, "complete", {"miners": holders})
		if on_complete.is_valid():
			on_complete.call(run, self)
