class_name TapperHunt
extends RefCounted
## CRT-09's hunt: Approach (to the wall nearest the sound, tapping), Listen (taps held for the
## crew's pause, striking only a true source in reach), Search (tapping within 10 tiles for the
## ring's search time), WindUp (0.5 s, the arm out, a double tap), Pin and ReStrike (TapperPin).
## The arm is an entity only in WindUp, Pin and ReStrike. A strike from rest at a wall needs no
## chosen hunt, so the relax never blocks it; the cap still binds.

const HUNTING: Array[StringName] = [&"approach", &"listen", &"search", &"windup", &"pin", &"restrike"]

var taps: TapperTaps = TapperTaps.new()
var pin: TapperPin = TapperPin.new()
## The face it waits at (its own rock tile when at a wall).
var face: Vector2i = Vector2i.ZERO
var until: int = -1
var arm: int = 0
var striking: int = 0
## LFT-10: () -> Array[Vector2i], the cage's sides as faces in the ride's bare-rock window.
var extra_faces: Callable = func() -> Array[Vector2i]: return []
## DIR-06: the first tick it may hunt at all, Approach or a strike from rest (staged run 1: 4:00).
var hunt_from_tick: int = 0
var _restriking: bool = false


static func busy(t: Tapper) -> bool:
	return t.state != null and HUNTING.has(t.state.name)


## The faces it can strike from now: its own (if it is at a wall) and the cage's.
func faces_here(run: RunState, t: Tapper) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if run.mine.native.tapper_face_usable(t.tile(run)):
		out.append(t.tile(run))
	for f: Variant in Variants.array(extra_faces.call()):
		out.append(f)
	return out


## From Patrol or Attend: a strike on a noisy miner already in reach (never blocked by the relax),
## else a chosen hunt toward the sound (blocked by the relax unless at the apex, and by the cap).
func consider(run: RunState, t: Tapper, heard: Array[TapperHearing.HeardEvent]) -> void:
	if heard.is_empty() or run.tick < hunt_from_tick:
		return
	var target: int = TapperStrike.target(run, t, heard, faces_here(run, t))
	if target != 0 and run.creatures.gate.request_commit(run, t, target, false):
		begin_windup(run, t, target)
		return
	var loudest: TapperHearing.HeardEvent = _loudest(heard)
	if run.creatures.gate.request_commit(run, t, TapperStrike.hunt_target(t, loudest), true):
		begin_approach(run, t, loudest)


func begin_approach(run: RunState, t: Tapper, h: TapperHearing.HeardEvent) -> void:
	var f: Variant = t.system.nav.native.nearest_usable_face(h.apparent, 6)
	if f == null:
		_listen(run, t)
		return
	face = f
	t.enter(run, &"approach", "heard %s" % NoiseTypes.id_of(h.kind))
	t.follower.go(run, t.system.nav, t, face, NavModes.Mode.ROCK)
	taps.reset()


func tick(run: RunState, t: Tapper, heard: Array[TapperHearing.HeardEvent]) -> void:
	match t.state.name:
		&"approach":
			taps.tick(run, t, Tuning.f(&"tapper.tap_radius_tiles"))
			if t.follower.status == NavFollower.Status.ARRIVED or t.follower.status == NavFollower.Status.BLOCKED or t.tile(run) == face:
				t.follower.stop()
				face = t.tile(run)
				_listen(run, t)
		&"listen":
			var target: int = TapperStrike.target(run, t, heard, faces_here(run, t))
			if target != 0:
				begin_windup(run, t, target)
			elif not heard.is_empty():
				begin_approach(run, t, _loudest(heard))
			elif run.tick >= until:
				t.enter(run, &"search", "nothing heard")
				until = run.tick + roundi(CreatureTables.search_time_s(t.ring(run)) * Tuning.f(&"net.tick_hz"))
				taps.reset()
		&"search":
			taps.tick(run, t, Tuning.f(&"tapper.search_tap_radius_tiles"))
			var target: int = TapperStrike.target(run, t, heard, faces_here(run, t))
			if target != 0:
				begin_windup(run, t, target)
			elif not heard.is_empty():
				begin_approach(run, t, _loudest(heard))
			elif run.tick >= until:
				end_hunt(run, t, "search spent")
		&"pin", &"restrike":
			if t.wind_up == null or not t.wind_up.is_running():
				pin.tick(run, t, self, heard)


