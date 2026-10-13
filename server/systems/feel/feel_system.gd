class_name FeelSystem
extends SimSystem
## VIS-07 (stage MINERS, after the inventory): feeling and wall bumps (Gameplay §5.5). A miner's
## interaction, not a sense: its range check may rewind (NET-06), so it lives outside the
## perception modules (check_module_deps.sh). Holding
## interact vision.feel_hold_s at a crouch's pace or slower, with nothing in touch range seen with
## identity, feels the nearest feelable thing within vision.touch_range_tiles, at any facing but
## never through a wall: the miner's client gets only {caption_key, bearing_q, verb_key}
## (FeelMessages), never the thing. The felt thing is remembered vision.felt_target_valid_s, and
## interacting again uses it as if identified. Feeling is silent, touches no creature sense and
## springs nothing. Bumping a wall the miner cannot see sends that client its material's caption
## (and the client rumbles). Server-only, except the owner's FEEL messages.

signal felt(miner: int, entity: int)

const FEELABLE: Array[WorldIds.EntityKind] = [WorldIds.EntityKind.MINER, WorldIds.EntityKind.ITEM, WorldIds.EntityKind.TRAP,
	WorldIds.EntityKind.COAT_HEAP, WorldIds.EntityKind.MOTH, WorldIds.EntityKind.PHONE, WorldIds.EntityKind.STYTHE,
	WorldIds.EntityKind.BESS]
const MATERIALS: String = "res://data/world/materials.json"

## miner -> {entity, until, signature}
var felt_targets: Dictionary = {}
## [slot, bytes] waiting for Replication to send (to that client only).
var outbox: Array[Array] = []
## kind -> (run, entity) -> String: an owning ticket's caption (HAZ-01/02's traps: jaws or boards).
var caption_hooks: Dictionary = {}
## kind -> (run, miner, entity) -> bool: what interacting again on a felt thing does.
var felt_uses: Dictionary = {}
## Every answer given: {tick, miner, caption_key, verb_key} (tests; never sent beyond the owner).
var answers: Array[Dictionary] = []
var _material_caption: Dictionary = {}
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 25


func system_name() -> String:
	return "feel"


func bind(run: RunState) -> void:
	_run = run
	_load_materials()
	if run.movement != null:
		run.movement.wall_bumped.connect(_on_bump)
	# Interacting again on a felt body lifts it into a fireman's carry (RSC-01, MNR-13).
	register_felt_use(WorldIds.EntityKind.MINER, func(r: RunState, miner: int, entity: int) -> bool:
		if r.falls == null or r.falls.body_of(entity) == null:
			return false
		return r.inventory.start_action(r, r.falls.lift_action(r, miner, entity)))


## What interacting again on a felt thing of `kind` does (MNR-04, MNR-05, MNR-13, LFT-12).
func register_felt_use(kind: WorldIds.EntityKind, handler: Callable) -> void:
	felt_uses[kind] = handler


## The thing a miner felt, while still usable (within touch range, unchanged, inside the window).
func felt_target(run: RunState, miner: int) -> int:
	var f: Dictionary = felt_targets.get(miner, {})
	if f.is_empty() or run.tick >= int(Variants.number(f["until"])):
		return 0
	var entity: int = int(Variants.number(f["entity"]))
	if not run.registry.has(entity) or not run.registry.has(miner):
		return 0
	if run.registry.get_entity(entity).position.distance_to(run.registry.get_entity(miner).position) > Tuning.f(&"vision.touch_range_tiles"):
		return 0
	if _signature(run, entity) != str(f["signature"]):
		return 0
	return entity


func tick(run: RunState) -> void:
	_run = run
	if run.movement == null or run.inventory == null:
		return
	var by_entity: Dictionary = {}
	for slot: int in run.movement.miner_slots():
		by_entity[run.movement.miner(slot).entity_id] = slot
	var miners: Array = by_entity.keys()
	miners.sort()
	for raw: Variant in miners:
		var m: int = int(Variants.number(raw))
		var slot: int = int(Variants.number(by_entity[raw]))
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null or run.inventory.actions.has(m) or not run.inventory.is_fresh(m, c.record.holds, InputRecord.HOLD_INTERACT):
			continue
		# Something identified in touch range (a teammate, a lever, an item): interact acts on it.
		if _identified_near(run, m, slot) or not run.inventory.targets.pick(run, m, slot, run.inventory.world).is_empty():
			continue
		var target: int = felt_target(run, m)
		if target != 0:
			var kind: int = run.registry.get_entity(target).kind
			if felt_uses.has(kind):
				var use: Callable = felt_uses[kind]
				if Variants.flag(use.call(run, m, target)):
					run.inventory.mark_spent(m, InputRecord.HOLD_INTERACT)
					continue
		run.inventory.mark_spent(m, InputRecord.HOLD_INTERACT)
		if not _may_feel(run, m):
			continue
		var a: TimedAction = TimedAction.make(m, &"feel", Tuning.f(&"vision.feel_hold_s"), InputRecord.HOLD_INTERACT)
		a.needs_crouch = true
		a.effect = func() -> void: resolve(run, m, slot)
		run.inventory.start_action(run, a)


