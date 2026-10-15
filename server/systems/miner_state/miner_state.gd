class_name MinerStateSystem
extends SimSystem
## MNR-03: every miner in exactly one life state (Upright, Caught, Grabbed, Unconscious, Dead),
## with Hurt and Sick as overlays, rock-touched as a flag and an outcome over the life state.
## Other systems change states only through the hooks below. Requests queue during the tick
## and apply at its end (stage 16, before the record) in priority Dead, Unconscious, Grabbed,
## Caught, Upright, then overlays; each is checked against MinerTransitions' table as it applies,
## and every change emits exactly one signal with its cause. Illegal requests are errors in
## debug builds and logged and ignored in release. Server-only, except what the owning client
## and identity-level viewers are given: the own life state and capabilities, and body cues.

signal state_changed(entity: int, old: int, new: int, cause: String)
signal overlay_changed(entity: int, which: StringName, on: bool, cause: String)
signal outcome_set(entity: int, outcome: int, cause: String)

const Life = MinerTransitions.Life
const Outcome = MinerTransitions.Outcome
const HURT_KEY: StringName = &"hurt"
const ROCK_KEY: StringName = &"rock_touched"


class Miner:
	extends RefCounted
	var entity: int = 0
	var slot: int = -1
	var life: int = Life.UPRIGHT
	var outcome: int = Outcome.NONE
	var overlays: MinerOverlays = MinerOverlays.new()
	## The trap holding this miner (Caught, or Caught underneath while Unconscious): {source, trap_id}.
	var holder: Dictionary = {}
	## The grab: {kind ("drag" or "pin"), grabber, over (the holder a pin holds in place)}.
	var grab: Dictionary = {}
	## Unconscious and being dragged as a body (CRT-14).
	var dragged: bool = false
	## The fall came from a pin: a revive leaves the miner rock-touched.
	var fell_by_pin: bool = false
	## RSC-04's coming-round window: the crawl, the own cone within 4 tiles, the whisper.
	var crawl_window: bool = false


## The flush at the end of the tick.
class Flush:
	extends SimSystem
	var owner: MinerStateSystem

	func _init(of: MinerStateSystem) -> void:
		owner = of

	func stage() -> int:
		return StageTable.Stage.RECORD

	func order() -> int:
		return 0

	func system_name() -> String:
		return "miner_state_flush"

	func tick(run: RunState) -> void:
		owner.flush(run.tick)


## MNR-16: cues other systems add (the revolver raised: MinerCues.AIMING): (entity) -> int.
var extra_cues: Callable = Callable()
var hurt_ticks: int = 1200
var rock_touched_ticks: int = 12000
var _miners: Dictionary = {}
## [order, seq, hook, entity, args]
var _queue: Array[Array] = []
var _seq: int = 0
var _now: int = 0


func _init() -> void:
	var tick_hz: float = Tuning.f(&"net.tick_hz")
	hurt_ticks = roundi(Tuning.f(&"movement.hurt_duration") * tick_hz)
	rock_touched_ticks = roundi(Tuning.f(&"marks.rock_touched_s") * tick_hz)


func stage() -> int:
	return StageTable.Stage.MINERS


## Before movement (order 10): wounds and capabilities reach MNR-01 for this tick.
func order() -> int:
	return 0


func system_name() -> String:
	return "miner_state"


func register_into(run: RunState) -> void:
	run.add_system(self)
	run.add_system(Flush.new(self))


func add_miner(entity: int, slot: int = -1) -> Miner:
	var m: Miner = Miner.new()
	m.entity = entity
	m.slot = slot
	_miners[entity] = m
	return m


func miner(entity: int) -> Miner:
	if not _miners.has(entity):
		return null
	var m: Miner = _miners[entity]
	return m


func life(entity: int) -> int:
	var m: Miner = miner(entity)
	return m.life if m != null else -1


#region Hooks (queued; applied at the end of the tick)

func enter_caught(entity: int, source: StringName, trap_id: int) -> void:
	_request("enter_caught", entity, [source, trap_id])


func release_caught(entity: int, by: String) -> void:
	_request("release_caught", entity, [by])


