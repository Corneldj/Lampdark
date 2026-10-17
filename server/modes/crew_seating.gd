class_name CrewSeating
extends RefCounted
## MOD-03 (Gameplay §13.2, GDD §14.1): who sits in each place. A joiner's Hello offers up to three
## roster miners in the order they would play them; the first whose lamp number no seated miner holds
## sits (no run seats two miners with one number, the dead included), and one whose three all clash is
## refused (Reject.LAMP_NUMBERS). The seat wears the player's own cap badge when no living miner wears
## it, else the next free one; Hired Hands take only badges no living player holds. Its character
## voice is the miner's own, else the first free (SND-13's VoiceAssignment rule, in join order). The
## player's New Brigade runs ride along for the staging. A player retaking their place (NET-11) keeps
## their seat. Kept through every save. Server-only: other clients learn only a seated miner's public
## view (name, lamp number, badge, the pages shown).


class Seat:
	extends RefCounted
	var identity: String = ""
	var slot: int = -1
	## Join order (0 first).
	var order: int = 0
	## A player's miner (bots and dev clients without a profile are seated with none: miner_id -1).
	var miner_id: int = -1
	var name: String = ""
	var lamp_number: int = 0
	var voice: int = -1
	var book_pages: Array[String] = []
	var badge: int = -1
	## MOD-01's New Brigade runs; -1 unknown (an Old Hand for the staging).
	var brigade_runs: int = -1

	func to_dict() -> Dictionary:
		return {"identity": identity, "slot": slot, "order": order, "miner_id": miner_id, "name": name, "lamp_number": lamp_number,
			"voice": voice, "book_pages": book_pages.duplicate(), "badge": badge, "brigade_runs": brigade_runs}

	static func from_dict(d: Dictionary) -> Seat:
		var s: Seat = Seat.new()
		s.identity = str(d.get("identity", ""))
		s.slot = int(Variants.number(d.get("slot", -1)))
		s.order = int(Variants.number(d.get("order", 0)))
		s.miner_id = int(Variants.number(d.get("miner_id", -1)))
		s.name = str(d.get("name", ""))
		s.lamp_number = int(Variants.number(d.get("lamp_number", 0)))
		s.voice = int(Variants.number(d.get("voice", -1)))
		for p: Variant in Variants.array(d.get("book_pages", [])):
			s.book_pages.append(str(p))
		s.badge = int(Variants.number(d.get("badge", -1)))
		s.brigade_runs = int(Variants.number(d.get("brigade_runs", -1)))
		return s


## identity -> Seat, everyone seated this run (a dead miner's seat stays: its number is still taken).
var seats: Dictionary = {}
## (slot) -> bool: that place's miner is dead (its badge is free again). Default: nobody.
var is_dead: Callable = func(_slot: int) -> bool: return false
var _joined: int = 0


## The seats into the run's systems (ServerSystems.install): VIS-06's badge by place, SND-13's
## voice (the identity's default for a seat with none), LFT-11's name and lamp number, RSC-06's
## staging telemetry, and whose miner is dead (a dead miner's badge is free again).
func bind(run: RunState) -> void:
	is_dead = func(slot: int) -> bool:
		var m: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
		return m != null and run.miner_state != null and run.miner_state.life(m.entity_id) == MinerTransitions.Life.DEAD
	if run.replication != null:
		run.replication.badge_of = func(slot: int) -> int:
			var b: int = badge_of(slot)
			return b if b >= 0 else slot % RunSetup.BADGES
	if run.fall_audio != null:
		run.fall_audio.voice_of = func(slot: int) -> int:
			var s: Seat = of_slot(slot)
			if s == null:
				return VoiceAssignment.default_for(str(slot))
			return s.voice if s.voice >= 0 else VoiceAssignment.default_for(s.identity)
	if run.outcomes != null:
		run.outcomes.identity_of = func(miner: int) -> Dictionary:
			if run.movement != null:
				for slot: int in run.movement.miner_slots():
					if run.movement.miner(slot).entity_id == miner:
						return identity_of(slot)
			return {}
	if run.lamp_check != null:
		run.lamp_check.staging_of = func(r: RunState) -> String: return r.header.staging if not r.header.staging.is_empty() else "none"


## A place left at the Pithead, before the run began: its seat is free again (number and badge).
func release_slot(slot: int) -> void:
	var s: Seat = of_slot(slot)
	if s != null:
		seats.erase(s.identity)


