class_name RepairList
extends RefCounted
## LFT-03: the run's repair list (Gameplay §3.3, §A.6), drawn once from the run seed by one pure
## function, which GEN-08's run plan reads and the Manual prints. Power, Fuel and Start are always on
## it (lift.list_always_jobs), Start always last; Standard adds lift.list_standard_pool_jobs and Full
## lift.list_full_pool_jobs from the pool of six, picked uniformly without replacement (Proposed: the
## design gives no weights), minus lift.solo_excluded_jobs (the drum gear) for a solo list. Fuel needs
## lift.list_*_cans cans; the cage is wedged only when Free the cage is drawn. Full is cut 11's: while
## lift.full_list_enabled is false it cannot be drawn. Server-only: a client is sent only the kind,
## the jobs and the can count (RepairListState), never the seed or anything the plan does with it.

enum Kind { SHORT = 0, STANDARD = 1, FULL = 2 }


var kind: Kind = Kind.SHORT
## The run's jobs, in Company order, Start last.
var jobs: Array[StringName] = []
var cans_required: int = 0
var cage_wedged: bool = false


## The draw from a stream (FND-06's lift.repair_list domain). Null, with an error, for Full while
## cut 11 holds.
static func draw(rng: LbRng, of_kind: Kind, solo: bool) -> RepairList:
	if of_kind == Kind.FULL and not Tuning.b(&"lift.full_list_enabled"):
		push_error("RepairList: the Full list is cut (lift.full_list_enabled is false)")
		return null
	var pool: Array[StringName] = []
	var excluded: Array[String] = []
	if solo:
		excluded = Tuning.list_s(&"lift.solo_excluded_jobs")
	for job: StringName in RepairJobs.POOL:
		if not excluded.has(String(job)):
			pool.append(job)
	var n: int = mini(pool_jobs(of_kind), pool.size())
	# A partial Fisher-Yates: the first n of a uniform shuffle.
	for i: int in n:
		var j: int = rng.range(i, pool.size() - 1)
		var swap: StringName = pool[i]
		pool[i] = pool[j]
		pool[j] = swap
	var on: Dictionary = {}
	for job: String in Tuning.list_s(&"lift.list_always_jobs"):
		on[StringName(job)] = true
	for i: int in n:
		on[pool[i]] = true
	var l: RepairList = RepairList.new()
	l.kind = of_kind
	for job: StringName in RepairJobs.COMPANY_ORDER:
		if on.has(job):
			l.jobs.append(job)
	l.cans_required = cans_for(of_kind)
	l.cage_wedged = on.has(&"free_cage")
	return l


## The run's list: the draw on the run seed's lift.repair_list stream.
static func for_run(run_seed: int, of_kind: Kind, solo: bool) -> RepairList:
	return draw(LbRng.from_seed(LbHash.sub_seed(run_seed, HashDomain.LIFT_REPAIR_LIST, PackedInt64Array(), 0)), of_kind, solo)


static func pool_jobs(of_kind: Kind) -> int:
	match of_kind:
		Kind.STANDARD:
			return Tuning.i(&"lift.list_standard_pool_jobs")
		Kind.FULL:
			return Tuning.i(&"lift.list_full_pool_jobs")
	return Tuning.i(&"lift.list_short_pool_jobs")


static func cans_for(of_kind: Kind) -> int:
	match of_kind:
		Kind.STANDARD:
			return Tuning.i(&"lift.list_standard_cans")
		Kind.FULL:
			return Tuning.i(&"lift.list_full_cans")
	return Tuning.i(&"lift.list_short_cans")


func has(job: StringName) -> bool:
	return jobs.has(job)


func to_dict() -> Dictionary:
	var names: Array = []
	for job: StringName in jobs:
		names.append(String(job))
	return {"kind": kind, "jobs": names, "cans": cans_required, "cage_wedged": cage_wedged}


static func from_dict(d: Dictionary) -> RepairList:
	if d.is_empty():
		return null
	var l: RepairList = RepairList.new()
	l.kind = clampi(int(Variants.number(d.get("kind", 0))), 0, 2) as Kind
	for raw: Variant in Variants.array(d.get("jobs", [])):
		l.jobs.append(StringName(str(raw)))
	l.cans_required = int(Variants.number(d.get("cans", 0)))
	l.cage_wedged = Variants.flag(d.get("cage_wedged", false))
	return l
