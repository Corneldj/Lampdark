class_name Revolver
extends SimSystem
## MNR-16 (stage MINERS, after the chalk): the deputy's Webley, the only gun below (Gameplay §4.7).
## It takes a belt slot, and its box of rounds (ROUNDS, a stack of up to 12) another; it is found
## with revolver.cylinder_rounds in the cylinder ("rounds" in its state).
##
## Use on its slot draws it into the free hand in revolver.draw_time (1 s), and Use on an empty
## slot puts it back there; drawn, it blocks whatever needs the free hand but feeling, levers and
## phones (MNR-04's rule). Aiming (InputRecord.HOLD_AIM while drawn) caps the gait at a walk
## (MNR-01's constraint) and shows on the miner's identity record (MinerCues.AIMING). A TRIGGER
## while aiming fires, at most once per revolver.fire_interval: one round, then Shot's effects and
## trace. An empty cylinder only clicks, for the shooter alone (Proposed). Reloading (relight's
## R or X held while drawn) loads a round a revolver.reload_per_round from a box on the belt, with
## an 8 np reload click, up to the cylinder's six; firing or putting it away stops a reload, and a
## round half-loaded is not loaded (Proposed). Hired Hands never pick it up, draw or fire it.
##
## A hit on a creature counts toward its own threshold (RetreatCounters): below it a flinch, at it
## a retreat (CRT-01). A hit on a miner or a Hand is a `friendly_hit` (RSC-05 decides the outcome:
## until then the stub here kills among friends and fells in public; a second by the same shooter
## asks MOD-11 to eject them). Bess hit: `bess_hit` (MOD-07). A dead body on the line stops the
## shot with no effect (Proposed). Every shot is logged for NET-07 and RSC-07's card. Server-only:
## no hit, miss, counter or tally ever reaches a client.

## HAZ-04: a shot at `tile` (a shot inside firedamp fires it).
signal shot_fired(tile: Vector2i)
## RSC-05, MOD-11: a shot hit a miner or a Hired Hand (decided on the rewound server state).
signal friendly_hit(victim: int, shooter: int, tick: int)
## MOD-07: a shot hit Bess.
signal bess_hit(shooter: int, tick: int)

const OWNER: StringName = &"revolver"

var counters: RetreatCounters = RetreatCounters.new()
## Every shot: {tick, shooter, origin, aim, hit, outcome}.
var shots: Array[Dictionary] = []
## Every friendly hit: {tick, victim, shooter, outcome}.
var friendly_hits: Array[Dictionary] = []
## MOD-11: shooters asked to be ejected: {tick, shooter}.
var ejections: Array[Dictionary] = []
## Muzzle flashes still lit: {source, until}.
var flashes: Array[Dictionary] = []
## RSC-05's outcome of a friendly hit: (run, victim, shooter) -> StringName. The stub: dead among
## friends and solo, unconscious in public, the shooter named (FallCause.FRIENDLY_HIT).
var on_friendly_hit: Callable = func(r: RunState, victim: int, shooter: int) -> StringName: return _stub_friendly(r, victim, shooter)
## MOD-11's ejection after a second friendly hit: (run, shooter) -> void. The stub logs it.
var eject: Callable = func(r: RunState, shooter: int) -> void: ejections.append({"tick": r.tick, "shooter": shooter})
## miner -> the tick it may fire again.
var _next_fire: Dictionary = {}
## miner -> the belt slot it was drawn from.
var _drawn_from: Dictionary = {}
## miner -> friendly hits it has made this run.
var _friendly_by: Dictionary = {}
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 37


func system_name() -> String:
	return "revolver"


func bind(run: RunState) -> void:
	_run = run
	if run.inventory != null:
		run.inventory.use_handlers[ItemKinds.Kind.REVOLVER] = func(r: RunState, entity: int, slot: int) -> void: draw(r, entity, slot)
		run.inventory.empty_slot_use = func(r: RunState, entity: int, _slot: int) -> void: put_away(r, entity)
	if run.miner_state != null:
		run.miner_state.extra_cues = func(entity: int) -> int: return MinerCues.AIMING if is_aiming(entity) else 0


## A new revolver (GEN-08's deputy, tests): six in the cylinder unless given.
static func make(run: RunState, rounds: int = -1) -> Item:
	return run.inventory.world.make(ItemKinds.Kind.REVOLVER, 1, {"rounds": rounds if rounds >= 0 else Tuning.i(&"revolver.cylinder_rounds")})


static func rounds_in(it: Item) -> int:
	return int(Variants.number(it.state.get("rounds", 0)))