func enter_grabbed(entity: int, kind: StringName, grabber: int) -> void:
	_request("enter_grabbed", entity, [kind, grabber])


func end_grab(entity: int, broken: bool) -> void:
	_request("end_grab", entity, [broken])


func fall_unconscious(entity: int, cause: String, ctx: Dictionary = {}) -> void:
	_request("fall_unconscious", entity, [cause, ctx])


func kill(entity: int, cause: String, shooter: int = 0) -> void:
	_request("kill", entity, [cause, shooter])


func revive(entity: int, how: StringName) -> void:
	_request("revive", entity, [how])


func make_hurt(entity: int, cause: String) -> void:
	_request("make_hurt", entity, [cause])


func add_mark(entity: int, mark: StringName) -> void:
	_request("add_mark", entity, [mark])


func cure_mark(entity: int, mark: StringName, cause: String = "kit") -> void:
	_request("cure_mark", entity, [mark, cause])


## Sets rock-touched until a tick; it only ever extends. No hook cures it.
func set_rock_touched(entity: int, until_tick: int) -> void:
	_request("set_rock_touched", entity, [until_tick])


func set_outcome(entity: int, outcome: int) -> void:
	_request("set_outcome", entity, [outcome])


## RSC-04 opens and closes the coming-round window (applies at once: it is no state change).
func set_crawl_window(entity: int, on: bool) -> void:
	var m: Miner = miner(entity)
	if m != null and m.life == Life.UNCONSCIOUS:
		m.crawl_window = on

#endregion

#region Queries

## What a miner may do now (the §4.2 table; the coming-round window opens a crawl).
func capabilities(entity: int) -> Dictionary:
	var m: Miner = miner(entity)
	if m == null:
		return {}
	var caps: Dictionary = Variants.dict(MinerTransitions.CAPABILITIES[m.life]).duplicate()
	if m.life == Life.UNCONSCIOUS and m.crawl_window:
		caps["move"] = true
		caps["turn"] = true
		caps["voice"] = true
	return caps


## The body cues identity-level viewers see (MinerCues bits).
func cues(entity: int) -> int:
	var m: Miner = miner(entity)
	if m == null:
		return 0
	var bits: int = 0
	if m.overlays.wound_slot(_now) and m.life != Life.DEAD and m.life != Life.UNCONSCIOUS:
		bits |= MinerCues.LIMP
	if m.overlays.marks.has(MinerOverlays.SOOT_LUNG) and m.life != Life.DEAD:
		bits |= MinerCues.COUGH
	var hold: Dictionary = m.holder if not m.holder.is_empty() else Variants.dict(m.grab.get("over", {}))
	if not hold.is_empty() and m.life != Life.DEAD:
		bits |= {&"man_trap": MinerCues.HELD_JAWS, &"timber_pin": MinerCues.HELD_PROP, &"staple_pit": MinerCues.HELD_PIT}.get(hold.get("source", &""), 0)
	if m.life == Life.GRABBED:
		bits |= MinerCues.HALF_IN_WALL if m.grab.get("kind", &"") == &"pin" else MinerCues.DRAGGED
	if m.life == Life.UNCONSCIOUS:
		bits |= MinerCues.LYING_BREATHING | (MinerCues.DRAGGED if m.dragged else 0)
	if m.life == Life.DEAD:
		bits |= MinerCues.LYING_STILL
	if extra_cues.is_valid():
		bits |= int(Variants.number(extra_cues.call(entity)))
	return bits


## A reading for Lamp Check and the logs: the outcome over the life state.
func describe(entity: int) -> String:
	var m: Miner = miner(entity)
	if m == null:
		return ""
	var state: String = str(Life.find_key(m.life)).capitalize()
	match m.outcome:
		Outcome.ESCAPED:
			return state + ", brought home" if m.life == Life.DEAD else state + ", escaped"
		Outcome.LEFT_BELOW:
			return state + ", left below"
	return state

#endregion

#region Tick

