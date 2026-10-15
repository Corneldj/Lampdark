class_name MovementSystem
extends SimSystem
## MNR-01 on the server (stage 3, MINERS: after inputs, before the light grid and seen sets):
## every miner takes the input NET-03 consumed for its slot through MinerMotion's shared step,
## its speed modifiers and the most restrictive gait constraints, and makes its steps through
## SND-02. Pace queries, the together helper and wall bumps are served from here. Modifiers,
## the wound slot and the step accumulator never leave the server.

## VIS-07 listens: a new contact with a solid tile, and its material (no noise).
## Once per contact with a solid tile: its effective material (a shut gate is steel) and the tile.
signal wall_bumped(slot: int, material: int, tile: Vector2i)
## MNR-02: a run just ended (panting begins).
signal run_ended(slot: int)


class Miner:
	extends RefCounted
	var slot: int = -1
	var entity_id: int = 0
	var state: MinerMotion.State = MinerMotion.State.new()
	var modifiers: SpeedModifiers = SpeedModifiers.new()
	var stamina: Stamina = Stamina.new()
	## The life state last tick (MNR-03), to stop panting on a fall and refill on a revive.
	var last_life: int = 0
	## owner -> MinerMotion.Constraints
	var requests: Dictionary = {}


var params: MinerMotion.Params
var mine: Mine = null
var still_speed: float = 0.3
var together_tiles: float = 6.0
var _miners: Dictionary = {}
var _run: RunState = null
## Per-tick cache of together answers, keyed by the pair.
var _together: Dictionary = {}
var _together_tick: int = -1


func _init(world: Mine = null) -> void:
	mine = world
	params = MinerMotion.Params.from_tuning()
	still_speed = Tuning.f(&"moth.widow_min_speed")
	together_tiles = Tuning.f(&"movement.together_path_tiles")


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 10


func system_name() -> String:
	return "movement"


## A miner joins at its entity's position (MOD and LFT spawn it; the kit calls this).
func add_miner(slot: int, entity_id: int, entity_position: Vector2, facing: int = 0) -> Miner:
	var m: Miner = Miner.new()
	m.slot = slot
	m.entity_id = entity_id
	m.state.x = entity_position.x
	m.state.y = entity_position.y
	m.state.facing = facing
	_miners[slot] = m
	return m


func remove_miner(slot: int) -> void:
	_miners.erase(slot)


## Every slot with a miner, ascending.
func miner_slots() -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in _miners.keys():
		out.append(int(Variants.number(raw)))
	out.sort()
	return out


func miner(slot: int) -> Miner:
	if not _miners.has(slot):
		return null
	var m: Miner = _miners[slot]
	return m


func modifiers(slot: int) -> SpeedModifiers:
	var m: Miner = miner(slot)
	return m.modifiers if m != null else null


## A gait request from one owner (MNR-02, MNR-03, MNR-13, MNR-14, MNR-16); clear it with null.
func set_constraint(slot: int, owner: StringName, request: MinerMotion.Constraints) -> void:
	var m: Miner = miner(slot)
	if m == null:
		return
	if request == null:
		m.requests.erase(owner)
	else:
		m.requests[owner] = request


## Puts a miner somewhere without walking it there (MNR-13: a carried body riding on its carrier,
## a body set down). The registry follows at once.
func place(run: RunState, entity: int, at: Vector2) -> void:
	for slot: int in miner_slots():
		var m: Miner = _miners[slot]
		if m.entity_id == entity:
			m.state.x = at.x
			m.state.y = at.y
			m.state.speed = 0.0
	if run.registry.has(entity):
		run.registry.move(entity, at)


func facing_of(slot: int) -> int:
	var m: Miner = miner(slot)
	return m.state.facing if m != null else 0


## Still: at or below CRT-07's moth.widow_min_speed (0.3 tiles/s) over the last tick.
func is_still(slot: int) -> bool:
	var m: Miner = miner(slot)
	return m == null or m.state.speed <= still_speed + 1e-9


## At a crouch's pace or slower (VIS-07's feeling, MNR-07's flint relighting).
func at_crouch_pace_or_slower(slot: int) -> bool:
	var m: Miner = miner(slot)
	return m == null or m.state.speed <= params.crouch_speed + 1e-9


## Together: the walkable path between two miners is 6 tiles or less (doors as they stand now).
func together(slot_a: int, slot_b: int) -> bool:
	var a: Miner = miner(slot_a)
	var b: Miner = miner(slot_b)
	if a == null or b == null or mine == null:
		return false
	var now: int = _run.tick if _run != null else -1
	if now != _together_tick:
		_together.clear()
		_together_tick = now
	var key: Vector2i = Vector2i(mini(slot_a, slot_b), maxi(slot_a, slot_b))
	if not _together.has(key):
		var from: Vector2i = Vector2i(floori(a.state.x), floori(a.state.y))
		var to: Vector2i = Vector2i(floori(b.state.x), floori(b.state.y))
		var answer: Mine.PathAnswer = mine.path_distance(from, to, together_tiles + 0.5)
		_together[key] = answer.distance >= 0.0 and answer.distance <= together_tiles + 1e-6
	return Variants.flag(_together[key])


