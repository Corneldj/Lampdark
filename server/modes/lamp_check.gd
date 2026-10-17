class_name LampCheck
extends SimSystem
## RSC-06 (stage RECEIVE, so it runs on while the mine is frozen; Gameplay §11.9, §6.8, §13.10, GDD
## §14.3, §15.7): Lamp Check at the pithead, from LFT-11's run_ended.
## - Opening: at the surface at once; after a wipe, rescue.wipe_lamp_check_wait_s later, while the
##   mine still runs, so the last victim's fall view (RSC-04) is sent and seen. Then the mine freezes
##   (run.frozen: every timer stands and only the network stage runs), the phase is LAMP_CHECK
##   (NET-07 serves the true view, for RSC-08), every member's voice moves to one shared channel
##   (no range, no loss, no noise), and each client is sent the hooks, the remark, the card and its
##   own miner's outcome (LAMP_CHECK open), which its roster applies (MOD-01).
## - Ending: in public, rescue.lamp_check_public_s after it opens; among friends and in Night Shift,
##   once every player still connected has pressed Ready. Then the phase is ENDED (NET-07 discards the
##   record, so every replay or clip request fails) and every client is told (LAMP_CHECK end).
## - A void public run (NET-09's voided) never sends run_ended, so it has no Lamp Check.
## - Telemetry: one run_end line as it opens (GDD §15.12).
## Its clock is its own ticks: run.tick stands still from the freeze. Not in the state hash: Lamp
## Check comes after the run's end, and nothing in the mine moves during it. Server-only.

signal opened(facts: Dictionary)
signal ended(why: String)

enum State { PLAYING, WAITING, OPEN, ENDED }

## SND-07's shared channel for everyone at the pithead.
const CHANNEL: String = "lamp_check"

var state: State = State.PLAYING
## LFT-11's outcome record, and what Lamp Check makes of it (LampCheckFacts.build).
var record: Dictionary = {}
var facts: Dictionary = {}
## The cause (FallCause) of the run's most recent fall or death, -1 while nobody has fallen.
var last_cause: int = -1
## Ticks since the run ended (its own clock), when it opened and when it ended (-1: not yet).
var clock: int = 0
var opened_at: int = -1
var ended_at: int = -1
var end_why: String = ""
## slot -> true: players who pressed Ready; slots already sent the opening.
var ready: Dictionary = {}
var told: Dictionary = {}
## MOD-03 (with DIR-06's staging): the run's staging stage for telemetry. Default: none.
var staging_of: Callable = func(_r: RunState) -> String: return "none"
var _open_due: int = -1
var _run: RunState = null
var _net: ServerNet = null


func stage() -> int:
	return StageTable.Stage.RECEIVE


## After NET-02's receive (0): this tick's Ready presses are in.
func order() -> int:
	return 20


func system_name() -> String:
	return "lamp_check"


func hashed() -> bool:
	return false


func bind(run: RunState, net: ServerNet) -> void:
	_run = run
	_net = net
	if run.outcomes != null:
		run.outcomes.run_ended.connect(func(rec: Dictionary) -> void: _on_run_ended(run, rec))
	if run.falls != null:
		run.falls.fell.connect(func(rec: Dictionary) -> void:
			if state == State.PLAYING:
				last_cause = int(Variants.number(rec.get("cause", -1))))
	if run.miner_state != null:
		run.miner_state.state_changed.connect(func(_entity: int, _old: int, new: int, cause: String) -> void:
			if state == State.PLAYING and new == MinerTransitions.Life.DEAD:
				last_cause = death_cause(cause))


## A death's cause as a FallCause: a revolver's shot is SHOT_DEAD.
static func death_cause(cause: String) -> int:
	var c: int = FallCause.from_state_cause(cause)
	if c < 0 and cause.begins_with("shot"):
		return FallCause.Cause.SHOT_DEAD
	return c


func tick(run: RunState) -> void:
	_run = run
	match state:
		State.WAITING:
			clock += 1
			if clock >= _open_due:
				_open(run)
		State.OPEN:
			clock += 1
			# The run is over: nothing consumes inputs any more.
			if _net != null:
				_net.routed.erase(Lane.Id.INPUTS)
			_take_ready()
			_tell_new_members(run)
			var why: String = _due_to_end(run)
			if not why.is_empty():
				_end(run, why)


func _on_run_ended(run: RunState, rec: Dictionary) -> void:
	if state != State.PLAYING:
		return
	record = rec
	state = State.WAITING
	clock = 0
	var wait_s: float = Variants.number(rec.get("lamp_check_wait_s", 0.0)) if Variants.flag(rec.get("wipe", false)) else 0.0
	_open_due = roundi(wait_s * Tuning.f(&"net.tick_hz"))
	Log.info("lamp check: the run has ended (%s); it opens in %.1f s" % ["a wipe" if Variants.flag(rec.get("wipe", false)) else "the surface", wait_s])
	if _open_due <= 0:
		_open(run)


func _open(run: RunState) -> void:
	state = State.OPEN
	opened_at = clock
	run.frozen = true
	run.set_phase(RunState.Phase.LAMP_CHECK)
	facts = LampCheckFacts.build(record, last_cause)
	if run.voice != null:
		# The pithead's channel is everyone's only route: no dream channel, no phone line.
		for name: Variant in run.voice.channels.keys():
			if str(name) != CHANNEL:
				for raw: Variant in Variants.dict(run.voice.channels[name]).keys():
					run.voice.channel_leave(str(name), int(Variants.number(raw)))
		for raw: Variant in run.voice.direct.keys():
			for other: Variant in Variants.dict(run.voice.direct[raw]).keys():
				run.voice.close_direct(int(Variants.number(raw)), int(Variants.number(other)))
	_tell_new_members(run)
	_telemetry(run)
	Log.info("lamp check: open, %s (%d hooks, remark %s)" % [str(facts["card"]).replace("\n", " / "), Variants.array(facts["hooks"]).size(),
		str(facts["remark"]) if not str(facts["remark"]).is_empty() else "none"])
	opened.emit(facts)


