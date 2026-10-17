class_name HandController
extends SimSystem
## MOD-08 (Gameplay §13.9, §11.11, §13.10, §13.11; GDD §13.9, §14.1): Hired Hands, deterministic
## AI miners who fill places and add risk, nothing more. One body, two drivers: a Hand is an
## ordinary miner entity whose input this controller writes each tick exactly as NET-03 delivers a
## client's (InputService.drive), so movement, collision, the lamp, carries and every authority
## check apply unchanged; a takeover only switches the driver, and nothing teleports. Stage INPUTS,
## after the callouts (it hears this tick's orders) and before the miners move.
##
## - Follows the nearest conscious human by path (CRT-02's walker paths) at hands.follow_min_tiles
##   to hands.follow_max_tiles, switching only to one hands.switch_nearer_tiles nearer, never a
##   miner at the switchboard; mirrors its human's gait and stamina, so it pants as they do. With no
##   path (a shut gate or air door between) it stands.
## - Obeys HandOrders' table, from callouts it keeps and lamp signals it sees; freezes, shuttered,
##   while a human within hands.grab_freeze_range_tiles by path is grabbed; does POINT's jobs
##   (HandJobs); coughs every hands.cough_interval_s (± jitter, its own named stream), whatever
##   the orders.
## - Never: tools, gates, air doors, phones, the switchboard, kits, the revolver, the lift's levers,
##   crank and throttle (HandInteractionFilter strips the input; the systems refuse it too).
## - Never company, never counted for a wipe, half a miner for crew count: DIR-05, DIR-03, SND-09,
##   RSC-09 and LFT-11 read is_hand_driven and is_hired_hand. Taken like miners (no scream; the
##   knocks sound; a kit on a medbay table revives one).
## Server-only: a client sees a Hand as an ordinary miner, by its seen set; nothing of its state,
## target or orders is ever sent.

enum State { FOLLOW = 0, STAND = 1, COME = 2, JOB = 3, TAKEN = 4 }
## How the Hand came to drive its miner: its own body (a filler), or a player's (NET-11, MOD-11).
enum Mode { FILLER = 0, DROPPED = 1, KICKED = 2, EJECTED = 3 }

const KEEP_REJECTED: int = 256
## How often a Hand plans its path and chooses whom to follow (ticks; Proposed: 4 Hz).
const PLAN_TICKS: int = 5
## A waypoint counts as reached within this distance of its centre (tiles).
const WAYPOINT_REACH: float = 0.35


class Hand:
	extends RefCounted
	var entity: int = 0
	var slot: int = -1
	var mode: Mode = Mode.FILLER
	var state: State = State.FOLLOW
	## 'Quiet!': crouches until the next order (Proposed: crouching as it follows).
	var crouched: bool = false
	## 'Douse!': shuttered, frozen while its human stands still, until 'Light up!'.
	var doused: bool = false
	## A human within range is grabbed: shuttered and frozen until the grab ends.
	var grab_frozen: bool = false
	var followed: int = 0
	var follow_distance: float = -1.0
	## COME's signaller.
	var come_to: int = 0
	## POINT's job ({kind, target, tile}), its phase and the ticks worked at it.
	var job: Dictionary = {}
	var job_phase: int = HandJobs.Phase.GO
	var worked: int = 0
	## 'Light up!' with the lamp Out: holding the flint until it lights or fails.
	var relighting: bool = false
	var next_cough: int = 0
	var badge: int = -1
	var voice: int = -1
	## The path it walks and the goal it was planned for.
	var path: Array[Vector2i] = []
	var path_index: int = 0
	var planned_tick: int = -1000000
	var moving: bool = false
	## MNR-14's knock: a load carrier's heading lags its partner's sharp turns.
	var heading: int = -1
	var turn_since: int = -1
	var cough_rng: LbRng = null

	func to_dict() -> Dictionary:
		return {"entity": entity, "slot": slot, "mode": mode, "state": state, "crouched": crouched, "doused": doused,
			"followed": followed, "next_cough": next_cough, "badge": badge, "voice": voice}


## entity -> Hand: every miner a Hand drives.
var hands: Dictionary = {}
## Inputs the filter turned away: how many, and the latest KEEP_REJECTED of them {tick, entity,
## holds, actions}.
var rejected_count: int = 0
var rejected: Array[Dictionary] = []
## Every order a Hand took: {tick, entity, order, from}.
var orders_taken: Array[Dictionary] = []
## Every cough: {tick, entity, tile}.
var coughs: Array[Dictionary] = []
## Soaks and tests: (run, entity, record) -> Array[ActionRecord], called on each Hand's input every
## tick before the filter, to inject attempts (held controls into `record`, one-shot actions returned).
var inject: Callable = Callable()
var _crew: CrewSeating = null
var _run: RunState = null
## Lamp signals seen since the last tick: [hand, kind, tile, maker].
var _seen: Array[Array] = []
var _frozen_since: int = -1


func stage() -> int:
	return StageTable.Stage.INPUTS


func order() -> int:
	return 40


func system_name() -> String:
	return "hands"


