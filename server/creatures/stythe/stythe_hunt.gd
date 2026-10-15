class_name StytheHunt
extends RefCounted
## CRT-14 (Gameplay §7.4): the Stythe's hunting states. From Lurk, Circle, Check, Keep or Shadow it
## commits (CRT-01's gate: chosen, so a relax blocks it, unless the miner walked unlit into its
## reach) to its preferred eligible miner and closes through the dark (Hunt). Its target lit, it
## circles; ineligible, it checks its remembered places. Within stythe.reach_tiles of a target whose
## flame is out (CRT-13's snuff takes it), it winds up for stythe.windup_s with a sharp intake of
## breath; the grab lands if the target is still in reach and no teammate's light of its threshold is
## on them (their own light made meanwhile, and Hired Hands' lamps, never count; NET-06's defender
## rule judges the reach). Collect takes an unlit unconscious miner it senses inside its hunting
## range: stythe.collect_s of breath, no wind-up, no hunt (no cap place, no relax). Flee drops any
## victim and goes stythe.flee_tiles from the light, then circles for stythe.circle_s; Retreat
## (CRT-01, the revolver) drops it and goes home. While the engine runs (LFT-09's apex) it lurks
## within stythe.apex_lurk_tiles of the gates unless it keeps a body or retreats. Server-only.

## The miner hunted (0: none) and whether the hunt was chosen.
var target: int = 0
## Collect: the body, and the tick its breath ends (-1: still closing).
var collecting: int = 0
var collect_until: int = -1
## Check: the remembered places still to visit.
var places: Array[Vector2i] = []
## Flee: where it runs to, and the light it then circles.
var flee_to: Vector2i = Vector2i(2147483647, 0)
var flee_light: Vector2i = Vector2i(2147483647, 0)
## Every transition it made, for tests: {tick, from, to, why}.
var log: Array[Dictionary] = []


## One tick, by state (Lurk and Circle's movement are StytheCreature's).
func tick(run: RunState, st: StytheCreature) -> void:
	match st.state.name:
		&"lurk", &"circle", &"check", &"keep", &"shadow":
			if st.state.name == &"circle" and run.tick >= st.circle_until:
				begin_check(run, st, "circled 30 s")
			elif st.state.name == &"check":
				_check(run, st)
			_consider(run, st)
		&"hunt":
			_hunt(run, st)
		&"windup":
			st.move.stop()
		&"collect":
			_collect(run, st)
		&"drag":
			st.drag.tick(run, st)
		&"flee":
			_flee(run, st)
		&"retreat":
			st.move.head_for(run, st, st.lair)


## A hunt to start, or a body to collect (Lurk only, per the diagram).
func _consider(run: RunState, st: StytheCreature) -> void:
	if st.is_retreating():
		return
	if st.state.name == &"lurk":
		var body: int = collectable(run, st)
		if body != 0:
			begin_collect(run, st, body)
			return
	for m: int in StytheEligibility.ranked(run, st):
		var row: String = StytheEligibility.row(run, st, m)
		if st.state.name == &"keep" and row != "reach" and not st.senses.in_territory(run, st, run.registry.get_entity(m).tile()):
			continue  # keeping a body, it hunts only in its territory
		if st.system.gate.request_commit(run, st, m, row != "reach"):
			target = m
			_enter(run, st, &"hunt", "eligible: %s" % row)
		return


func _hunt(run: RunState, st: StytheCreature) -> void:
	if target == 0 or not st.system.gate.is_hunting(st) or not run.registry.has(target):
		end_hunt(run, st, "the hunt ended")
		return
	var e: SimEntity = run.registry.get_entity(target)
	if not st.unlit(run, e.tile()):
		st.system.gate.stand_down(run, st, "target lit")
		var lit_at: Vector2i = e.tile()
		target = 0
		st.begin_circle(run, lit_at)
		_note(run, st, &"circle", "target lit")
		return
	if StytheEligibility.row(run, st, target).is_empty():
		end_hunt(run, st, "target ineligible")
		return
	st.chase(run, target)
	if e.position.distance_to(st.position(run)) <= Tuning.f(&"stythe.reach_tiles") + 1e-9 and not st.pushed \
			and not has_flame(run, target):
		begin_windup(run, st)


## The target's own flame (a burning gauze lamp or candle in hand, shuttered or not).
static func has_flame(run: RunState, miner: int) -> bool:
	if run.lamps != null:
		var l: GauzeLamp = run.lamps.lamp_in_hand(miner)
		if l != null and l.burning():
			return true
	if run.inventory != null and run.inventory.hands.has(miner):
		return HandsAndBelt.lit_candle(run.inventory.hands_of(miner).lamp_hand)
	return false


