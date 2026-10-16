class_name StretcherRules
extends RefCounted
## MNR-14: what only a stretcher does (Gameplay §4.3, §11.4, §11.5), for LoadCarry. Laying an
## unconscious or dead body on a set-down stretcher is the ring's lay option: movement.
## stretcher_lay_time of held interact in touch range of the body, the lamp hooked from the start
## like a lift (Proposed: it takes both hands), onto the nearest free stretcher within touch range
## of the body. A loaded stretcher set down with its body within touch range of a free medbay table
## puts the body on it after movement.stretcher_to_table_time. Server-only.

## Whether `actor` may lay `body` on a stretcher now: the body lies free (no carry, drag, trap,
## table or load), the actor stands upright with the free hand empty and both hands unspoken for,
## and a free stretcher lies within touch range of the body.
static func may_lay(run: RunState, actor: int, body: int) -> bool:
	if run.loads == null or run.falls == null or run.inventory == null or actor == body:
		return false
	var b: BodyState = run.falls.body_of(body)
	if b == null or b.carried_by != 0 or b.dragged_by != 0 or b.held_by_trap or b.on_load != 0:
		return false
	if run.miner_state != null and run.miner_state.miner(actor) != null and run.miner_state.life(actor) != MinerTransitions.Life.UPRIGHT:
		return false
	var h: HandsAndBelt = run.inventory.hands_of(actor)
	if h.free_hand != null or h.two_handed or run.loads.carrying(actor):
		return false
	return free_near(run, run.registry.get_entity(body).position) != 0


## The lay: held interact for movement.stretcher_lay_time; the lamp hooks at its start and comes
## back when it ends; the body then lies on the stretcher (cancelled if the stretcher is taken).
static func lay_action(run: RunState, actor: int, body: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(actor, &"lay_on_stretcher", Tuning.f(&"movement.stretcher_lay_time"), InputRecord.HOLD_INTERACT)
	a.target_entity = body
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	var hooked: Array[bool] = [false]
	a.valid = func() -> bool:
		if not hooked[0]:
			return may_lay(run, actor, body)
		var b: BodyState = run.falls.body_of(body)
		return b != null and b.carried_by == 0 and b.dragged_by == 0 and b.on_load == 0 \
			and free_near(run, run.registry.get_entity(body).position) != 0
	a.on_start = func() -> void:
		hooked[0] = may_lay(run, actor, body) and run.inventory.begin_two_handed(run, actor)
	var unhook: Callable = func() -> void:
		if hooked[0]:
			hooked[0] = false
			run.inventory.end_two_handed(actor)
	a.cancelled.connect(func(_action: TimedAction, _reason: StringName) -> void: unhook.call())
	a.effect = func() -> void:
		unhook.call()
		var stretcher: int = free_near(run, run.registry.get_entity(body).position)
		if stretcher != 0:
			run.loads.lay_body(run, stretcher, body)
	return a


## The free stretcher (set down, empty, nobody holding it) nearest `at` within touch range of its
## centre, or 0; ties to the lower entity.
static func free_near(run: RunState, at: Vector2) -> int:
	var best: int = 0
	var best_d: float = INF
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	for e: int in run.loads.lying(run, at, reach + Tuning.f(&"movement.stretcher_length")):
		var it: Item = run.inventory.world.item_at(e)
		if it.kind != ItemKinds.Kind.STRETCHER or run.loads.is_held(it.uid) or run.loads.body_on(run, it.uid) != 0:
			continue
		var d: float = run.registry.get_entity(e).position.distance_to(at)
		if d <= reach + 1e-9 and d < best_d:
			best = e
			best_d = d
	return best


## The nearest free medbay table whose centre is within touch range of `at`, or (-1, -1).
static func free_table_near(run: RunState, at: Vector2) -> Vector2i:
	if run.base_camp == null:
		return Vector2i(-1, -1)
	var medbay: Medbay = run.base_camp.cupboard()
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for t: Vector2i in medbay.tables:
		if int(Variants.number(medbay.bodies.get(t, 0))) != 0:
			continue
		var d: float = at.distance_to(Vector2(t) + Vector2(0.5, 0.5))
		if d <= reach + 1e-9 and d < best_d:
			best = t
			best_d = d
	return best