## The 0.5 s wind-up at the face nearest the miner: the arm leaves the wall with a double tap.
func begin_windup(run: RunState, t: Tapper, miner: int) -> void:
	var faces: Array[Vector2i] = faces_here(run, t)
	if faces.is_empty():
		return
	var best: Vector2i = faces[0]
	var at: Vector2 = run.registry.get_entity(miner).position
	for f: Vector2i in faces:
		if TapperStrike.square_distance(at, f) < TapperStrike.square_distance(at, best):
			best = f
	face = best
	striking = miner
	t.follower.stop()
	_arm_out(run, at)
	run.noise.emit(NoiseTypes.Type.ROCK_TAP, face, {"level_np": Tuning.f(&"tapper.tap_np"), "source": t.entity_id})
	var strike_face: Vector2i = face
	var reach: float = Tuning.f(&"tapper.reach_tiles")
	var slot: int = _slot_of(run, miner)
	var w: CreatureWindUp = t.system.begin_wind_up(run, t, slot, miner, Tuning.f(&"tapper.windup_s"), func(r: RunState) -> bool:
		return r.registry.has(miner) and TapperStrike.square_distance(r.registry.get_entity(miner).position, strike_face) <= reach + 1e-9)
	t.enter(run, &"restrike" if _restriking else &"windup", "strike")
	if not w.valid:
		_after_miss(run, t)


func on_wind_up_finished(run: RunState, t: Tapper, w: CreatureWindUp) -> void:
	if w.outcome == CreatureWindUp.Outcome.LANDED:
		if _restriking and pin.grab_id >= 0 and run.holds.resume(run, pin.grab_id):
			t.grabbing = striking
			t.enter(run, &"pin", "restrike landed")
		elif not _restriking and pin.start(run, t, striking):
			t.enter(run, &"pin", "strike landed")
		else:
			_after_miss(run, t)
		_restriking = false
		return
	if w.outcome != CreatureWindUp.Outcome.CANCELLED:
		_after_miss(run, t)


## A ReStrike on the same victim, if they are within reach of the face.
func restrike(run: RunState, t: Tapper, miner: int) -> void:
	var at: Vector2 = run.registry.get_entity(miner).position
	if TapperStrike.square_distance(at, face) <= Tuning.f(&"tapper.reach_tiles") + 1e-9:
		_restriking = true
		begin_windup(run, t, miner)
	else:
		run.holds.end_grab(run, pin.grab_id, GrabHold.Outcome.ABANDONED)
		pin.reset()
		_listen(run, t)


## The grab ended (pulled, flared, lured, run out or a retreat).
func on_grab_ended(run: RunState, t: Tapper, outcome: GrabHold.Outcome) -> void:
	withdraw_arm(run)
	t.grabbing = 0
	if outcome == GrabHold.Outcome.TIMED_OUT and t.drop_lamp.is_valid():
		t.drop_lamp.call(pin.victim, face)
	pin.reset()
	if outcome != GrabHold.Outcome.RETREAT and t.state.name != &"approach":
		_listen(run, t)


## A lure dropped the victim: the hunt moves to the sound (and its miner, if any).
func lured(run: RunState, t: Tapper, h: TapperHearing.HeardEvent, miner: int) -> void:
	run.creatures.gate.stand_down(run, t, "lured")
	run.creatures.gate.request_commit(run, t, miner, false)
	begin_approach(run, t, h)


func end_hunt(run: RunState, t: Tapper, why: String) -> void:
	withdraw_arm(run)
	run.creatures.gate.stand_down(run, t, why)
	t.enter(run, &"patrol", why)
	taps.reset()


func reset(run: RunState) -> void:
	withdraw_arm(run)
	pin.reset()
	taps.reset()
	_restriking = false


func withdraw_arm(run: RunState) -> void:
	if arm != 0 and run.registry.has(arm):
		run.registry.destroy(arm)
	arm = 0


func _arm_out(run: RunState, toward: Vector2) -> void:
	withdraw_arm(run)
	var centre: Vector2 = Vector2(face) + Vector2(0.5, 0.5)
	var dir: Vector2 = (toward - centre).normalized() if toward.distance_to(centre) > 0.01 else Vector2.ZERO
	arm = run.registry.create(WorldIds.EntityKind.TAPPER_ARM, centre + dir * 0.75).id


func _after_miss(run: RunState, t: Tapper) -> void:
	withdraw_arm(run)
	if _restriking and pin.grab_id >= 0:
		run.holds.end_grab(run, pin.grab_id, GrabHold.Outcome.ABANDONED)
		pin.reset()
	_restriking = false
	_listen(run, t)


func _listen(run: RunState, t: Tapper) -> void:
	t.enter(run, &"listen", "at the wall")
	until = run.tick + roundi(CreatureTables.tapper_listen_pause_s(run.crew.count if run.crew != null else 1) * Tuning.f(&"net.tick_hz"))


static func _loudest(heard: Array[TapperHearing.HeardEvent]) -> TapperHearing.HeardEvent:
	var best: TapperHearing.HeardEvent = heard[0]
	for h: TapperHearing.HeardEvent in heard:
		if h.energy_np > best.energy_np:
			best = h
	return best


static func _slot_of(run: RunState, miner: int) -> int:
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == miner:
			return slot
	return -1