## Carrying (both hands), Grabbed, unconscious and dead miners cannot feel. A drawn revolver or a
## can in the free hand does not stop it (§4.7: "feeling still works").
func _may_feel(run: RunState, miner: int) -> bool:
	if run.inventory.hands_of(miner).two_handed:
		return false
	if run.miner_state != null and run.miner_state.miner(miner) != null:
		var life: int = run.miner_state.life(miner)
		return life == MinerTransitions.Life.UPRIGHT or life == MinerTransitions.Life.CAUGHT
	return true


## The feel lands: the nearest feelable thing in touch range, by a clear segment.
func resolve(run: RunState, miner: int, slot: int) -> void:
	var me: Vector2 = run.registry.get_entity(miner).position
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var c: InputBuffer.Consumed = run.input_for(slot)
	var shown: int = c.shown_tick if c != null else run.tick
	var best: int = 0
	var best_d: float = INF
	var ids: Array = Array(run.registry.ids())
	ids.sort()
	for raw: Variant in ids:
		var id: int = int(Variants.number(raw))
		var e: SimEntity = run.registry.get_entity(id)
		if id == miner or not FEELABLE.has(e.kind):
			continue
		var d: float = me.distance_to(e.position)
		var in_reach: bool = d <= reach
		if not in_reach and _moves(e.kind) and run.rewind != null:
			in_reach = run.rewind.in_range_at(miner, id, reach, shown)
		if not in_reach or not clear_segment(run, me, e.position):
			continue
		if d < best_d:
			best_d = d
			best = id
	var bytes: PackedByteArray
	if best == 0:
		bytes = FeelMessages.feel("feel.nothing", FeelMessages.NO_BEARING, "")
		answers.append({"tick": run.tick, "miner": miner, "caption_key": "feel.nothing", "verb_key": ""})
	else:
		var target: SimEntity = run.registry.get_entity(best)
		var caption: String = caption_key(run, best)
		var verb: String = verb_key(run, best)
		bytes = FeelMessages.feel(caption, bearing_q(target.position - me), verb)
		answers.append({"tick": run.tick, "miner": miner, "caption_key": caption, "verb_key": verb, "entity": best})
		felt_targets[miner] = {"entity": best, "signature": _signature(run, best),
			"until": run.tick + roundi(Tuning.f(&"vision.felt_target_valid_s") * Tuning.f(&"net.tick_hz"))}
		if target.kind == WorldIds.EntityKind.ITEM:
			run.inventory.targets.note_felt(miner, best)
		felt.emit(miner, best)
	outbox.append([slot, bytes])


## The caption key for a feelable entity (§5.5's table).
func caption_key(run: RunState, entity: int) -> String:
	var e: SimEntity = run.registry.get_entity(entity)
	if caption_hooks.has(e.kind):
		var hook: Callable = caption_hooks[e.kind]
		return str(hook.call(run, entity))
	match e.kind:
		WorldIds.EntityKind.MINER:
			var b: BodyState = run.falls.body_of(entity) if run.falls != null else null
			if b != null:
				return "feel.body_cold" if b.dead else "feel.body_breathing"
			return "feel.someone_standing"
		WorldIds.EntityKind.ITEM:
			var it: Item = run.inventory.world.item_at(entity)
			return "feel.item." + str(ItemKinds.Kind.find_key(it.kind)).to_lower() if it != null else "feel.nothing"
		WorldIds.EntityKind.TRAP:
			return "feel.iron_jaws"
		WorldIds.EntityKind.COAT_HEAP:
			return "feel.heap_of_coats"
		WorldIds.EntityKind.MOTH:
			var moth: Moth = run.creatures.creature_of(entity) as Moth if run.creatures != null else null
			# A sleeping Moth is felt exactly as a heap of coats is (CRT-03's feel_reply).
			return "feel.heap_of_coats" if moth == null or moth.is_sleeping() else "feel.coats_moving"
		WorldIds.EntityKind.PHONE:
			return "feel.telephone"
		WorldIds.EntityKind.STYTHE:
			return "feel.cold_soot"
		WorldIds.EntityKind.BESS:
			return "feel.pony"
	return "feel.nothing"


## What interacting again would do, or "" (a heap and a sleeping Moth: nothing, alike).
func verb_key(run: RunState, entity: int) -> String:
	var e: SimEntity = run.registry.get_entity(entity)
	match e.kind:
		WorldIds.EntityKind.ITEM:
			return "verb.pick_up"
		WorldIds.EntityKind.MINER:
			return "verb.lift" if run.falls != null and run.falls.body_of(entity) != null else "verb.ring"
		WorldIds.EntityKind.PHONE:
			return "verb.crank"
	return ""