func bind(run: RunState, net: ServerNet) -> void:
	_run = run
	_crew = net.crew if net != null else null
	if run.crew != null:
		var driven_before: Callable = run.crew.is_hand_driven
		run.crew.is_hand_driven = func(e: int) -> bool: return hands.has(e) or Variants.flag(driven_before.call(e))
		run.crew.is_hired_hand = func(e: int) -> bool: return is_hand(e)
	if run.heard != null:
		run.heard.is_hand = func(slot: int) -> bool: return slot_driven(slot)
	if run.drops != null:
		run.drops.take_over = func(r: RunState, miner: int, mode: DropHandler.Takeover) -> void: take_over(r, miner, mode)
		run.drops.hand_back = func(r: RunState, miner: int) -> void: hand_back(r, miner)
	if run.lamp_signals != null:
		run.lamp_signals.signal_seen.connect(_on_signal_seen)
	if run.replication != null:
		var badge_before: Callable = run.replication.badge_of
		run.replication.badge_of = func(slot: int) -> int:
			var h: Hand = hand_in(slot)
			return h.badge if h != null and h.mode == Mode.FILLER and h.badge >= 0 else int(Variants.number(badge_before.call(slot)))
	if run.fall_audio != null:
		var voice_before: Callable = run.fall_audio.voice_of
		run.fall_audio.voice_of = func(slot: int) -> int:
			var h: Hand = hand_in(slot)
			if h != null and h.mode == Mode.FILLER and h.voice >= 0:
				return h.voice
			return int(Variants.number(voice_before.call(slot))) if voice_before.is_valid() else VoiceAssignment.default_for(str(slot))


#region The API other systems use

## A filler Hand's own body (never a player's miner it drives).
func is_hand(entity: int) -> bool:
	var h: Hand = hands.get(entity, null)
	return h != null and h.mode == Mode.FILLER


## Any miner a Hand drives, a dropped, kicked or ejected player's included.
func is_hand_driven(entity: int) -> bool:
	return hands.has(entity)


func slot_driven(slot: int) -> bool:
	return hand_in(slot) != null


func hand_in(slot: int) -> Hand:
	for raw: Variant in hands.values():
		var h: Hand = raw
		if h.slot == slot:
			return h
	return null


## The Hands within `tiles` (straight line) of `pos`, by entity.
func hands_within(pos: Vector2, tiles: float) -> Array[int]:
	var out: Array[int] = []
	for e: int in _sorted():
		var se: SimEntity = _run.registry.get_entity(e)
		if se != null and se.position.distance_to(pos) <= tiles:
			out.append(e)
	return out


## A filler Hand in an empty place (`slot`, with no player): its own miner at `at`, no lamp, a badge
## no living player wears and a free voice. Returns its entity (0 when the place is taken).
func fill_place(run: RunState, slot: int, at: Vector2) -> int:
	if run.movement == null or run.movement.miner(slot) != null:
		return 0
	var badge: int = _free_badge()
	var voice: int = _free_voice()
	var e: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, at)
	run.movement.add_miner(slot, e.id, e.position, 0)
	if run.miner_state != null:
		run.miner_state.add_miner(e.id, slot)
	if run.vision != null:
		run.vision.watch(slot, e.id, 0)
	var h: Hand = _start(run, e.id, slot, Mode.FILLER)
	h.badge = badge
	h.voice = voice
	Log.info("hands: a Hired Hand fills place %d at %s (badge %d)" % [slot, at, h.badge])
	return e.id


## NET-11 and MOD-11: a Hand takes a player's conscious miner where it stands. A drop keeps the belt,
## the lamp turned down on its hook and a drawn revolver back in its slot; a kick or an ejection keeps
## the lamp, and the rest of the belt drops at the miner's feet (the revolver too).
func take_over(run: RunState, miner: int, mode: DropHandler.Takeover) -> void:
	if hands.has(miner):
		return
	var slot: int = _slot_of(run, miner)
	var as_mode: Mode = Mode.DROPPED
	match mode:
		DropHandler.Takeover.KICKED:
			as_mode = Mode.KICKED
		DropHandler.Takeover.EJECTED:
			as_mode = Mode.EJECTED
	if run.inventory != null:
		var h: HandsAndBelt = run.inventory.hands_of(miner)
		if as_mode == Mode.DROPPED:
			if h.free_hand != null and h.free_hand.kind == ItemKinds.Kind.REVOLVER:
				for i: int in h.slots.size():
					if h.slots[i] == null:
						h.slots[i] = h.free_hand
						h.free_hand = null
						break
		else:
			_drop_belt(run, miner, h)
		_lamp_on_hook(run, miner)
		run.inventory.changed.emit(miner)
	_start(run, miner, slot, as_mode)
	Log.info("hands: a Hand takes slot %d's miner (%s)" % [slot, str(Mode.find_key(as_mode)).to_lower()])


## NET-11: the player retakes their miner as it is now; the lamp stays on the belt until they take it.
func hand_back(run: RunState, miner: int) -> void:
	var h: Hand = hands.get(miner, null)
	if h == null or h.mode == Mode.FILLER:
		return
	_end_job(run, h)
	hands.erase(miner)
	Log.info("hands: slot %d's player takes their miner back" % h.slot)


