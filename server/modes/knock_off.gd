class_name KnockOff
extends SimSystem
## MOD-05 (Gameplay §13.11, §3.5, §12.6, A.10; GDD §14.3, §15.10): knocking off. In a friends lobby or
## Night Shift the host may save and end the session whenever every conscious miner (a player's,
## whoever drives it) is inside base camp and every gate is shut; filler Hands never block it
## (Proposed), and neither do the unconscious and the dead anywhere. `available` is that test at the
## end of every tick, and only the host's client hears it (the host link: it tells nothing a player
## in base camp cannot see). The flow, on the host's word: the condition again that tick (else
## nothing happens), the run frozen (NET-01: every timer and tick stops, the network pumps on),
## NET-09's knock-off save written and sent to every member, and once every member has acknowledged
## it, or after modes.knock_off_ack_timeout_s, the session ends: everyone to the Pithead, with no Lamp
## Check (it waits for the run's end). Never in public. Server-only.

signal availability_changed(on: bool)
## The save is out and acknowledged (or timed out): `acked` the slots that confirmed it.
signal finished(acked: Array[int], timed_out: bool)

var available: bool = false
## Why it is not available ("" when it is): for logs and the refusal.
var why_not: String = ""
## The flow under way: the save's sequence number, and when it gives up waiting (µs).
var flowing: bool = false
var awaiting_seq: int = -1
var deadline_usec: int = -1
## Every request: {tick, by, refused}.
var requests: Array[Dictionary] = []
## A request made during a tick (FND-08's console): taken at this tick's end, so the save is of a
## whole tick. The host link's comes between ticks and goes at once.
var deferred_by: String = ""
var last_refusal: String = ""
var _done: bool = false


func stage() -> int:
	return StageTable.Stage.RECORD


## After NET-09's saves (60), so a request made during the tick saves the whole tick.
func order() -> int:
	return 70


func system_name() -> String:
	return "knock_off"


func hashed() -> bool:
	return false


func tick(run: RunState) -> void:
	var why: String = refusal(run)
	var on: bool = why.is_empty()
	why_not = why
	if on != available:
		available = on
		availability_changed.emit(on)
	if not deferred_by.is_empty():
		var by: String = deferred_by
		deferred_by = ""
		last_refusal = request(run, by, Transport.now_usec())


## Why a knock-off cannot happen now ("" when it can).
static func refusal(run: RunState) -> String:
	if run.header.mode == ServerConfig.Mode.PUBLIC:
		return "A public run is never saved."
	if run.phase != RunState.Phase.PLAYING:
		return "The run is not under way."
	if run.saves == null or not run.saves.enabled or run.saves.closed:
		return "This run cannot be saved."
	if run.base_camp == null:
		return "There is no base camp to knock off in."
	if not run.base_camp.is_sealed():
		return "Every gate must be shut."
	for e: int in _conscious_miners(run):
		var at: SimEntity = run.registry.get_entity(e)
		if not run.base_camp.inside_tiles.has(Vector2i(floori(at.position.x), floori(at.position.y))):
			return "Everyone must be inside base camp."
	if not Snapshot.may_capture(run):
		return "Not while someone is held."
	return ""


## Every conscious miner but a filler Hand's own (players' miners, whoever drives them).
static func _conscious_miners(run: RunState) -> Array[int]:
	var out: Array[int] = []
	for id: int in run.registry.ids():
		var e: SimEntity = run.registry.get_entity(id)
		if e.kind != WorldIds.EntityKind.MINER:
			continue
		if run.crew != null and Variants.flag(run.crew.is_hired_hand.call(id)):
			continue
		if run.miner_state != null and run.miner_state.miner(id) != null and run.miner_state.life(id) >= MinerTransitions.Life.UNCONSCIOUS:
			continue
		out.append(id)
	return out


## The host's word (`by`: who asked). "" when the knock-off begins, else why not (nothing happens).
func request(run: RunState, by: String, now_usec: int) -> String:
	var why: String = refusal(run) if not flowing else "A knock-off is under way."
	requests.append({"tick": run.tick, "by": by, "refused": why})
	if not why.is_empty():
		Log.info("knock off refused (%s): %s" % [by, why])
		return why
	run.frozen = true
	var row: Dictionary = run.saves.knockoff(run)
	flowing = true
	_done = false
	awaiting_seq = int(Variants.number(row.get("seq", -1)))
	deadline_usec = now_usec + roundi(Tuning.f(&"modes.knock_off_ack_timeout_s") * 1000000.0)
	Log.info("knocking off at tick %d (%s): save %d sent, waiting for every member" % [run.tick, by, awaiting_seq])
	return ""


## While the flow waits (every frame, after the frozen network pump): every member's acknowledgement
## of the save, or the timeout. Returns true once, when the session may end.
func poll(run: RunState, members: Array[int], now_usec: int) -> bool:
	if not flowing or _done:
		return false
	run.saves.take_acks()
	var acked: Array[int] = []
	for slot: int in members:
		if int(Variants.number(run.saves.acks.get(slot, -1))) >= awaiting_seq:
			acked.append(slot)
	var timed_out: bool = now_usec >= deadline_usec
	if acked.size() < members.size() and not timed_out:
		return false
	_done = true
	Log.info("knocked off: %d of %d members hold the save%s" % [acked.size(), members.size(), " (timed out)" if timed_out else ""])
	finished.emit(acked, timed_out)
	return true
