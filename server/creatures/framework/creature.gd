class_name Creature
extends RefCounted
## CRT-01's base for the Moth, the Tapper and the Stythe. A creature is a state machine over
## CreatureState data, holds one sense (CRT-04 to CRT-17 pick it), and moves only through
## CreatureSystem.move_to, which refuses nothing but logs any tick's step past its speed limit.
## Nothing here is sent to a client; a creature appears to players only through VIS-03's seen set.

var kind: WorldIds.EntityKind = WorldIds.EntityKind.NONE
var entity_id: int = 0
var system: CreatureSystem = null
## FND-06's stream for this creature (creatures.moth, creatures.tapper, creatures.stythe).
var rng: LbRng = null
var states: Dictionary = {}
var state: CreatureState = null
var wind_up: CreatureWindUp = null
## The miner entity it holds in a grab or carry, 0 if none (RSC-03 releases it).
var grabbing: int = 0
## The tick a retreat ends, -1 when not retreating.
var retreat_until: int = -1
## Fastest it may move this tick, tiles per second (the no-teleport check).
var max_speed: float = 5.0
## The body's radius for a shot, while its state is hittable (Proposed: Moth 0.6, Stythe 0.35,
## the Tapper's arm tip 0.3).
var body_radius: float = 0.5


## Each creature ticket returns its states; the first is where it starts.
func define_states() -> Array[CreatureState]:
	return [CreatureState.make(&"idle")]


## Each creature ticket returns its guard predicate (run, miner_entity) -> bool. None is an error.
func guard_predicate() -> Callable:
	return Callable()


## Once, when the spawner has placed it (its entity, stream and states exist).
func on_spawned(_run: RunState) -> void:
	pass


## Once a tick, at stage 7, after the defender rule has weighed pending wind-ups.
func think(_run: RunState) -> void:
	pass


## FND-08's freeze_ai: every absolute tick this creature keeps moves on by `by` (the frozen ticks),
## so its timers resume where they paused. -1 (unset) stays. Each creature adds its own fields.
func shift_timers(by: int) -> void:
	retreat_until = later(retreat_until, by)


static func later(t: int, by: int) -> int:
	return t + by if t >= 0 else t


func kind_name() -> StringName:
	return StringName(str(WorldIds.EntityKind.find_key(kind)).to_lower())


func position(run: RunState) -> Vector2:
	var e: SimEntity = run.registry.get_entity(entity_id)
	return e.position if e != null else Vector2.ZERO


func tile(run: RunState) -> Vector2i:
	var p: Vector2 = position(run)
	return Vector2i(floori(p.x), floori(p.y))


## The ring of the tile it stands on (FND-07).
func ring(run: RunState) -> int:
	return WorldCoords.ring_of_point(position(run))


func is_retreating() -> bool:
	return retreat_until >= 0


## The circle a shot can hit now: its radius, or 0 when nothing of it can be hit.
func hit_body() -> float:
	return body_radius if state != null and state.hittable else 0.0


## VIS-08: the flame state this creature's tell puts on flames within flame_tell_reach() tiles,
## straight-line (FlameFlags.TREMBLE for the Moth; GUTTER for the Stythe in Hunt, WindUp, Drag and
## Collect, CRT-14), or 0.
func flame_tell() -> int:
	return 0


func flame_tell_reach() -> float:
	return 0.0


func enter(run: RunState, state_name: StringName, reason: String = "") -> void:
	if not states.has(state_name):
		push_error("%s: no state %s" % [kind_name(), state_name])
		return
	var from: StringName = state.name if state != null else &""
	state = states[state_name]
	if system != null:
		system.log.add(run.tick, &"state", {"creature": kind_name(), "from": from, "to": state_name, "reason": reason})


## Hooks each creature ticket fills in.
func on_relax_started(_run: RunState) -> void:
	pass


func on_relax_ended(_run: RunState) -> void:
	pass


func on_retreat_started(_run: RunState, _cause: String) -> void:
	pass


## toward_base: the retreat ended after the engine caught and before the cage left (§3.6).
func on_retreat_ended(_run: RunState, _toward_base: bool) -> void:
	pass


func on_grab_dropped(_run: RunState) -> void:
	pass


func on_flinch(_run: RunState) -> void:
	pass


func on_wind_up_finished(_run: RunState, _w: CreatureWindUp) -> void:
	pass


## RSC-03: a grab this creature held has ended. By default its hunt stands down with it.
func on_grab_ended(run: RunState, _grab: GrabHold, _outcome: GrabHold.Outcome) -> void:
	grabbing = 0
	if system != null:
		system.gate.stand_down(run, self, "grab ended")