## MOD-03: a friend joining takes a filler Hand's place; the Hand leaves its body to them.
func release(entity: int) -> void:
	var h: Hand = hands.get(entity, null)
	if h == null:
		return
	if _run != null:
		_end_job(_run, h)
	hands.erase(entity)
	Log.info("hands: a filler Hand leaves place %d to a joining friend" % h.slot)


## An order straight to one Hand, as if it had kept the callout or seen the signal (soaks and tests
## fuzz orders here; `from` is the human who gave it).
func give_order(run: RunState, entity: int, what: HandOrders.Order, from: int = 0, point_tile: Vector2i = Vector2i(-1, -1)) -> void:
	var h: Hand = hands.get(entity, null)
	if h != null and h.state != State.TAKEN:
		_order(run, h, what, from, point_tile)


## Drives a Hand's input through the never filter (the controller does every tick; soaks and tests
## inject attempts here). Returns the holds the filter refused.
func drive(run: RunState, entity: int, record: InputRecord, actions: Array[ActionRecord] = []) -> int:
	var h: Hand = hands.get(entity, null)
	if h == null or run.inputs == null:
		return 0
	var acting: bool = h.state == State.JOB and h.job_phase == HandJobs.Phase.ACT
	var refused: int = HandInteractionFilter.strip(record, HandInteractionFilter.allowed_for(acting, h.relighting))
	if refused != 0 or not actions.is_empty():
		rejected_count += 1
		rejected.append({"tick": run.tick, "entity": entity, "holds": refused, "actions": actions.size()})
		if rejected.size() > KEEP_REJECTED:
			rejected.pop_front()
	var c: InputBuffer.Consumed = InputBuffer.Consumed.new()
	c.record = record
	c.shown_tick = run.tick
	c.real = true
	run.inputs.drive(h.slot, c)
	return refused

#endregion


func tick(run: RunState) -> void:
	_run = run
	if hands.is_empty():
		_seen.clear()
		return
	# FND-08's freeze_ai: Hands stop deciding and moving; their timers resume where they paused.
	if run.creatures != null and run.creatures.frozen:
		if _frozen_since < 0:
			_frozen_since = run.tick
		for e: int in _sorted():
			var still: Hand = hands[e]
			drive(run, e, _stopped(run, still))
		_seen.clear()
		return
	if _frozen_since >= 0:
		for raw: Variant in hands.values():
			var thawed: Hand = raw
			thawed.next_cough += run.tick - _frozen_since
		_frozen_since = -1
	_take_callouts(run)
	_take_signals(run)
	for e: int in _sorted():
		var h: Hand = hands[e]
		if run.registry.get_entity(e) == null:
			hands.erase(e)
			continue
		var record: InputRecord = _decide(run, h)
		var injected: Array[ActionRecord] = []
		if inject.is_valid():
			injected.assign(Variants.array(inject.call(run, e, record)))
		drive(run, e, record, injected)
		_cough(run, h)


## Each callout spoken this tick by a human, to every Hand that keeps more than half of it.
func _take_callouts(run: RunState) -> void:
	if run.callouts == null:
		return
	for entry: Dictionary in run.callouts.spoken:
		if int(Variants.number(entry["tick"])) != run.tick:
			continue
		var said: HandOrders.Order = HandOrders.of_callout(str(entry["line"]))
		if said == HandOrders.Order.NONE:
			continue
		var speaker_slot: int = int(Variants.number(entry["slot"]))
		var speaker: MovementSystem.Miner = run.movement.miner(speaker_slot)
		if speaker == null or hands.has(speaker.entity_id):
			continue
		for e: int in _sorted():
			var h: Hand = hands[e]
			if h.state == State.TAKEN:
				continue
			var at: Vector2i = run.registry.get_entity(e).tile()
			if run.callouts.kept_fraction_at(int(Variants.number(entry["id"])), at, h.slot) > HandOrders.KEPT_MIN:
				_order(run, h, said, speaker.entity_id, Vector2i(-1, -1))


func _on_signal_seen(hand: int, kind: LampSignalKind.Kind, point_tile: Vector2i) -> void:
	var maker: int = 0
	if _run != null and _run.lamp_signals != null and not _run.lamp_signals.history.is_empty():
		maker = int(Variants.number(_run.lamp_signals.history[_run.lamp_signals.history.size() - 1]["miner"]))
	_seen.append([hand, kind, point_tile, maker])


func _take_signals(run: RunState) -> void:
	var seen: Array[Array] = _seen
	_seen = []
	for s: Array in seen:
		var h: Hand = hands.get(int(Variants.number(s[0])), null)
		var maker: int = int(Variants.number(s[3]))
		if h == null or h.state == State.TAKEN or hands.has(maker):
			continue
		var signalled: HandOrders.Order = HandOrders.of_signal(int(Variants.number(s[1])) as LampSignalKind.Kind)
		var tile: Vector2i = s[2]
		if signalled != HandOrders.Order.NONE:
			_order(run, h, signalled, maker, tile)