func tick(run: RunState) -> void:
	_now = run.tick
	for raw: Variant in _sorted_entities():
		var m: Miner = _miners[raw]
		if m.overlays.hurt_until >= 0 and not m.overlays.hurt(run.tick):
			m.overlays.hurt_until = -1
			overlay_changed.emit(m.entity, HURT_KEY, false, "expired")
		if m.overlays.rock_touched_until >= 0 and not m.overlays.rock_touched(run.tick):
			m.overlays.rock_touched_until = -1
			overlay_changed.emit(m.entity, ROCK_KEY, false, "worn_off")
		if run.movement != null and m.slot >= 0 and run.movement.miner(m.slot) != null:
			run.movement.modifiers(m.slot).set_wound(m.overlays.wound_slot(run.tick))
			var caps: Dictionary = capabilities(m.entity)
			var c: MinerMotion.Constraints = MinerMotion.Constraints.new()
			c.movement_off = not Variants.flag(caps["move"])
			c.facing_lock = not Variants.flag(caps["turn"])
			run.movement.set_constraint(m.slot, &"miner_state", c)


func _request(hook: String, entity: int, args: Array) -> void:
	_queue.append([_order_of(hook, args), _seq, hook, entity, args])
	_seq += 1


## Applies the queued requests in priority order. Returns [hook, entity, accepted] per request.
func flush(now: int) -> Array:
	_now = now
	var queue: Array[Array] = _queue
	_queue = []
	queue.sort_custom(func(a: Array, b: Array) -> bool:
		var ao: int = a[0]
		var bo: int = b[0]
		var asq: int = a[1]
		var bsq: int = b[1]
		return ao < bo or (ao == bo and asq < bsq))
	var results: Array = []
	for item: Array in queue:
		var hook: String = item[2]
		var entity: int = item[3]
		var ok: bool = _apply(hook, entity, Variants.array(item[4]))
		if not ok:
			var text: String = "MinerStateSystem: %s refused for entity %d in %s" % [hook, entity,
				Life.find_key(life(entity)) if miner(entity) != null else "no miner"]
			if OS.is_debug_build():
				push_error(text)
			else:
				Log.warn(text)
		results.append([hook, entity, ok])
	return results


func _order_of(hook: String, args: Array) -> int:
	match hook:
		"kill":
			return 0
		"fall_unconscious":
			return 1
		"end_grab":
			return 2 if Variants.flag(args[0]) else 1
		"enter_grabbed":
			return 2
		"enter_caught":
			return 3
		"release_caught", "revive":
			return 4
	return 5