func begin_windup(run: RunState, st: StytheCreature) -> void:
	var victim: int = target
	var slot: int = StytheEligibility.slot_of(run, victim)
	var reach: float = Tuning.f(&"stythe.reach_tiles")
	st.move.stop()
	var w: CreatureWindUp = st.system.begin_wind_up(run, st, slot, victim, Tuning.f(&"stythe.windup_s"), func(r: RunState) -> bool:
		return r.registry.has(victim) and r.registry.get_entity(victim).position.distance_to(st.position(r)) <= reach + 1e-9)
	if not w.valid:
		return
	w.at_end = func(r: RunState) -> bool: return not lit_by_teammates(r, st, victim)
	if run.audio != null:
		run.audio.local(run, LocalSounds.Type.STYTHE_INTAKE, st.tile(run), Tuning.f(&"stythe.intake_reach_tiles"),
			Tuning.f(&"stythe.intake_np"), Tuning.f(&"stythe.windup_s"))
	_enter(run, st, &"windup", "in reach, flame out")


## Light of its threshold on `miner`'s tile from anyone but the miner and the Hired Hands (unheld
## lamps and area lights count: they are nobody's, Proposed).
static func lit_by_teammates(run: RunState, st: StytheCreature, miner: int) -> bool:
	var e: SimEntity = run.registry.get_entity(miner)
	return e != null and others_light(run, e.tile(), [miner]) >= st.light_threshold() - 1e-9


## The light on `tile` from every owner but `excluded` and the Hired Hands, 0-1.
static func others_light(run: RunState, tile: Vector2i, excluded: Array) -> float:
	if run.light == null:
		return 0.0
	var owners: PackedInt64Array = PackedInt64Array([0])
	for m: int in StytheSenses.miners(run):
		if not excluded.has(m) and not StytheEligibility.is_hand(run, m):
			owners.append(m)
	return run.light.grid.value_from(tile, owners) / 1000.0


func on_wind_up_finished(run: RunState, st: StytheCreature, w: CreatureWindUp) -> void:
	var victim: int = w.target_entity
	match w.outcome:
		CreatureWindUp.Outcome.LANDED:
			if not grab(run, st, victim, false):
				end_hunt(run, st, "the grab failed")
		CreatureWindUp.Outcome.MISSED:
			if run.registry.has(victim) and lit_by_teammates(run, st, victim):
				st.system.gate.stand_down(run, st, "a teammate's light")
				target = 0
				st.begin_circle(run, run.registry.get_entity(victim).tile())
				_note(run, st, &"circle", "a teammate's light on the target")
			else:
				_enter(run, st, &"hunt", "out of reach")


## Takes hold of `victim` (conscious, or a body to collect) and starts the drag.
func grab(run: RunState, st: StytheCreature, victim: int, collected: bool) -> bool:
	if run.holds == null or st.drag.victim != 0:
		return false
	var at: Vector2i = run.registry.get_entity(victim).tile()
	var conscious: bool = run.miner_state == null or run.miner_state.life(victim) != MinerTransitions.Life.UNCONSCIOUS
	if run.carry != null and run.carry.carrier_of(victim) != 0:
		run.carry.set_down(run, run.carry.carrier_of(victim))
	var limit: int = roundi(Tuning.f(&"stythe.drag_conscious_s") * Tuning.f(&"net.tick_hz"))
	var id: int = run.holds.grab(run, victim, GrabHold.Kind.STYTHE_DRAG, st.entity_id, limit)
	if id < 0:
		return false
	if conscious:
		LampDisposition.drop_at_grab(run, victim, at)
	st.grabbing = victim
	st.drag.start(run, st, victim, id, collected, conscious)
	_enter(run, st, &"drag", "collected" if collected else "the grab landed")
	return true


## An unlit unconscious miner it senses (by path, within its sense range), inside its hunting range,
## held by nothing, on a tile below its threshold (a carried body under a burning hook lamp is lit).
func collectable(run: RunState, st: StytheCreature) -> int:
	if run.miner_state == null:
		return 0
	var from: Vector2i = st.tile(run)
	var reach: float = st.senses.range_at(run, st)
	for m: int in StytheSenses.miners(run):
		if run.miner_state.life(m) != MinerTransitions.Life.UNCONSCIOUS or (run.holds != null and run.holds.grab_of(m) != null):
			continue
		var e: SimEntity = run.registry.get_entity(m)
		if not st.unlit(run, e.tile()) or not st.senses.in_hunting_range(run, st, e.tile()):
			continue
		var answer: Mine.PathAnswer = run.mine.path_distance(from, e.tile(), reach) if run.mine != null else null
		if answer != null and answer.distance >= 0.0 and answer.distance <= reach + 1e-6:
			return m
	return 0