## One order (HandOrders' table). A new order replaces the current one; 'Quiet!' lasts until the next.
func _order(run: RunState, h: Hand, what: HandOrders.Order, from: int, point_tile: Vector2i) -> void:
	orders_taken.append({"tick": run.tick, "entity": h.entity, "order": HandOrders.name_of(what), "from": from})
	h.crouched = what == HandOrders.Order.QUIET
	if what == HandOrders.Order.COUNT_OFF:
		# It answers 'Here!' at talk band, in its own voice, and carries on as it was.
		if run.callouts != null:
			run.callouts.speak(run, h.slot, "here", CalloutLines.TALK)
		return
	match what:
		HandOrders.Order.DOUSE:
			h.doused = true
			_shutter(run, h, true)
		HandOrders.Order.LIGHT_UP:
			h.doused = false
			var l: GauzeLamp = run.lamps.lamp_in_hand(h.entity) if run.lamps != null else null
			if l != null:
				if l.burning():
					_shutter(run, h, false)
				else:
					h.relighting = Relight.offered(l, Relight.FLINT)
		HandOrders.Order.STOP:
			if h.state == State.JOB and HandJobs.carrying(run, h.entity, h.job):
				HandJobs.set_down_here(run, h.entity)
			_end_job(run, h)
			h.state = State.STAND
		HandOrders.Order.COME:
			_end_job_unless_carrying(run, h)
			h.state = State.COME
			h.come_to = from
			h.planned_tick = -1000000
		HandOrders.Order.OK:
			_end_job_unless_carrying(run, h)
			h.state = State.FOLLOW
		HandOrders.Order.POINT:
			if h.state == State.JOB and HandJobs.carrying(run, h.entity, h.job) and int(Variants.number(h.job["kind"])) == HandJobs.Kind.BODY:
				h.job = {"kind": HandJobs.Kind.SET_DOWN, "target": int(Variants.number(h.job["target"])), "tile": point_tile}
				h.job_phase = HandJobs.Phase.GO
				h.planned_tick = -1000000
				return
			if h.state == State.JOB and HandJobs.carrying(run, h.entity, h.job):
				return  # one load at a time
			var job: Dictionary = HandJobs.pick(run, h.entity, point_tile)
			if job.is_empty():
				return
			_end_job(run, h)
			h.job = job
			h.job_phase = HandJobs.Phase.GO
			h.worked = 0
			h.state = State.JOB
			h.planned_tick = -1000000


## This tick's input for a Hand.
func _decide(run: RunState, h: Hand) -> InputRecord:
	var life: int = run.miner_state.life(h.entity) if run.miner_state != null and run.miner_state.miner(h.entity) != null \
		else MinerTransitions.Life.UPRIGHT
	if life != MinerTransitions.Life.UPRIGHT:
		# Taken like miners: Caught, Grabbed, unconscious or dead, it does nothing.
		if h.state != State.TAKEN:
			_end_job(run, h)
			h.state = State.TAKEN
			h.relighting = false
		return _stopped(run, h)
	if h.state == State.TAKEN:
		h.state = State.FOLLOW
		h.planned_tick = -1000000
	var r: InputRecord = _stopped(run, h)
	# Riding the cage, it stands where the cage takes it.
	if run.cage != null and run.cage.state >= Cage.State.RIDING and SignalCord.aboard(run, h.entity, run.cage.deck):
		return r
	if h.relighting:
		var l: GauzeLamp = run.lamps.lamp_in_hand(h.entity) if run.lamps != null else null
		if l == null or l.burning() or not Relight.offered(l, Relight.FLINT):
			h.relighting = false
		else:
			r.holds |= InputRecord.HOLD_RELIGHT
	# A grabbed human within range: shuttered and frozen until the grab ends.
	var grabbed: bool = _human_grabbed_near(run, h)
	if grabbed and not h.grab_frozen:
		_shutter(run, h, true)
	h.grab_frozen = grabbed
	if grabbed:
		return r
	match h.state:
		State.STAND:
			return r
		State.COME:
			if not _valid_human(run, h.come_to):
				h.state = State.FOLLOW
				return r
			var d: float = _walk_toward(run, h, h.come_to, r, Tuning.f(&"hands.follow_min_tiles"))
			if d >= 0.0 and d <= Tuning.f(&"hands.follow_min_tiles"):
				h.state = State.FOLLOW
				h.followed = h.come_to
			return r
		State.JOB:
			return _job(run, h, r)
	_follow(run, h, r)
	return r


