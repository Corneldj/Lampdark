extends Creature
## A stand-in creature (CRT-01) for the kit and the creature tests, until each kind's own
## ticket supplies the real one: idle (no place), hunt (chosen, fills a place, tells), carry (a
## consequence, fills no place), buried (cannot be hit) and retreat. Its guard holds within
## `guard_range` tiles.

var guard_range: float = 5.0
var with_guard: bool = true
var relax_started: int = 0
var retreats_ended: Array[bool] = []
var flinches: int = 0
var grabs_dropped: int = 0
## Each think() moves it by this much (the no-teleport tests).
var drift: Vector2 = Vector2.ZERO
## CRT-02: when set, think() walks this follower's path at `speed` tiles/s.
var follower: NavFollower = null
var speed: float = 2.5


func _init(creature_kind: WorldIds.EntityKind = WorldIds.EntityKind.MOTH) -> void:
	kind = creature_kind


func define_states() -> Array[CreatureState]:
	return [CreatureState.make(&"idle"),
		CreatureState.make(&"hunt", {"fills_cap_place": true, "chosen_entry": true, "plays_tell": true}),
		CreatureState.make(&"carry"),
		CreatureState.make(&"buried", {"hittable": false}),
		CreatureState.make(&"retreat")]


func guard_predicate() -> Callable:
	if not with_guard:
		return Callable()
	return func(run: RunState, miner: int) -> bool:
		return run.registry.get_entity(miner).position.distance_to(position(run)) <= guard_range


func think(run: RunState) -> void:
	if follower != null:
		follower.tick(run, system.nav, self, speed)
	if drift != Vector2.ZERO:
		system.move_to(run, self, position(run) + drift)


func on_relax_started(_run: RunState) -> void:
	relax_started += 1


func on_retreat_ended(_run: RunState, toward_base: bool) -> void:
	retreats_ended.append(toward_base)


func on_flinch(_run: RunState) -> void:
	flinches += 1


func on_grab_dropped(_run: RunState) -> void:
	grabs_dropped += 1
