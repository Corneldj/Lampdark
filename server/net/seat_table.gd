class_name SeatTable
extends RefCounted
## NET-11 (Gameplay §13.11, GDD §15.10): who holds which place in the run. A player's identity
## (the SteamID, or the dev name) maps to its slot and miner. A dropped player's seat is reserved:
## its slot is never given to anyone else, and the player retakes it on rejoining (by identity, or
## the session token): any time among friends and in Night Shift, within net.public_retake_window_s
## in public. After that the Hand keeps the place, and the miner's outcome is still the player's
## (RSC-06); MOD-09 never offers it. A removed player (MOD-11's kicks and ejections) is refused with
## Reject.REMOVED. Server-only.

enum State {
	SEATED = 0,
	RESERVED = 1,
	HAND_KEEPS = 2,
	REMOVED = 3,
}


class Seat:
	extends RefCounted
	var identity: String = ""
	var slot: int = -1
	var miner: int = 0
	var state: State = State.SEATED
	var dropped_tick: int = -1
	var token: String = ""


## identity -> Seat
var seats: Dictionary = {}
## Every change: {tick, identity, slot, state, why}.
var history: Array[Dictionary] = []


func seat_of(identity: String) -> Seat:
	return seats.get(identity, null)


func seat_at(slot: int) -> Seat:
	for raw: Variant in seats.values():
		var s: Seat = raw
		if s.slot == slot and s.state != State.REMOVED:
			return s
	return null


## The slots held for someone not connected now (never handed to a newcomer).
func held_slots() -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in seats.values():
		var s: Seat = raw
		if s.state == State.RESERVED or s.state == State.HAND_KEEPS:
			out[s.slot] = true
	return out


## A hello from `identity` (or with `token`): {"slot": n} to retake a reserved seat, {"reject":
## Protocol.Reject} when refused, or {} for a newcomer.
func on_hello(identity: String, token: String, tick: int, public: bool) -> Dictionary:
	var s: Seat = seat_of(identity)
	if s == null and not token.is_empty():
		for raw: Variant in seats.values():
			var by_token: Seat = raw
			if by_token.token == token:
				s = by_token
	if s == null:
		return {}
	expire(tick, public)
	match s.state:
		State.REMOVED:
			return {"reject": Protocol.Reject.REMOVED}
		State.HAND_KEEPS:
			return {"reject": Protocol.Reject.SEAT_KEPT}
		State.RESERVED:
			return {"slot": s.slot}
	return {}


## A welcomed player in `slot`: its seat is (again) its own.
func on_seated(identity: String, slot: int, token: String, tick: int) -> Seat:
	var s: Seat = seat_of(identity)
	if s == null:
		s = Seat.new()
		s.identity = identity
		seats[identity] = s
	s.slot = slot
	s.token = token
	s.state = State.SEATED
	s.dropped_tick = -1
	_note(tick, s, "seated")
	return s


func on_dropped(slot: int, miner: int, tick: int) -> Seat:
	var s: Seat = seat_at(slot)
	if s == null or s.state != State.SEATED:
		return null
	s.miner = miner
	s.state = State.RESERVED
	s.dropped_tick = tick
	_note(tick, s, "dropped")
	return s


## Public seats past net.public_retake_window_s: the Hand keeps the place.
func expire(tick: int, public: bool) -> Array[Seat]:
	var out: Array[Seat] = []
	if not public:
		return out
	var window: int = roundi(Tuning.f(&"net.public_retake_window_s") * Tuning.f(&"net.tick_hz"))
	for raw: Variant in seats.values():
		var s: Seat = raw
		if s.state == State.RESERVED and tick - s.dropped_tick > window:
			s.state = State.HAND_KEEPS
			_note(tick, s, "the Hand keeps the place")
			out.append(s)
	return out


func on_removed(identity: String, tick: int, why: String) -> Seat:
	var s: Seat = seat_of(identity)
	if s == null:
		return null
	s.state = State.REMOVED
	_note(tick, s, "removed: " + why)
	return s


func _note(tick: int, s: Seat, why: String) -> void:
	history.append({"tick": tick, "identity": s.identity, "slot": s.slot, "state": s.state, "why": why})