## Follows the nearest conscious human by path, in the 3-5 tile band.
func _follow(run: RunState, h: Hand, r: InputRecord) -> void:
	if run.tick - h.planned_tick >= PLAN_TICKS or h.followed == 0 or not _valid_human(run, h.followed):
		_choose_human(run, h)
	if h.followed == 0:
		h.moving = false
		return
	var human: SimEntity = run.registry.get_entity(h.followed)
	var me: SimEntity = run.registry.get_entity(h.entity)
	r.facing = _facing_to(human.position - me.position, r.facing)
	_mirror_stamina(run, h)
	# LFT-10: its human aboard the cage, it boards too (it rides only standing on the deck), and it
	# never pulls the cord or counts toward its majority.
	if run.cage != null and SignalCord.aboard(run, h.followed, run.cage.deck):
		_board(run, h, r)
		return
	var d: float = h.follow_distance
	var max_d: float = Tuning.f(&"hands.follow_max_tiles")
	# 'Douse!': frozen while its human stands still.
	if h.doused and run.movement.is_still(_slot_of(run, h.followed)):
		h.moving = false
		return
	if d < 0.0:
		h.moving = false
		return
	if d > max_d:
		h.moving = true
	elif d <= max_d - 0.5:
		h.moving = false
	if h.moving:
		_step_path(run, h, r, _human_gait(run, h), true)


## Steps onto the cage's deck: to the free deck tile nearest it, then stands.
func _board(run: RunState, h: Hand, r: InputRecord) -> void:
	if SignalCord.aboard(run, h.entity, run.cage.deck):
		h.moving = false
		return
	var me: Vector2 = run.registry.get_entity(h.entity).position
	if run.tick - h.planned_tick >= PLAN_TICKS:
		h.planned_tick = run.tick
		var best: Vector2i = Vector2i(-1, -1)
		var best_d: float = INF
		var deck: Rect2i = run.cage.deck
		for y: int in range(deck.position.y, deck.end.y):
			for x: int in range(deck.position.x, deck.end.x):
				var t: Vector2i = Vector2i(x, y)
				var c: Vector2 = Vector2(t) + Vector2(0.5, 0.5)
				if run.mine != null and not run.mine.native.is_walkable(t):
					continue
				if _miner_on(run, c, h.entity):
					continue
				var d: float = c.distance_to(me)
				if d < best_d:
					best_d = d
					best = t
		if best.x < 0 or _plan(run, h, best) < 0.0:
			return
	h.moving = true
	_step_path(run, h, r, InputRecord.Gait.WALK)


func _miner_on(run: RunState, at: Vector2, but: int) -> bool:
	for slot: int in run.movement.miner_slots():
		var m: int = run.movement.miner(slot).entity_id
		if m != but and run.registry.get_entity(m).position.distance_to(at) < 0.6:
			return true
	return false


## Walks toward `target` along a path until within `stop_at` tiles by path; returns that distance.
func _walk_toward(run: RunState, h: Hand, target: int, r: InputRecord, stop_at: float) -> float:
	if run.tick - h.planned_tick >= PLAN_TICKS:
		h.follow_distance = _plan(run, h, run.registry.get_entity(target).tile())
		h.planned_tick = run.tick
	if h.follow_distance > stop_at:
		_step_path(run, h, r, InputRecord.Gait.WALK)
	return h.follow_distance


func _job(run: RunState, h: Hand, r: InputRecord) -> InputRecord:
	if not HandJobs.still_open(run, h.entity, h.job):
		_end_job(run, h)
		h.state = State.FOLLOW
		return r
	if h.job_phase == HandJobs.Phase.CARRY:
		# Carrying, it follows its human at the load's pace.
		_follow(run, h, r)
		_lag_heading(run, h, r)
		return r
	var me: SimEntity = run.registry.get_entity(h.entity)
	var goal: Vector2 = HandJobs.goal_of(run, h.entity, h.job)
	r.facing = _facing_to(goal - me.position, r.facing)
	if me.position.distance_to(goal) > HandJobs.WORK_REACH:
		h.job_phase = HandJobs.Phase.GO
		if run.tick - h.planned_tick >= PLAN_TICKS:
			_plan(run, h, Vector2i(floori(goal.x), floori(goal.y)))
			h.planned_tick = run.tick
		_step_path(run, h, r, InputRecord.Gait.WALK)
		return r
	h.job_phase = HandJobs.Phase.ACT
	var res: Dictionary = HandJobs.act(run, h.entity, h.job, h.worked)
	h.worked += 1
	if Variants.flag(res["interact"]):
		r.holds |= InputRecord.HOLD_INTERACT
	if Variants.flag(res["done"]):
		if HandJobs.carrying(run, h.entity, h.job):
			h.job_phase = HandJobs.Phase.CARRY
			h.planned_tick = -1000000
		else:
			h.job = {}
			h.state = State.FOLLOW
	return r


## Chooses whom to follow: the nearest conscious human by path, the current one kept unless another
## is hands.switch_nearer_tiles nearer; never a miner at the switchboard. Ties by entity.
func _choose_human(run: RunState, h: Hand) -> void:
	h.planned_tick = run.tick
	var operator: int = run.closeups.operator() if run.closeups != null else 0
	var best: int = 0
	var best_d: float = -1.0
	var best_path: Array[Vector2i] = []
	var current_d: float = -1.0
	var current_path: Array[Vector2i] = []
	var me: Vector2i = run.registry.get_entity(h.entity).tile()
	for slot: int in run.movement.miner_slots():
		var m: int = run.movement.miner(slot).entity_id
		if m == operator or not _valid_human(run, m):
			continue
		var p: Dictionary = _path(run, me, run.registry.get_entity(m).tile())
		if p.is_empty():
			continue
		var d: float = Variants.number(p["distance"])
		var tiles: Array[Vector2i] = p["tiles"]
		if m == h.followed:
			current_d = d
			current_path = tiles
		if best == 0 or d < best_d or (d == best_d and m < best):
			best = m
			best_d = d
			best_path = tiles
	if h.followed != 0 and current_d >= 0.0 and h.followed != operator \
			and best_d > current_d - Tuning.f(&"hands.switch_nearer_tiles"):
		_set_path(h, current_path, current_d)
		return
	h.followed = best
	_set_path(h, best_path, best_d)