## Each member not yet told: the opening, with its own miner's outcome, and onto the channel (a
## player who rejoins during Lamp Check gets it then).
func _tell_new_members(run: RunState) -> void:
	if _net == null:
		return
	for session: Sessions.Session in _net.sessions.welcomed():
		if told.has(session.slot):
			continue
		told[session.slot] = true
		if run.voice != null:
			# Up on the surface nobody's voice is cut, dragged or coming round (and none makes noise).
			run.voice.set_route(session.slot, VoiceRoutes.Route.NORMAL)
			run.voice.channel_join(CHANNEL, session.slot)
		_net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.LAMP_CHECK, opening_for(run, session.slot)))


## The opening as a slot's client is sent it (NET-08's audit checks it byte for byte).
func opening_for(run: RunState, slot: int) -> PackedByteArray:
	return LampCheckWire.open(Variants.array(facts.get("hooks", [])), str(facts.get("remark", "")), str(facts.get("card", "")),
		Variants.flag(facts.get("wipe", false)), own_outcome(run, slot), run.header.run_uuid, _end_rule(run))


## The outcome of the miner a slot plays (MNR-03 keeps every miner's slot, the dead's too):
## escaped, dead or left_below; "" for none (no miner, or one the record leaves out, as an absent
## player's).
func own_outcome(run: RunState, slot: int) -> String:
	if run.miner_state == null:
		return ""
	for raw: Variant in Variants.array(record.get("miners", [])):
		var m: Dictionary = Variants.dict(raw)
		var miner: MinerStateSystem.Miner = run.miner_state.miner(int(Variants.number(m.get("miner_id", 0))))
		if miner != null and miner.slot == slot:
			return LampCheckFacts.outcome_name(m)
	return ""


## {public_s} in public (the pithead empties then); {} among friends and in Night Shift (Ready).
func _end_rule(run: RunState) -> Dictionary:
	if run.header.mode == ServerConfig.Mode.PUBLIC:
		return {"public_s": Tuning.f(&"rescue.lamp_check_public_s")}
	return {}


func _take_ready() -> void:
	if _net == null:
		return
	var control: Array = Variants.array(_net.routed.get(Lane.Id.CONTROL, []))
	var rest: Array = []
	for raw: Variant in control:
		var m: Array = raw
		if int(Variants.number(m[1])) != Protocol.Msg.LAMP_CHECK:
			rest.append(m)
			continue
		var payload: PackedByteArray = m[2]
		var said: Dictionary = LampCheckWire.read(payload)
		if str(said.get("kind", "")) == LampCheckWire.READY:
			ready[int(Variants.number(m[0]))] = true
	if not control.is_empty():
		_net.routed[Lane.Id.CONTROL] = rest


## Why Lamp Check ends now, or "": public on its budget; otherwise when every player still connected
## is ready (or none is left).
func _due_to_end(run: RunState) -> String:
	if run.header.mode == ServerConfig.Mode.PUBLIC:
		if clock - opened_at >= roundi(Tuning.f(&"rescue.lamp_check_public_s") * Tuning.f(&"net.tick_hz")):
			return "time"
		return ""
	if _net == null:
		return ""
	for session: Sessions.Session in _net.sessions.welcomed():
		if session.seat == Protocol.Seat.PLAYER and not ready.has(session.slot):
			return ""
	return "ready"


## Ends Lamp Check now (MOD-03's host, when the server knows who that is): `why` names it.
func end_now(run: RunState, why: String) -> void:
	if state == State.OPEN:
		_end(run, why)


func _end(run: RunState, why: String) -> void:
	state = State.ENDED
	ended_at = clock
	end_why = why
	run.set_phase(RunState.Phase.ENDED)
	if _net != null:
		var payload: PackedByteArray = LampCheckWire.end(why)
		for session: Sessions.Session in _net.sessions.welcomed():
			_net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.LAMP_CHECK, payload))
	Log.info("lamp check: ended (%s) after %.1f s" % [why, (clock - opened_at) / Tuning.f(&"net.tick_hz")])
	ended.emit(why)


## GDD §15.12: escape, wipe and Left Below rates by list and crew, and the run's length.
func _telemetry(run: RunState) -> void:
	var escaped: int = 0
	var left_below: int = 0
	var dead: int = 0
	for raw: Variant in Variants.array(record.get("miners", [])):
		match LampCheckFacts.outcome_name(Variants.dict(raw)):
			"escaped":
				escaped += 1
			"dead":
				dead += 1
			_:
				left_below += 1
	var humans: int = Variants.array(record.get("miners", [])).size()
	var hands: int = 0
	if run.registry != null and run.crew != null:
		for raw: Variant in Array(run.registry.ids()):
			var id: int = int(Variants.number(raw))
			var e: SimEntity = run.registry.get_entity(id)
			if e != null and e.kind == WorldIds.EntityKind.MINER and Variants.flag(run.crew.is_hired_hand.call(id)):
				hands += 1
	var list: String = str(RepairList.Kind.find_key(run.repair.list.kind)).to_lower() if run.repair != null and run.repair.list != null else "none"
	Log.info("telemetry run_end list=%s humans=%d hands=%d escaped=%d left_below=%d dead=%d wipe=%s run_length_s=%.1f staging_stage=%s" % [
		list, humans, hands, escaped, left_below, dead, str(Variants.flag(record.get("wipe", false))).to_lower(),
		Variants.number(record.get("time_below_s", 0.0)), str(staging_of.call(run))])