func begin_collect(run: RunState, st: StytheCreature, body: int) -> void:
	collecting = body
	collect_until = -1
	_enter(run, st, &"collect", "a body unlit")


func _collect(run: RunState, st: StytheCreature) -> void:
	var e: SimEntity = run.registry.get_entity(collecting) if collecting != 0 else null
	if e == null or not st.unlit(run, e.tile()) or run.miner_state.life(collecting) != MinerTransitions.Life.UNCONSCIOUS \
			or (run.holds != null and run.holds.grab_of(collecting) != null):
		collecting = 0
		begin_check(run, st, "the body lit or gone")
		return
	if e.position.distance_to(st.position(run)) > Tuning.f(&"stythe.reach_tiles") + 1e-9:
		collect_until = -1
		st.move.head_for(run, st, e.tile())
		return
	st.move.stop()
	if collect_until < 0:
		collect_until = run.tick + roundi(Tuning.f(&"stythe.collect_s") * Tuning.f(&"net.tick_hz"))
		return
	if run.tick >= collect_until:
		var body: int = collecting
		collecting = 0
		collect_until = -1
		if not grab(run, st, body, true):
			begin_check(run, st, "could not take hold")


## Light on it while dragging (or a flare): drops the victim and runs stythe.flee_tiles from the light.
func begin_flee(run: RunState, st: StytheCreature, light_tile: Vector2i, why: String) -> void:
	st.drag.drop(run, st, GrabHold.Outcome.BROKEN)
	st.system.gate.stand_down(run, st, why)
	target = 0
	flee_light = light_tile
	flee_to = Vector2i(2147483647, 0)  # chosen once it stands in the dark again
	_enter(run, st, &"flee", why)


func _flee(run: RunState, st: StytheCreature) -> void:
	if flee_to.x == 2147483647:
		flee_to = _away_from(run, st, flee_light)
		st.move.head_for(run, st, flee_to)
		return
	if Vector2(st.tile(run)).distance_to(Vector2(flee_light)) >= Tuning.f(&"stythe.flee_tiles") - 1e-6 \
			or st.move.follower.status == NavFollower.Status.ARRIVED or st.move.follower.status == NavFollower.Status.BLOCKED:
		st.begin_circle(run, flee_light)
		_note(run, st, &"circle", "fled")
		return
	st.move.head_for(run, st, flee_to)


## The nearest dark floor at least stythe.flee_tiles (straight) from the light, by a dark flood.
func _away_from(run: RunState, st: StytheCreature, light_tile: Vector2i) -> Vector2i:
	var start: Vector2i = st.tile(run)
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var best: Vector2i = start
	var best_d: float = -1.0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size() and seen.size() < 4000:
		var t: Vector2i = queue[head]
		head += 1
		var d: float = Vector2(t).distance_to(Vector2(light_tile))
		if d >= Tuning.f(&"stythe.flee_tiles") - 1e-6:
			return t
		if d > best_d:
			best_d = d
			best = t
		for dir: Vector2i in dirs:
			var n: Vector2i = t + dir
			if not seen.has(n) and run.mine != null and run.mine.native.is_walkable(n, false) and st.unlit(run, n):
				seen[n] = true
				queue.append(n)
	return best


func begin_check(run: RunState, st: StytheCreature, why: String) -> void:
	places.clear()
	for i: int in range(st.senses.memory.size() - 1, -1, -1):
		places.append(st.senses.memory[i]["tile"])
	_enter(run, st, &"check", why)


func _check(run: RunState, st: StytheCreature) -> void:
	if places.is_empty():
		_enter(run, st, &"keep" if st.keeps() else &"lurk", "places checked")
		return
	st.move.head_for(run, st, places[0])
	if st.tile(run) == places[0] or st.move.follower.status == NavFollower.Status.BLOCKED:
		places.remove_at(0)


func end_hunt(run: RunState, st: StytheCreature, why: String) -> void:
	st.system.gate.stand_down(run, st, why)
	target = 0
	begin_check(run, st, why)


## Retreat (CRT-01, the revolver): the victim already dropped by the system; home, hunting nobody.
func on_retreat(run: RunState, st: StytheCreature) -> void:
	st.drag.drop(run, st, GrabHold.Outcome.RETREAT)
	target = 0
	collecting = 0
	st.move.stop()
	_enter(run, st, &"retreat", "retreat")


func _enter(run: RunState, st: StytheCreature, name: StringName, why: String) -> void:
	if st.state.name != name:
		_note(run, st, name, why)
		st.enter(run, name, why)


func _note(run: RunState, st: StytheCreature, to: StringName, why: String) -> void:
	log.append({"tick": run.tick, "from": st.state.name, "to": to, "why": why})