func _set_path(h: Hand, tiles: Array[Vector2i], d: float) -> void:
	h.path = tiles
	h.path_index = 1 if tiles.size() > 1 else 0
	h.follow_distance = d


## Plans a path to `goal` for the Hand; returns its length in tiles (-1 with none).
func _plan(run: RunState, h: Hand, goal: Vector2i) -> float:
	var p: Dictionary = _path(run, run.registry.get_entity(h.entity).tile(), goal)
	if p.is_empty():
		_set_path(h, [] as Array[Vector2i], -1.0)
		return -1.0
	var tiles: Array[Vector2i] = p["tiles"]
	_set_path(h, tiles, Variants.number(p["distance"]))
	return h.follow_distance


## A walking path between tiles, {tiles, distance} or {} when there is none (an air door shut on it
## leaves the Hand behind: GEN-15).
func _path(run: RunState, from: Vector2i, to: Vector2i) -> Dictionary:
	if from == to:
		return {"tiles": [from] as Array[Vector2i], "distance": 0.0}
	if run.creatures == null or run.creatures.nav == null:
		return {}
	var res: Dictionary = run.creatures.nav.native.path(NavModes.Mode.WALKER, from, to, NavModes.defaults())
	if not Variants.flag(res.get("found", false)):
		return {}
	var tiles: Array[Vector2i] = []
	tiles.assign(Variants.array(res["tiles"]))
	var d: float = 0.0
	for i: int in range(1, tiles.size()):
		if run.mine != null and run.mine.native.effective_material(tiles[i]) == WorldIds.TileMaterial.WOODEN_DOOR:
			return {}
		d += Vector2(tiles[i] - tiles[i - 1]).length()
	return {"tiles": tiles, "distance": d}


## One step along the planned path at `gait`; facing its way unless `keep_facing` (a following Hand
## faces its human, Proposed).
func _step_path(run: RunState, h: Hand, r: InputRecord, gait: InputRecord.Gait, keep_facing: bool = false) -> void:
	if h.path.is_empty():
		return
	var me: Vector2 = run.registry.get_entity(h.entity).position
	while h.path_index < h.path.size() - 1 and me.distance_to(Vector2(h.path[h.path_index]) + Vector2(0.5, 0.5)) <= WAYPOINT_REACH:
		h.path_index += 1
	var next: Vector2 = Vector2(h.path[h.path_index]) + Vector2(0.5, 0.5)
	var v: Vector2 = next - me
	if v.length() <= 0.05:
		return
	r.move_dir = dir_byte(v)
	r.gait = InputRecord.Gait.CROUCH if h.crouched else gait
	if not keep_facing:
		r.facing = facing_u16(v)


## The gait it copies: its human's (walking when its human stands still and it must close up).
func _human_gait(run: RunState, h: Hand) -> InputRecord.Gait:
	var m: MovementSystem.Miner = run.movement.miner(_slot_of(run, h.followed))
	if m == null:
		return InputRecord.Gait.WALK
	match m.state.gait:
		MinerMotion.RUN:
			return InputRecord.Gait.RUN
		MinerMotion.CROUCH:
			return InputRecord.Gait.CROUCH
	return InputRecord.Gait.WALK


## Copies its human's stamina, so it never runs when they cannot and pants as they do.
func _mirror_stamina(run: RunState, h: Hand) -> void:
	var mine: MovementSystem.Miner = run.movement.miner(h.slot)
	var theirs: MovementSystem.Miner = run.movement.miner(_slot_of(run, h.followed))
	if mine == null or theirs == null:
		return
	mine.stamina.pool_ms = theirs.stamina.pool_ms
	mine.stamina.latched_off = theirs.stamina.latched_off


## MNR-14's knock (Proposed): carrying a load, a Hand re-heads only hands.knock_reheading_delay_ms
## after its partner turns more than 45°, so a sharp turn knocks as it does for two players.
func _lag_heading(run: RunState, h: Hand, r: InputRecord) -> void:
	if run.loads == null or not run.loads.carrying(h.entity) or r.move_dir == InputRecord.NO_DIRECTION:
		h.heading = r.move_dir
		h.turn_since = -1
		return
	if h.heading < 0 or h.heading == InputRecord.NO_DIRECTION:
		h.heading = r.move_dir
		return
	var diff: int = absi(posmod(r.move_dir - h.heading + InputRecord.DIRECTIONS / 2, InputRecord.DIRECTIONS) - InputRecord.DIRECTIONS / 2)
	if diff * 360 <= 45 * InputRecord.DIRECTIONS:
		h.heading = r.move_dir
		h.turn_since = -1
		return
	if h.turn_since < 0:
		h.turn_since = run.tick
	if (run.tick - h.turn_since) * 1000.0 / Tuning.f(&"net.tick_hz") >= Tuning.f(&"hands.knock_reheading_delay_ms"):
		h.heading = r.move_dir
		h.turn_since = -1
	else:
		r.move_dir = h.heading


