class_name RepairListState
extends SimSystem
## LFT-03 (stage WORLD): the run's repair list and which jobs are done (Gameplay §3.3). The list is
## drawn once at the run's start (RepairList.for_run; MOD-03 chooses the kind and the solo rule, by
## mode until it lands: Short in public and Night Shift, Standard among friends) and kept with
## every snapshot. LFT-05 to LFT-08 call mark_done(); the one prerequisite is Start's: every other
## job on the list done first, Power included (the winder's brake releases electrically). Server
## truth: the done flags never reach a client, and the Manual never ticks itself.
##
## A client is sent the list once, the first time its miner opens the Manual (Protocol.Msg.MANUAL,
## control lane, RepairJobs' wire form: the kind, the can count and the jobs). Server-only.

signal job_done(job: StringName)

var list: RepairList = null
## job -> the tick it was marked done.
var done: Dictionary = {}
## Peers sent the list (a new connection is sent it again on its next opening).
var _told: Dictionary = {}
var _net: ServerNet = null


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 30


func system_name() -> String:
	return "repair_list"


func bind(run: RunState, net: ServerNet) -> void:
	_net = net
	if list == null:
		set_list(RepairList.for_run(run.header.run_seed, default_kind(run.header.mode), run.header.mode == ServerConfig.Mode.NIGHTSHIFT))


## Until MOD-03 chooses: Short in public and in Night Shift, Standard among friends.
static func default_kind(mode: ServerConfig.Mode) -> RepairList.Kind:
	return RepairList.Kind.STANDARD if mode == ServerConfig.Mode.FRIENDS else RepairList.Kind.SHORT


## MOD-03's choice (or a test's): the run's list, nothing done yet.
func set_list(l: RepairList) -> void:
	list = l
	done.clear()
	_told.clear()


func is_on_list(job: StringName) -> bool:
	return list != null and list.has(job)


func is_done(job: StringName) -> bool:
	return done.has(job)


## Every job on the list but Start is done.
func can_start() -> bool:
	if list == null:
		return false
	for job: StringName in list.jobs:
		if job != &"start" and not done.has(job):
			return false
	return true


## A job ticket's work is finished. False for a job not on the list, already done, or Start before
## everything else.
func mark_done(run: RunState, job: StringName) -> bool:
	if not is_on_list(job) or done.has(job) or (job == &"start" and not can_start()):
		return false
	done[job] = run.tick
	Log.info("repair job done: %s at tick %d" % [job, run.tick])
	job_done.emit(job)
	return true


func tick(run: RunState) -> void:
	if _net == null or list == null or run.closeups == null or run.movement == null:
		return
	for session: Sessions.Session in _net.sessions.welcomed():
		if _told.get(session.slot, -1) == session.peer:
			continue
		var m: MovementSystem.Miner = run.movement.miner(session.slot)
		if m == null or run.closeups.kind_of(m.entity_id) != CloseupKind.Kind.MANUAL:
			continue
		_told[session.slot] = session.peer
		var payload: PackedByteArray = RepairJobs.encode(list.kind, list.cans_required, list.jobs)
		_net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.MANUAL, payload))


## NET-09: the list and what is done, with every snapshot (the list holds through knock-offs).
func save_state() -> Dictionary:
	var d: Dictionary = {}
	for raw: Variant in done.keys():
		d[str(raw)] = done[raw]
	return {"list": list.to_dict() if list != null else {}, "done": d}


func load_state(_r: RunState, state: Dictionary) -> void:
	var l: RepairList = RepairList.from_dict(Variants.dict(state.get("list", {})))
	if l != null:
		list = l
	done.clear()
	var d: Dictionary = Variants.dict(state.get("done", {}))
	for raw: Variant in d.keys():
		done[StringName(str(raw))] = int(Variants.number(d[raw]))
	_told.clear()


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(list.kind if list != null else -1)
	for job: StringName in RepairJobs.COMPANY_ORDER:
		writer.put_bool(list != null and list.has(job))
		writer.put_bool(done.has(job))