func tick(run: RunState) -> void:
	_run = run
	var dt: float = 1.0 / Tuning.f(&"net.tick_hz")
	var is_solid: Callable = _solid
	var slots: Array = _miners.keys()
	slots.sort()
	for raw: Variant in slots:
		var m: Miner = _miners[raw]
		var entity: SimEntity = run.registry.get_entity(m.entity_id)
		if entity == null:
			_miners.erase(raw)
			continue
		var consumed: InputBuffer.Consumed = run.input_for(m.slot)
		var input: InputRecord = consumed.record if consumed != null else null
		_follow_life(run, m)
		var c: MinerMotion.Constraints = MinerMotion.Constraints.most_restrictive(m.requests.values())
		c.run_allowed = c.run_allowed and m.stamina.allow_run(input)
		var result: MinerMotion.Result = MinerMotion.step(m.state, input, c, m.modifiers.factor(), is_solid, dt, params)
		m.state = result.state
		var was_running: bool = m.stamina.running
		var held: bool = input != null and input.gait == InputRecord.Gait.RUN and input.move_dir != InputRecord.NO_DIRECTION
		var pants: int = m.stamina.after_step(m.state.gait == MinerMotion.RUN, held, run.tick)
		if was_running and not m.stamina.running:
			run_ended.emit(m.slot)
		if pants > 0 and run.noise != null:
			run.noise.emit(NoiseTypes.Type.PANTING, Vector2i(floori(m.state.x), floori(m.state.y)), {"source": m.entity_id})
		run.registry.move(m.entity_id, Vector2(m.state.x, m.state.y))
		if run.noise != null:
			# SND-01's player listener sits on the miner; its id is the slot (creatures use others).
			run.noise.set_player_listener(m.slot, Vector2i(floori(m.state.x), floori(m.state.y)))
		for _i: int in result.steps:
			_step_noise(run, m, result.step_gait, entity)
		for tile: Vector2i in result.bumped:
			wall_bumped.emit(m.slot, mine.native.effective_material(tile) if mine != null else 0, tile)


## MNR-03's life state: the unconscious and dead stop panting; a revive comes round rested.
func _follow_life(run: RunState, m: Miner) -> void:
	if run.miner_state == null or run.miner_state.miner(m.entity_id) == null:
		return
	var life: int = run.miner_state.life(m.entity_id)
	if life >= MinerTransitions.Life.UNCONSCIOUS:
		m.stamina.stop()
	elif m.last_life == MinerTransitions.Life.UNCONSCIOUS:
		m.stamina.refill()
	m.last_life = life


## MNR-02's queries.
func is_running(slot: int) -> bool:
	var m: Miner = miner(slot)
	return m != null and m.stamina.running


func is_panting(slot: int) -> bool:
	var m: Miner = miner(slot)
	return m != null and m.stamina.panting()


func voice_loss_flag(slot: int) -> bool:
	var m: Miner = miner(slot)
	return m != null and m.stamina.voice_loss()


## SND-14's breath-hold: panting events are suppressed while it lasts; the timer runs on.
func set_breath_hold(slot: int, active: bool) -> void:
	var m: Miner = miner(slot)
	if m != null:
		m.stamina.breath_hold = active


func _step_noise(run: RunState, m: Miner, gait: int, entity: SimEntity) -> void:
	if run.noise == null:
		return
	var type: NoiseTypes.Type = NoiseTypes.Type.STEP_RUN if gait == MinerMotion.RUN else NoiseTypes.Type.STEP_WALK
	var level: float = run.noise.catalogue.entry(type).np
	var override: float = m.modifiers.step_np_override()
	if override > level:
		type = NoiseTypes.Type.STEP_HEAVY
	run.noise.emit(type, Vector2i(floori(m.state.x), floori(m.state.y)), {"source": entity.id})


func _solid(tile: Vector2i) -> bool:
	return mine != null and not mine.native.is_walkable(tile)


func write_state(writer: SimStateWriter) -> void:
	var slots: Array = _miners.keys()
	slots.sort()
	writer.put_i64(slots.size())
	for raw: Variant in slots:
		var m: Miner = _miners[raw]
		writer.put_i64(m.slot)
		writer.put_i64(m.entity_id)
		writer.put_f64(m.state.x)
		writer.put_f64(m.state.y)
		writer.put_i64(m.state.facing)
		writer.put_f64(m.state.step_accum)
		writer.put_i64(m.state.gait)
		m.modifiers.write_state(writer)
		m.stamina.write_state(writer)


## NET-09: each miner's place, facing and stamina.
func save_state() -> Dictionary:
	var out: Dictionary = {}
	for slot: int in miner_slots():
		var m: Miner = _miners[slot]
		out[slot] = {"entity": m.entity_id, "x": m.state.x, "y": m.state.y, "facing": m.state.facing,
			"stamina": StateDicts.pick(m.stamina, ["pool_ms", "running", "latched_off", "pant_start", "pant_next", "breath_hold"])}
	return {"miners": out}


func load_state(_r: RunState, state: Dictionary) -> void:
	var miners: Dictionary = Variants.dict(state.get("miners", {}))
	for raw: Variant in miners.keys():
		var d: Dictionary = miners[raw]
		var m: Miner = add_miner(int(Variants.number(raw)), int(Variants.number(d["entity"])),
			Vector2(Variants.number(d["x"]), Variants.number(d["y"])), int(Variants.number(d["facing"])))
		StateDicts.put(m.stamina, Variants.dict(d["stamina"]))