func _apply(hook: String, entity: int, args: Array) -> bool:
	var m: Miner = miner(entity)
	if m == null or not MinerTransitions.allowed(hook, m.life):
		return false
	match hook:
		"enter_caught":
			var source: StringName = args[0]
			if m.life == Life.UNCONSCIOUS and not m.holder.is_empty():
				return false
			m.holder = {"source": source, "trap_id": args[1]}
			if source == &"man_trap":
				_mark_on(m, MinerOverlays.TRAP_WOUND, "man_trap")
			if m.life == Life.UPRIGHT:
				_set_life(m, Life.CAUGHT, "caught:" + str(source))
		"release_caught":
			if m.holder.is_empty():
				return false
			var held_by: StringName = m.holder["source"]
			m.holder = {}
			if m.life == Life.CAUGHT:
				_set_life(m, Life.UPRIGHT, "released:" + str(args[0]))
				if held_by == &"timber_pin":
					_hurt(m, "released_from_timber_pin")
		"enter_grabbed":
			var kind: StringName = args[0]
			if m.life == Life.UNCONSCIOUS:
				if kind != &"drag" or m.dragged:
					return false
				m.dragged = true
				return true
			if kind == &"drag":
				if m.life == Life.CAUGHT and m.holder.get("source", &"") == &"man_trap":
					_mark_on(m, MinerOverlays.TRAP_WOUND, "man_trap")
				m.holder = {}  # torn out of the trap, which stays sprung
				m.grab = {"kind": kind, "grabber": args[1], "over": {}}
			else:
				m.grab = {"kind": kind, "grabber": args[1], "over": m.holder}
				m.holder = {}
			_set_life(m, Life.GRABBED, "grabbed:" + str(kind))
		"end_grab":
			var broken: bool = args[0]
			if m.life == Life.UNCONSCIOUS:
				if not m.dragged:
					return false
				m.dragged = false
				return true
			var kind: StringName = m.grab["kind"]
			var over: Dictionary = Variants.dict(m.grab.get("over", {}))
			m.grab = {}
			if broken:
				if not over.is_empty():
					m.holder = over
					_set_life(m, Life.CAUGHT, "grab_broken:" + str(kind))
				else:
					_set_life(m, Life.UPRIGHT, "grab_broken:" + str(kind))
				_hurt(m, "released_from_" + str(kind))
				if kind == &"pin":
					_rock_touch(m, _now + rock_touched_ticks, "freed_from_pin")
			else:
				m.holder = over
				m.fell_by_pin = kind == &"pin"
				_set_life(m, Life.UNCONSCIOUS, str(kind) + "_ran_out")
		"fall_unconscious":
			if m.life == Life.GRABBED:
				m.holder = Variants.dict(m.grab.get("over", {}))
				m.grab = {}
			m.fell_by_pin = false
			m.crawl_window = false
			_set_life(m, Life.UNCONSCIOUS, str(args[0]))
		"kill":
			m.holder = {}
			m.grab = {}
			m.dragged = false
			m.crawl_window = false
			_set_life(m, Life.DEAD, str(args[0]))
		"revive":
			var how: StringName = args[0]
			m.dragged = false
			m.crawl_window = false
			_set_life(m, Life.CAUGHT if not m.holder.is_empty() else Life.UPRIGHT, "revived:" + str(how))
			if how == &"self":
				_hurt(m, "self_revive")
			if m.fell_by_pin:
				m.fell_by_pin = false
				_rock_touch(m, _now + rock_touched_ticks, "revived_after_pin")
		"make_hurt":
			_hurt(m, str(args[0]))
		"add_mark":
			var mark: StringName = args[0]
			if not MinerOverlays.MARKS.has(mark):
				return false
			_mark_on(m, mark, "add_mark")
		"cure_mark":
			var mark: StringName = args[0]
			if not m.overlays.marks.has(mark):
				return false
			m.overlays.marks.erase(mark)
			overlay_changed.emit(m.entity, mark, false, str(args[1]))
		"set_rock_touched":
			var until: int = args[0]
			if until <= m.overlays.rock_touched_until:
				return true  # it only ever extends
			_rock_touch(m, until, "set")
		"set_outcome":
			var outcome: int = args[0]
			if m.outcome != Outcome.NONE or outcome == Outcome.NONE:
				return false
			m.outcome = outcome
			outcome_set.emit(m.entity, outcome, "cage")
	return true


func _set_life(m: Miner, new: int, cause: String) -> void:
	var old: int = m.life
	m.life = new
	state_changed.emit(m.entity, old, new, cause)


func _hurt(m: Miner, cause: String) -> void:
	m.overlays.hurt_until = _now + hurt_ticks
	overlay_changed.emit(m.entity, HURT_KEY, true, cause)


func _mark_on(m: Miner, mark: StringName, cause: String) -> void:
	if m.overlays.marks.has(mark):
		return
	m.overlays.marks[mark] = true
	overlay_changed.emit(m.entity, mark, true, cause)


func _rock_touch(m: Miner, until: int, cause: String) -> void:
	var was: bool = m.overlays.rock_touched(_now)
	m.overlays.rock_touched_until = maxi(m.overlays.rock_touched_until, until)
	if not was:
		overlay_changed.emit(m.entity, ROCK_KEY, true, cause)


func _sorted_entities() -> Array:
	var keys: Array = _miners.keys()
	keys.sort()
	return keys


func write_state(writer: SimStateWriter) -> void:
	var keys: Array = _sorted_entities()
	writer.put_i64(keys.size())
	for raw: Variant in keys:
		var m: Miner = _miners[raw]
		writer.put_i64(m.entity)
		writer.put_i64(m.life)
		writer.put_i64(m.outcome)
		writer.put_bool(not m.holder.is_empty())
		writer.put_bool(not m.grab.is_empty())
		writer.put_bool(m.dragged)
		writer.put_bool(m.fell_by_pin)
		m.overlays.write_state(writer)

#endregion