func drawn_revolver(m: int) -> Item:
	if _run == null or _run.inventory == null or not _run.inventory.hands.has(m):
		return null
	var it: Item = _run.inventory.hands_of(m).free_hand
	return it if it != null and it.kind == ItemKinds.Kind.REVOLVER else null


func is_drawn(m: int) -> bool:
	return drawn_revolver(m) != null


## Drawn, with aim held, and able to use the belt (not Grabbed or out cold).
func is_aiming(m: int) -> bool:
	if not is_drawn(m) or _run.movement == null:
		return false
	var slot: int = _slot_of(_run, m)
	var c: InputBuffer.Consumed = _run.input_for(slot) if slot >= 0 else null
	return c != null and (c.record.holds & InputRecord.HOLD_AIM) != 0 and _may_use(_run, m)


## Use on the revolver's slot: into the free hand in revolver.draw_time. Never for a Hand.
func draw(run: RunState, m: int, _slot: int) -> void:
	var h: HandsAndBelt = run.inventory.hands_of(m)
	var from_slot: int = h.selected
	var it: Item = h.slots[from_slot]
	if it == null or it.kind != ItemKinds.Kind.REVOLVER or ToolsParts.is_hand(run, m) or h.free_hand != null or h.two_handed:
		return
	var a: TimedAction = TimedAction.make(m, &"draw", Tuning.f(&"revolver.draw_time"), InputRecord.HOLD_USE)
	a.capability = &"belt"
	a.valid = func() -> bool: return h.slots[from_slot] == it and h.free_hand == null and not h.two_handed
	a.effect = func() -> void:
		h.slots[from_slot] = null
		h.free_hand = it
		_drawn_from[m] = from_slot
		run.inventory.changed.emit(m)
	run.inventory.start_action(run, a)


## Use on an empty slot while drawn: back into that slot in revolver.draw_time.
func put_away(run: RunState, m: int) -> void:
	var h: HandsAndBelt = run.inventory.hands_of(m)
	var it: Item = drawn_revolver(m)
	var to_slot: int = h.selected
	if it == null or h.slots[to_slot] != null:
		return
	var a: TimedAction = TimedAction.make(m, &"put_away", Tuning.f(&"revolver.draw_time"), InputRecord.HOLD_USE)
	a.capability = &"belt"
	a.valid = func() -> bool: return h.free_hand == it and h.slots[to_slot] == null
	a.effect = func() -> void:
		h.free_hand = null
		h.slots[to_slot] = it
		_drawn_from.erase(m)
		run.inventory.changed.emit(m)
	run.inventory.start_action(run, a)


func tick(run: RunState) -> void:
	_run = run
	for f: Dictionary in flashes.duplicate():
		if run.tick >= int(Variants.number(f["until"])):
			if run.light != null:
				run.light.grid.remove_source(int(Variants.number(f["source"])))
			flashes.erase(f)
	if run.movement == null or run.inventory == null:
		return
	for slot: int in run.movement.miner_slots():
		var m: int = run.movement.miner(slot).entity_id
		var aiming: bool = is_aiming(m)
		run.movement.set_constraint(slot, OWNER, _walk_only() if aiming else null)
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null or not is_drawn(m):
			continue
		for act: ActionRecord in c.actions:
			if act.kind == ActionRecord.Kind.TRIGGER:
				fire(run, m, slot, act.aim, act.tick, aiming)
		if (c.record.holds & InputRecord.HOLD_RELIGHT) != 0 and not run.inventory.actions.has(m):
			_reload_one(run, m)


static func _walk_only() -> MinerMotion.Constraints:
	var k: MinerMotion.Constraints = MinerMotion.Constraints.new()
	k.run_allowed = false
	return k


## A trigger: fires if drawn and aiming, not too soon, with a round; else nothing (an empty
## cylinder clicks for the shooter alone). Returns the shot's record, or {}.
func fire(run: RunState, m: int, slot: int, aim: int, stamp: int, aiming: bool) -> Dictionary:
	var it: Item = drawn_revolver(m)
	if it == null or not aiming or ToolsParts.is_hand(run, m) or not _may_use(run, m):
		return {}
	if run.tick < int(Variants.number(_next_fire.get(m, -1))):
		return {}
	_next_fire[m] = run.tick + maxi(1, roundi(Tuning.f(&"revolver.fire_interval") * Tuning.f(&"net.tick_hz")))
	# Firing stops a reload; the round half-loaded is not loaded.
	var running: TimedAction = run.inventory.actions.get(m, null)
	if running != null and running.verb == &"reload":
		run.inventory.actions.erase(m)
		running.cancel(&"fired")
	if rounds_in(it) <= 0:
		_dry_click(run, slot, m)
		return {}
	it.state["rounds"] = rounds_in(it) - 1
	var row: Dictionary = Shot.fire(run, self, m, slot, aim, stamp)
	shots.append(row)
	return row


