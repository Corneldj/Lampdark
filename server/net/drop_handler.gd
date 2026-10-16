class_name DropHandler
extends SimSystem
## NET-11 (stage INPUTS, after the input service; Gameplay §13.11, §13.9): a drop never ends a run
## or changes an outcome already under way. NET-02's drop is handled by the miner's state at that
## moment, after NET-03 has stopped it and cancelled any timed action at the 200 ms cut-off,
## nothing spent:
##
## - a conscious miner: a carried load is set down first, without a knock (MNR-13); a seated
##   operator stands up from the board; then a Hired Hand takes it where it stands, its lamp turned
##   down on the belt (MOD-08's `take_over`);
## - Caught or Grabbed: the trap or the grab runs on, stoppable only by a teammate;
## - unconscious or dead: nothing changes (rejoining, the player returns to the Dark, RSC-04).
##
## The seat is reserved (SeatTable): the player retakes it on rejoining, any time among friends,
## within net.public_retake_window_s in public, and MOD-08 hands the miner back as it is now, the
## lamp still on the belt until they take it in hand. `remove_player` is MOD-11's kick and
## ejection. Until MOD-08 lands, a stand-in takes over: the miner stands where it is, marked
## Hand-driven (so the Hands' rules apply), its lamp hooked and turned down, a drawn revolver back
## in its slot. Server-only.

enum Takeover {
	DROPPED = 0,
	KICKED = 1,
	EJECTED = 2,
}

## MOD-08: (run, miner, mode) -> void.
var take_over: Callable = func(r: RunState, miner: int, mode: Takeover) -> void: _stub_take_over(r, miner, mode)
## MOD-08: (run, miner) -> void.
var hand_back: Callable = func(r: RunState, miner: int) -> void: _stub_hand_back(r, miner)
## The stand-in's Hand-driven miners (MOD-08 replaces it).
var hand_driven: Dictionary = {}
## Every drop: {tick, slot, miner, life, what}.
var drops: Array[Dictionary] = []
## Every retake: {tick, slot, miner, identity}.
var retakes: Array[Dictionary] = []
var _net: ServerNet = null
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.INPUTS


func order() -> int:
	return 5


func system_name() -> String:
	return "drop_handler"


func bind(run: RunState, net: ServerNet) -> void:
	_run = run
	_net = net
	net.rejoined.connect(func(slot: int, identity: String) -> void: _on_rejoined(run, slot, identity))
	if run.crew != null:
		var before: Callable = run.crew.is_hand_driven
		run.crew.is_hand_driven = func(e: int) -> bool: return hand_driven.has(e) or Variants.flag(before.call(e))


func tick(run: RunState) -> void:
	_run = run
	for slot: int in _net.dropped_slots:
		on_drop(run, slot)
	_net.seats.expire(run.tick, _public(run))


static func _public(run: RunState) -> bool:
	return run.header.mode == ServerConfig.Mode.PUBLIC


## The drop of `slot`'s player, by its miner's state now.
func on_drop(run: RunState, slot: int) -> void:
	var m: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
	var miner: int = m.entity_id if m != null else 0
	_net.seats.on_dropped(slot, miner, run.tick)
	if miner == 0 or run.miner_state == null or run.miner_state.miner(miner) == null:
		drops.append({"tick": run.tick, "slot": slot, "miner": miner, "life": -1, "what": "no miner"})
		return
	var life: int = run.miner_state.life(miner)
	var what: String = ""
	# A timed action in progress is cancelled, nothing spent (NET-03's cut-off: one that needs no
	# held input, a chalk mark, would otherwise run on).
	if run.inventory != null and run.inventory.actions.has(miner):
		var a: TimedAction = run.inventory.actions[miner]
		run.inventory.actions.erase(miner)
		a.cancel(TimedAction.STARVED)
		what += "action cancelled; "
	if run.carry != null and run.carry.is_carrying(miner):
		run.carry.set_down(run, miner, FiremanCarry.DISCONNECTED)
		what += "set down; "
	# MNR-14: a load's end or a tub is let go at once, with no knock.
	if run.loads != null and run.loads.carrying(miner):
		run.loads.set_down(run, miner, LoadCarry.DISCONNECTED)
		what += "load set down; "
	if run.tubs != null and run.tubs.holding(miner):
		run.tubs.let_go(run, miner, TubRails.DISCONNECTED)
		what += "tub let go; "
	match life:
		MinerTransitions.Life.UPRIGHT:
			if run.closeups != null and run.closeups.operator() == miner:
				run.closeups.close(miner, "dropped")
				what += "stood up from the board; "
			take_over.call(run, miner, Takeover.DROPPED)
			what += "a Hand takes it"
		MinerTransitions.Life.CAUGHT, MinerTransitions.Life.GRABBED:
			what += "the hold runs on"
		_:
			what += "nothing changes"
	drops.append({"tick": run.tick, "slot": slot, "miner": miner, "life": life, "what": what})


func _on_rejoined(run: RunState, slot: int, identity: String) -> void:
	var seat: SeatTable.Seat = _net.seats.seat_of(identity)
	if seat == null or seat.miner == 0:
		return
	hand_back.call(run, seat.miner)
	retakes.append({"tick": run.tick, "slot": slot, "miner": seat.miner, "identity": identity})


## MOD-11's kick or ejection: the player is sent to the Pithead (Reject.REMOVED, refused again
## on any later handshake) and a Hand takes the miner in `mode`.
func remove_player(run: RunState, identity: String, reason: String, mode: Takeover) -> bool:
	var seat: SeatTable.Seat = _net.seats.seat_of(identity)
	if seat == null:
		return false
	var slot: int = seat.slot
	var m: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
	var miner: int = m.entity_id if m != null else seat.miner
	seat.miner = miner
	_net.seats.on_removed(identity, run.tick, reason)
	_net.remove(slot, Protocol.Reject.REMOVED)
	if miner != 0 and run.miner_state != null and run.miner_state.life(miner) == MinerTransitions.Life.UPRIGHT:
		take_over.call(run, miner, mode)
	return true


func _stub_take_over(run: RunState, miner: int, _mode: Takeover) -> void:
	hand_driven[miner] = true
	if run.inventory == null:
		return
	var h: HandsAndBelt = run.inventory.hands_of(miner)
	# A drawn revolver goes back in its slot at once (MNR-16): a Hand never holds it.
	if h.free_hand != null and h.free_hand.kind == ItemKinds.Kind.REVOLVER:
		for i: int in h.slots.size():
			if h.slots[i] == null:
				h.slots[i] = h.free_hand
				h.free_hand = null
				break
	# Its lamp turned down on the belt.
	if run.lamps != null:
		var l: GauzeLamp = run.lamps.lamp_in_hand(miner)
		if l != null:
			for _i: int in 2:
				run.lamps.step_wick(run, l, -1, "a Hand took over")
			run.lamps.hook(run, l)
	run.inventory.changed.emit(miner)


func _stub_hand_back(_r: RunState, miner: int) -> void:
	hand_driven.erase(miner)