## A conscious human (not a Hand) a Hand may follow.
func _valid_human(run: RunState, m: int) -> bool:
	if m == 0 or hands.has(m) or run.registry.get_entity(m) == null:
		return false
	if run.crew != null and Variants.flag(run.crew.is_hand_driven.call(m)):
		return false
	if run.miner_state == null or run.miner_state.miner(m) == null:
		return true
	return run.miner_state.life(m) <= MinerTransitions.Life.GRABBED


func _human_grabbed_near(run: RunState, h: Hand) -> bool:
	if run.holds == null:
		return false
	var me: SimEntity = run.registry.get_entity(h.entity)
	var reach: float = Tuning.f(&"hands.grab_freeze_range_tiles")
	var ids: Array = run.holds.grabs.keys()
	ids.sort()
	for raw: Variant in ids:
		var g: GrabHold = run.holds.grabs[raw]
		if not g.is_live() or hands.has(g.victim):
			continue
		var v: SimEntity = run.registry.get_entity(g.victim)
		if v == null or me.position.distance_to(v.position) > reach:
			continue
		var p: Dictionary = _path(run, me.tile(), v.tile())
		if not p.is_empty() and Variants.number(p["distance"]) <= reach:
			return true
	return false


## The cough: every hands.cough_interval_s or so (± hands.cough_jitter_s), at 12 np, whatever the
## orders ('Quiet!' too), while conscious.
func _cough(run: RunState, h: Hand) -> void:
	if run.tick < h.next_cough:
		return
	var life: int = run.miner_state.life(h.entity) if run.miner_state != null and run.miner_state.miner(h.entity) != null \
		else MinerTransitions.Life.UPRIGHT
	if life < MinerTransitions.Life.UNCONSCIOUS and run.noise != null:
		var at: Vector2i = run.registry.get_entity(h.entity).tile()
		run.noise.emit(NoiseTypes.Type.COUGH, at, {"source": h.entity})
		coughs.append({"tick": run.tick, "entity": h.entity, "tile": at})
	_schedule_cough(run, h)


func _schedule_cough(run: RunState, h: Hand) -> void:
	var hz: float = Tuning.f(&"net.tick_hz")
	var base: int = roundi(Tuning.f(&"hands.cough_interval_s") * hz)
	var jitter: int = roundi(Tuning.f(&"hands.cough_jitter_s") * hz)
	h.next_cough = run.tick + base + (h.cough_rng.range(-jitter, jitter) if jitter > 0 else 0)


func _start(run: RunState, entity: int, slot: int, mode: Mode) -> Hand:
	var h: Hand = Hand.new()
	h.entity = entity
	h.slot = slot
	h.mode = mode
	h.cough_rng = run.stream(HashDomain.HANDS, PackedInt64Array([entity]))
	hands[entity] = h
	_schedule_cough(run, h)
	return h


func _end_job(run: RunState, h: Hand) -> void:
	if run.inventory != null and run.inventory.actions.has(h.entity):
		var a: TimedAction = run.inventory.actions[h.entity]
		run.inventory.actions.erase(h.entity)
		a.cancel(TimedAction.RELEASED)
	h.job = {}
	h.job_phase = HandJobs.Phase.GO
	h.worked = 0


func _end_job_unless_carrying(run: RunState, h: Hand) -> void:
	if h.state == State.JOB and HandJobs.carrying(run, h.entity, h.job):
		return
	_end_job(run, h)


## A stopped input: no movement, nothing held, the lamp's state as its holder last asked (no press).
func _stopped(run: RunState, h: Hand) -> InputRecord:
	var r: InputRecord = InputRecord.new()
	r.move_dir = InputRecord.NO_DIRECTION
	r.gait = InputRecord.Gait.WALK
	r.facing = run.movement.facing_of(h.slot) if run.movement != null else 0
	r.holds = 0
	r.desired = run.lamps.last_bits(h.entity) if run.lamps != null else 2
	return r


func _shutter(run: RunState, h: Hand, closed: bool) -> void:
	if run.lamps == null:
		return
	var l: GauzeLamp = run.lamps.lamp_in_hand(h.entity)
	if l != null and l.burning() and l.shutter_closed != closed:
		run.lamps.shutter(run, l, not closed, "a Hand's order")


## The lamp turned down and onto the belt hook (MNR-06): radius 2.5, core 1.5.
func _lamp_on_hook(run: RunState, miner: int) -> void:
	if run.lamps == null:
		return
	var l: GauzeLamp = run.lamps.lamp_in_hand(miner)
	if l == null:
		return
	while l.wick > LampRules.WICK_DOWN:
		if not run.lamps.step_wick(run, l, -1, "a Hand took over"):
			break
	if not run.inventory.hands_of(miner).hooked:
		run.lamps.hook(run, l)


