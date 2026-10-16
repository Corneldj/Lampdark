class_name SelfRevive
extends SimSystem
## RSC-09 (stage FALLS, after the Dark; Gameplay §11.11, §A.8): a miner with no conscious human
## teammate gets one self-revive a run (rescue.self_revives_per_run): it arms when they fall alone
## (AloneRules.alone_at_fall) with one unspent, and rescue.self_revive_delay_s later they come round
## fully where they lie, Hurt (MNR-03's revive with how SELF, which also applies rock-touched after a
## pin). Proposed: a miner who fell while another human was still conscious never arms one later;
## the count does not run while a drag holds the body and starts in full when it ends; a second
## conscious human appearing cancels it, unspent; a kit's revive cancels it, unspent; death ends it.
##
## A fall alone with the self-revive spent is the solo wipe: `wiped` fires that tick, and
## `deferral_active()` (LFT-11's hook) is true while any self-revive is pending. Server-only.

signal self_revived(miner: int, tick: int)
signal wiped(miner: int, tick: int)

class Pending:
	extends RefCounted
	var miner: int = 0
	var ticks: int = 0
	var left: int = 0
	var waiting: bool = false
	var cause: String = ""
	var fell_tick: int = 0

## miner -> Pending
var pending: Dictionary = {}
## miner -> self-revives spent this run
var spent: Dictionary = {}
## Every self-revive and wipe: {tick, miner, what (self_revived | cancelled | wiped), why}.
var events: Array[Dictionary] = []
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.FALLS


func order() -> int:
	return 50


func system_name() -> String:
	return "self_revive"


func bind(run: RunState) -> void:
	_run = run
	if run.falls != null:
		run.falls.fell.connect(func(record: Dictionary) -> void: _on_fell(run, record))
	if run.miner_state != null:
		run.miner_state.state_changed.connect(func(entity: int, _old: int, new: int, cause: String) -> void:
			if not pending.has(entity):
				return
			if new == MinerTransitions.Life.DEAD:
				_cancel(run, entity, "died")
			elif new < MinerTransitions.Life.UNCONSCIOUS and not cause.ends_with(":self"):
				_cancel(run, entity, "revived by %s" % cause))


## Whether `miner` still has a self-revive to spend this run.
func self_revive_available(miner: int) -> bool:
	return int(Variants.number(spent.get(miner, 0))) < roundi(Tuning.f(&"rescue.self_revives_per_run"))


func self_revive_pending(miner: int) -> bool:
	return pending.has(miner)


## LFT-11's hook: true while any self-revive is pending (a wipe waits for it).
func deferral_active() -> bool:
	return not pending.is_empty()


## For the own status (StatusWire): {counting, waiting, due_tick, ticks}.
func status_of(run: RunState, miner: int) -> Dictionary:
	var p: Pending = pending.get(miner, null)
	if p == null:
		return {}
	return {"counting": not p.waiting, "waiting": p.waiting, "due_tick": run.tick + p.left, "ticks": p.ticks}


func _on_fell(run: RunState, record: Dictionary) -> void:
	var miner: int = int(Variants.number(record.get("miner_id", 0)))
	if miner == 0 or Variants.flag(record.get("is_hand", false)) or pending.has(miner):
		return
	if not AloneRules.alone_at_fall(run, miner):
		return
	if not self_revive_available(miner):
		events.append({"tick": run.tick, "miner": miner, "what": "wiped", "why": "fell alone with the self-revive spent"})
		Log.info("telemetry solo_wipe miner=%d tick=%d" % [miner, run.tick])
		wiped.emit(miner, run.tick)
		return
	var p: Pending = Pending.new()
	p.miner = miner
	p.ticks = maxi(1, roundi(Tuning.f(&"rescue.self_revive_delay_s") * Tuning.f(&"net.tick_hz")))
	p.left = p.ticks
	p.cause = str(record.get("cause_name", ""))
	p.fell_tick = run.tick
	pending[miner] = p


func tick(run: RunState) -> void:
	_run = run
	var ids: Array = pending.keys()
	ids.sort()
	for raw: Variant in ids:
		var p: Pending = pending.get(raw, null)
		if p == null:
			continue
		if not _still_alone(run, p.miner):
			_cancel(run, p.miner, "a conscious human teammate")
			continue
		var g: GrabHold = run.holds.grab_of(p.miner) if run.holds != null else null
		if g != null and g.is_live():
			# A drag holds the body: the count waits, and starts in full when it ends (Proposed).
			p.waiting = true
			p.left = p.ticks
			continue
		p.waiting = false
		p.left -= 1
		if p.left <= 0:
			_revive(run, p)


## Normal rules are back once another human is conscious (revived or rejoined).
static func _still_alone(run: RunState, miner: int) -> bool:
	if run.crew == null:
		return true
	if AloneRules.is_solo(run.crew):
		return true
	for e: int in run.crew.humans(run):
		if e != miner and CrewCensus.is_conscious(run, e):
			return false
	return true


func _revive(run: RunState, p: Pending) -> void:
	pending.erase(p.miner)
	spent[p.miner] = int(Variants.number(spent.get(p.miner, 0))) + 1
	run.miner_state.revive(p.miner, &"self")
	events.append({"tick": run.tick, "miner": p.miner, "what": "self_revived", "why": p.cause})
	var ring: int = Depth.ring_for_miner(run, p.miner) if run.registry.get_entity(p.miner) != null else 0
	Log.info("telemetry self_revive ring=%d cause=%s" % [ring, p.cause])
	self_revived.emit(p.miner, run.tick)


func _cancel(run: RunState, miner: int, why: String) -> void:
	if pending.erase(miner):
		events.append({"tick": run.tick, "miner": miner, "what": "cancelled", "why": why})


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = pending.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var p: Pending = pending[raw]
		writer.put_i64(p.miner)
		writer.put_i64(p.left)
		writer.put_i64(1 if p.waiting else 0)
	var used: Array = spent.keys()
	used.sort()
	writer.put_i64(used.size())
	for raw: Variant in used:
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(int(Variants.number(spent[raw])))


## NET-09: the counts under way and the self-revives spent.
func save_state() -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in pending.keys():
		var p: Pending = pending[raw]
		out[raw] = {"ticks": p.ticks, "left": p.left, "waiting": p.waiting, "cause": p.cause, "fell_tick": p.fell_tick}
	return {"pending": out, "spent": spent.duplicate()}


func load_state(_r: RunState, state: Dictionary) -> void:
	pending.clear()
	var saved: Dictionary = Variants.dict(state.get("pending", {}))
	for raw: Variant in saved.keys():
		var d: Dictionary = saved[raw]
		var p: Pending = Pending.new()
		p.miner = int(Variants.number(raw))
		p.ticks = int(Variants.number(d["ticks"]))
		p.left = int(Variants.number(d["left"]))
		p.waiting = Variants.flag(d["waiting"])
		p.cause = str(d.get("cause", ""))
		p.fell_tick = int(Variants.number(d.get("fell_tick", 0)))
		pending[p.miner] = p
	spent.clear()
	var used: Dictionary = Variants.dict(state.get("spent", {}))
	for raw: Variant in used.keys():
		spent[int(Variants.number(raw))] = int(Variants.number(used[raw]))