## What a joiner would take, changing nothing: {"miner": the candidate (or {} for none), "badge",
## "voice"}, or {"reject": Protocol.Reject} when none of its miners may sit (LAMP_NUMBERS) or a
## candidate's number is not a lamp number (BAD_MESSAGE). A returning player keeps their seat.
func choose(identity: String, hello: Protocol.Hello) -> Dictionary:
	var own: Seat = seats.get(identity, null)
	if own != null:
		return {"miner": {}, "badge": own.badge, "voice": own.voice, "keep": true}
	var lo: int = Tuning.i(&"modes.lamp_number_min")
	var hi: int = Tuning.i(&"modes.lamp_number_max")
	var picked: Dictionary = {}
	if not hello.candidates.is_empty():
		var taken: Array[int] = seated_numbers()
		for c: Dictionary in hello.candidates:
			var n: int = int(Variants.number(c.get("lamp_number", 0)))
			if n < lo or n > hi or str(c.get("name", "")).strip_edges().is_empty():
				return {"reject": Protocol.Reject.BAD_MESSAGE}
		for c: Dictionary in hello.candidates:
			if not taken.has(int(Variants.number(c.get("lamp_number", 0)))):
				picked = c
				break
		if picked.is_empty():
			return {"reject": Protocol.Reject.LAMP_NUMBERS}
	var want_voice: int = int(Variants.number(picked.get("voice_id", -1))) if not picked.is_empty() else -1
	var badge: int = RunSetup.badge_for(maxi(hello.preferred_badge, 0), worn_badges())
	return {"miner": picked, "badge": badge, "voice": _voice_for(want_voice, str(picked.get("name", "")))}


## Seats `identity` in `slot` with what choose() gave.
func commit(slot: int, identity: String, hello: Protocol.Hello, choice: Dictionary) -> Seat:
	var s: Seat = seats.get(identity, null)
	if s != null:
		s.slot = slot
		return s
	s = Seat.new()
	s.identity = identity
	s.slot = slot
	s.order = _joined
	_joined += 1
	var m: Dictionary = Variants.dict(choice.get("miner", {}))
	if not m.is_empty():
		s.miner_id = int(Variants.number(m.get("id", -1)))
		s.name = str(m.get("name", ""))
		s.lamp_number = int(Variants.number(m.get("lamp_number", 0)))
		for p: Variant in Variants.array(m.get("book_pages", [])):
			s.book_pages.append(str(p))
	s.voice = int(Variants.number(choice.get("voice", -1)))
	s.badge = int(Variants.number(choice.get("badge", -1)))
	s.brigade_runs = hello.new_brigade_runs
	seats[identity] = s
	return s


func of_slot(slot: int) -> Seat:
	var best: Seat = null
	for raw: Variant in seats.values():
		var s: Seat = raw
		if s.slot == slot and (best == null or s.order > best.order):
			best = s
	return best


## Every seated miner's lamp number (the dead's too).
func seated_numbers() -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in seats.values():
		var s: Seat = raw
		if s.miner_id >= 0:
			out.append(s.lamp_number)
	return out


## The badges living miners wear.
func worn_badges() -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in seats.values():
		var s: Seat = raw
		if s.badge >= 0 and not Variants.flag(is_dead.call(s.slot)):
			out.append(s.badge)
	return out


## A place's badge (VIS-06's MinerCues), -1 when nobody is seated there.
func badge_of(slot: int) -> int:
	var s: Seat = of_slot(slot)
	return s.badge if s != null else -1


## SND-13: a place's character voice, -1 when unknown.
func voice_of(slot: int) -> int:
	var s: Seat = of_slot(slot)
	return s.voice if s != null else -1


## LFT-11's {name, lamp_number} for a place's roster miner ({} for none).
func identity_of(slot: int) -> Dictionary:
	var s: Seat = of_slot(slot)
	if s == null or s.miner_id < 0:
		return {}
	return {"name": s.name, "lamp_number": s.lamp_number}


## What another client may know of a place's miner (MOD-01's public view): {} for none.
func public_view(slot: int) -> Dictionary:
	var s: Seat = of_slot(slot)
	if s == null or s.miner_id < 0:
		return {}
	return {"name": s.name, "lamp_number": s.lamp_number, "badge": s.badge, "book_pages": s.book_pages.duplicate()}


## Hired Hands' badges: only those no living player wears.
func badges_for_hands(count: int) -> Array[int]:
	return RunSetup.badges_for_hands(count, worn_badges())


## The seated players' New Brigade runs, in join order (-1: unknown).
func brigade_runs() -> Array[int]:
	var out: Array[int] = []
	for s: Seat in in_order():
		out.append(s.brigade_runs)
	return out


func in_order() -> Array[Seat]:
	var out: Array[Seat] = []
	for raw: Variant in seats.values():
		out.append(raw)
	out.sort_custom(func(a: Seat, b: Seat) -> bool: return a.order < b.order)
	return out


func to_dict() -> Dictionary:
	var out: Array = []
	for s: Seat in in_order():
		out.append(s.to_dict())
	return {"seats": out, "joined": _joined}


func from_dict(d: Dictionary) -> void:
	seats.clear()
	for raw: Variant in Variants.array(d.get("seats", [])):
		var s: Seat = Seat.from_dict(Variants.dict(raw))
		seats[s.identity] = s
	_joined = int(Variants.number(d.get("joined", seats.size())))


func _voice_for(want: int, miner_name: String) -> int:
	var used: Array[int] = []
	for raw: Variant in seats.values():
		var s: Seat = raw
		if s.voice >= 0:
			used.append(s.voice)
	var v: int = want if want >= 0 and want < VoiceAssignment.VOICES else (VoiceAssignment.default_for(miner_name) if not miner_name.is_empty() else -1)
	if v < 0:
		return -1
	if not used.has(v):
		return v
	for free: int in VoiceAssignment.VOICES:
		if not used.has(free):
			return free
	return v