## 0-15 steps of vision.feel_bearing_step_deg from east, clockwise (+y down): the step whose
## direction is nearest, by deterministic unit vectors (no libm trig on the server).
static func bearing_q(d: Vector2) -> int:
	var steps: int = roundi(360.0 / Tuning.f(&"vision.feel_bearing_step_deg"))
	var n: Vector2 = d.normalized() if d.length() > 1e-9 else Vector2.RIGHT
	var best: int = 0
	var best_dot: float = -INF
	for i: int in steps:
		var u: PackedFloat64Array = LbDetMath.unit(float(i) / steps)
		var dot: float = n.x * u[0] + n.y * u[1]
		if dot > best_dot + 1e-12:
			best_dot = dot
			best = i
	return best


## True if the straight segment between two points crosses no tile a miner could not pass (rock,
## a closed door, a shut gate), nor slips between two such tiles at a corner.
static func clear_segment(run: RunState, from: Vector2, to: Vector2) -> bool:
	if run.mine == null:
		return true
	var t: Vector2i = Vector2i(floori(from.x), floori(from.y))
	var end: Vector2i = Vector2i(floori(to.x), floori(to.y))
	var d: Vector2 = to - from
	var step: Vector2i = Vector2i(signi(roundi(signf(d.x))), signi(roundi(signf(d.y))))
	var t_max: Vector2 = Vector2(INF, INF)
	var t_delta: Vector2 = Vector2(INF, INF)
	if step.x != 0:
		var next_x: float = t.x + (1.0 if step.x > 0 else 0.0)
		t_max.x = (next_x - from.x) / d.x
		t_delta.x = absf(1.0 / d.x)
	if step.y != 0:
		var next_y: float = t.y + (1.0 if step.y > 0 else 0.0)
		t_max.y = (next_y - from.y) / d.y
		t_delta.y = absf(1.0 / d.y)
	var guard: int = 0
	while t != end and guard < 64:
		guard += 1
		if absf(t_max.x - t_max.y) < 1e-9:
			# Through a corner: both side tiles must be open.
			if not _open(run, t + Vector2i(step.x, 0)) or not _open(run, t + Vector2i(0, step.y)):
				return false
			t += step
			t_max += t_delta
		elif t_max.x < t_max.y:
			t.x += step.x
			t_max.x += t_delta.x
		else:
			t.y += step.y
			t_max.y += t_delta.y
		if t != end and not _open(run, t):
			return false
	return true


static func _open(run: RunState, tile: Vector2i) -> bool:
	return run.mine.native.is_walkable(tile, false)


static func _moves(kind: int) -> bool:
	return kind == WorldIds.EntityKind.MINER or kind == WorldIds.EntityKind.STYTHE or kind == WorldIds.EntityKind.BESS \
		or kind == WorldIds.EntityKind.MOTH


## A felt thing stays usable while unchanged: its kind, and for a miner its life state.
func _signature(run: RunState, entity: int) -> String:
	var e: SimEntity = run.registry.get_entity(entity)
	if e == null:
		return ""
	var life: int = run.miner_state.life(entity) if run.miner_state != null and run.miner_state.miner(entity) != null else -1
	return "%d:%d" % [e.kind, life]


func _identified_near(run: RunState, miner: int, slot: int) -> bool:
	if run.vision == null:
		return false
	var me: Vector2 = run.registry.get_entity(miner).position
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var identified: PackedInt64Array = run.vision.frame_for(slot).get("identified", PackedInt64Array())
	for id: int in identified:
		if id != miner and run.registry.has(id) and run.registry.get_entity(id).position.distance_to(me) <= reach:
			return true
	return false


## MNR-01's bump: an unseen wall's caption to that client (one per contact; silent).
func _on_bump(slot: int, material: int, tile: Vector2i) -> void:
	if _run == null or _run.movement == null or _run.movement.miner(slot) == null:
		return
	var key: String = str(_material_caption.get(material, ""))
	if key.is_empty():
		return
	if _run.vision != null:
		var me: SimEntity = _run.registry.get_entity(_run.movement.miner(slot).entity_id)
		if _run.vision.native.tile_seen(slot, tile) or (me != null and _run.vision.native.tile_seen(slot, me.tile())):
			return
	outbox.append([slot, FeelMessages.bump(key)])
	answers.append({"tick": _run.tick, "miner": _run.movement.miner(slot).entity_id, "caption_key": key, "verb_key": "", "bump": true})


func _load_materials() -> void:
	var data: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(MATERIALS)))
	var table: Dictionary = Variants.dict(data.get("materials", {}))
	for raw: Variant in table.keys():
		var name: String = str(raw)
		if WorldIds.TileMaterial.has(name):
			_material_caption[int(Variants.number(WorldIds.TileMaterial[name]))] = str(Variants.dict(table[raw]).get("caption_key", ""))


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = felt_targets.keys()
	ids.sort()
	for raw: Variant in ids:
		var f: Dictionary = felt_targets[raw]
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(int(Variants.number(f["entity"])))
		writer.put_i64(int(Variants.number(f["until"])))