## MOD-11: a kicked or ejected player's belt drops at their miner's feet; the lamp stays.
func _drop_belt(run: RunState, miner: int, h: HandsAndBelt) -> void:
	var at: Vector2 = run.registry.get_entity(miner).position
	var w: ItemWorld = run.inventory.world
	if h.free_hand != null:
		var it: Item = h.free_hand
		h.free_hand = null
		w.put(run, it, at, &"put", miner)
	for i: int in h.slots.size():
		if h.slots[i] != null:
			var it: Item = h.slots[i]
			h.slots[i] = null
			w.put(run, it, at, &"put", miner)


func _free_badge() -> int:
	var worn: Array[int] = _crew.worn_badges() if _crew != null else ([] as Array[int])
	for raw: Variant in hands.values():
		var other: Hand = raw
		if other.badge >= 0:
			worn.append(other.badge)
	var free: Array[int] = RunSetup.badges_for_hands(1, worn)
	return free[0] if not free.is_empty() else -1


## A voice no miner speaks in: every place's as SND-13 gives it (a player's, or a dropped player's
## that a Hand drives), and the other filler Hands'.
func _free_voice() -> int:
	var used: Array[int] = []
	if _crew != null:
		for s: CrewSeating.Seat in _crew.in_order():
			if s.voice >= 0:
				used.append(s.voice)
	if _run != null and _run.movement != null and _run.fall_audio != null:
		for slot: int in _run.movement.miner_slots():
			var other: Hand = hand_in(slot)
			if other == null or other.mode != Mode.FILLER:
				used.append(_run.fall_audio.voice_for(slot))
	for raw: Variant in hands.values():
		var other: Hand = raw
		if other.voice >= 0:
			used.append(other.voice)
	for v: int in VoiceAssignment.VOICES:
		if not used.has(v):
			return v
	return used.size() % VoiceAssignment.VOICES


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func _sorted() -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in hands.keys():
		out.append(int(Variants.number(raw)))
	out.sort()
	return out


## The direction byte (0-254) for a vector, by a polynomial arctangent (no libm: the same on every
## platform; within 0.3°, well inside a direction step of 1.4°).
static func dir_byte(v: Vector2) -> int:
	return posmod(roundi(turns_of(v) * InputRecord.DIRECTIONS), InputRecord.DIRECTIONS)


static func facing_u16(v: Vector2) -> int:
	return posmod(roundi(turns_of(v) * 65536.0), 65536)


## The angle of `v` in turns (0-1), measured as MinerMotion's direction table is.
static func turns_of(v: Vector2) -> float:
	var ax: float = absf(v.x)
	var ay: float = absf(v.y)
	if ax == 0.0 and ay == 0.0:
		return 0.0
	var z: float = minf(ax, ay) / maxf(ax, ay)
	var a: float = (PI / 4.0) * z + 0.273 * z * (1.0 - z)  # atan(z) on [0, 1]
	if ay > ax:
		a = PI / 2.0 - a
	if v.x < 0.0:
		a = PI - a
	if v.y < 0.0:
		a = TAU - a
	return a / TAU


func _facing_to(v: Vector2, fallback: int) -> int:
	return facing_u16(v) if v.length() > 0.01 else fallback


func write_state(writer: SimStateWriter) -> void:
	var ids: Array[int] = _sorted()
	writer.put_i64(ids.size())
	for e: int in ids:
		var h: Hand = hands[e]
		writer.put_i64(e)
		writer.put_i64(h.slot)
		writer.put_i64(h.mode)
		writer.put_i64(h.state)
		writer.put_i64(h.followed)
		writer.put_i64(h.next_cough)
		writer.put_bool(h.crouched)
		writer.put_bool(h.doused)


func save_state() -> Dictionary:
	var out: Array = []
	for e: int in _sorted():
		var h: Hand = hands[e]
		out.append(h.to_dict())
	return {"hands": out}


## NET-09: the Hands as saved (their jobs start afresh, Proposed); a resumed run's dropped players'
## miners are taken again as the snapshot restores them.
func load_state(run: RunState, state: Dictionary) -> void:
	hands.clear()
	for raw: Variant in Variants.array(state.get("hands", [])):
		var d: Dictionary = Variants.dict(raw)
		var e: int = int(Variants.number(d["entity"]))
		var h: Hand = _start(run, e, int(Variants.number(d["slot"])), int(Variants.number(d["mode"])) as Mode)
		h.state = int(Variants.number(d.get("state", State.FOLLOW))) as State
		if h.state == State.JOB or h.state == State.COME:
			h.state = State.FOLLOW
		h.crouched = Variants.flag(d.get("crouched", false))
		h.doused = Variants.flag(d.get("doused", false))
		h.followed = int(Variants.number(d.get("followed", 0)))
		h.next_cough = int(Variants.number(d.get("next_cough", h.next_cough)))
		h.badge = int(Variants.number(d.get("badge", -1)))
		h.voice = int(Variants.number(d.get("voice", -1)))