## A hit on `entity`: the outcome logged with the shot.
func on_body_hit(run: RunState, shooter: int, entity: int) -> StringName:
	var e: SimEntity = run.registry.get_entity(entity)
	if e == null:
		return &"none"
	match e.kind:
		WorldIds.EntityKind.MINER:
			if run.miner_state != null and run.miner_state.life(entity) == MinerTransitions.Life.DEAD:
				return &"stopped_by_the_dead"
			var outcome: StringName = on_friendly_hit.call(run, entity, shooter)
			friendly_hits.append({"tick": run.tick, "victim": entity, "shooter": shooter, "outcome": outcome})
			friendly_hit.emit(entity, shooter, run.tick)
			var n: int = int(Variants.number(_friendly_by.get(shooter, 0))) + 1
			_friendly_by[shooter] = n
			if n >= 2:
				eject.call(run, shooter)
			return &"friendly_hit"
		WorldIds.EntityKind.BESS:
			bess_hit.emit(shooter, run.tick)
			return &"bess"
	if run.creatures == null:
		return &"none"
	var c: Creature = run.creatures.creature_of(entity)
	if c == null and e.kind == WorldIds.EntityKind.TAPPER_ARM:
		c = run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER)
	if c == null:
		return &"none"
	var over: bool = counters.hit(run, c.entity_id)
	if not run.creatures.on_hit(run, entity, over):
		return &"none"
	return &"retreat" if over else &"flinch"


## The stub for RSC-05: dead among friends and solo (SHOT_DEAD), unconscious in public with the
## shooter named (FRIENDLY_HIT): no scream either way (SND-15).
func _stub_friendly(run: RunState, victim: int, shooter: int) -> StringName:
	if run.miner_state == null or run.miner_state.miner(victim) == null:
		return &"none"
	if run.header.mode == ServerConfig.Mode.PUBLIC:
		if run.falls != null:
			run.falls.fall_unconscious(run, victim, FallCause.Cause.FRIENDLY_HIT, {"shooter": shooter})
		return &"unconscious"
	run.miner_state.kill(victim, "shot", shooter)
	return &"dead"


## One round from a box on the belt into the cylinder in revolver.reload_per_round, held on
## relight's bit; an 8 np click as it goes in.
func _reload_one(run: RunState, m: int) -> void:
	var it: Item = drawn_revolver(m)
	if it == null or ToolsParts.is_hand(run, m) or rounds_in(it) >= Tuning.i(&"revolver.cylinder_rounds"):
		return
	if run.inventory.hands_of(m).count_of(ItemKinds.Kind.ROUNDS) <= 0:
		return
	var a: TimedAction = TimedAction.make(m, &"reload", Tuning.f(&"revolver.reload_per_round"), InputRecord.HOLD_RELIGHT)
	a.capability = &"belt"
	a.valid = func() -> bool: return drawn_revolver(m) == it and run.inventory.hands_of(m).count_of(ItemKinds.Kind.ROUNDS) > 0
	a.effect = func() -> void:
		if run.inventory.consume(run, m, ItemKinds.Kind.ROUNDS, 1):
			it.state["rounds"] = rounds_in(it) + 1
			if run.noise != null:
				run.noise.emit(NoiseTypes.Type.RELOAD_CLICK, run.registry.get_entity(m).tile(), {"source": m})
			run.inventory.changed.emit(m)
	run.inventory.start_action(run, a)


## An empty cylinder: a dry click only the shooter hears (Proposed).
func _dry_click(run: RunState, slot: int, m: int) -> void:
	if run.audio == null:
		return
	var r: AudioRecord = AudioRecord.new()
	r.type = LocalSounds.Type.DRY_CLICK
	r.start_tick = run.tick
	r.apparent = run.registry.get_entity(m).position
	r.level_np = 0.0
	r.remaining_np = 0.0
	r.duration_s = 0.2
	r.flags = AudioRecord.LOCAL
	run.audio.deliver(slot, r)


func _may_use(run: RunState, m: int) -> bool:
	return run.miner_state == null or run.miner_state.miner(m) == null or Variants.flag(run.miner_state.capabilities(m)["belt"])


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func write_state(writer: SimStateWriter) -> void:
	counters.write_state(writer)
	writer.put_i64(shots.size())
	writer.put_i64(flashes.size())


## NET-09: each creature's hits and retreats (the counters go into snapshots).
func save_state() -> Dictionary:
	return {"counters": counters.counters.duplicate(true)}


func load_state(_r: RunState, state: Dictionary) -> void:
	counters.counters = Variants.dict(state.get("counters", {})).duplicate(true)
