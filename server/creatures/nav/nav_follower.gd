class_name NavFollower
extends RefCounted
## CRT-02: one creature walking a path, a tick at a time, at the speed its ticket gives, never
## further than speed x 0.05 s. Each tick the rest of the path is checked: a tile that closed,
## lit (the dark walker) or fell makes it replan that same tick; a dark walker with no dark path
## makes for the reachable dark tile nearest its target. A closed air door holds the walker
## moth.air_door_hold_s, then it passes and the door stays shut. At ungenerated ground it stops
## at the frontier and replans every tick, so it moves on as soon as the cell arrives.

enum Status { IDLE = 0, MOVING = 1, ARRIVED = 2, HOLDING = 3, FRONTIER = 4, BLOCKED = 5 }

var mode: NavModes.Mode = NavModes.Mode.WALKER
var params: Dictionary = {}
var goal: Vector2i = Vector2i.ZERO
## The goal it settled for when the original had no dark path (DARK only), else the goal.
var heading_for: Vector2i = Vector2i.ZERO
var path: Array[Vector2i] = []
var index: int = 0
var status: Status = Status.IDLE
var replans: int = 0
var hold_ticks: int = 0
var _held_door: Vector2i = Vector2i(2147483647, 0)


## Sets a goal and plans from the creature's tile.
func go(run: RunState, nav: CreatureNav, c: Creature, to: Vector2i, how: NavModes.Mode, extra: Dictionary = {}) -> Status:
	mode = how
	params = extra
	goal = to
	_plan(run, nav, c)
	return status


func stop() -> void:
	path.clear()
	status = Status.IDLE


## One tick: check the path, then advance up to speed x dt along it.
func tick(run: RunState, nav: CreatureNav, c: Creature, speed: float) -> Status:
	if status == Status.IDLE or status == Status.ARRIVED:
		return status
	var rest: Array[Vector2i] = path.slice(index)
	if status == Status.FRONTIER or status == Status.BLOCKED or not nav.native.still_valid(mode, rest, params):
		_plan(run, nav, c)
		if status != Status.MOVING:
			return status
	var budget: float = speed / Tuning.f(&"net.tick_hz")
	var at: Vector2 = c.position(run)
	while budget > 1e-9 and index < path.size():
		var next: Vector2i = path[index]
		if mode <= NavModes.Mode.CRAWLER and _closed_door(run, next) and _held_door != next:
			# Held from the tick it reaches the door; it moves on once the hold has run out.
			hold_ticks += 1
			status = Status.HOLDING
			if hold_ticks <= roundi(Tuning.f(&"moth.air_door_hold_s") * Tuning.f(&"net.tick_hz")):
				break
			_held_door = next
			hold_ticks = 0
			status = Status.MOVING
		var centre: Vector2 = Vector2(next) + Vector2(0.5, 0.5)
		var d: float = at.distance_to(centre)
		if d <= budget:
			at = centre
			budget -= d
			index += 1
		else:
			at += (centre - at) / d * budget
			budget = 0.0
	if at != c.position(run):
		c.system.move_to(run, c, at)
	if index >= path.size():
		status = Status.ARRIVED
	return status


func _plan(run: RunState, nav: CreatureNav, c: Creature) -> void:
	replans += 1
	var from: Vector2i = c.tile(run)
	var result: Dictionary = nav.native.path(mode, from, goal, params)
	heading_for = goal
	if not Variants.flag(result["found"]) and mode == NavModes.Mode.DARK and not Variants.flag(result["touched_unloaded"]):
		var nearest: Variant = nav.native.reachable_dark_tile_nearest(goal, from, params)
		if nearest != null:
			heading_for = nearest
			result = nav.native.path(mode, from, heading_for, params)
	if Variants.flag(result["found"]):
		path = result["tiles"]
		index = 1
		status = Status.MOVING if path.size() > 1 else Status.ARRIVED
	else:
		path.clear()
		index = 0
		status = Status.FRONTIER if Variants.flag(result["touched_unloaded"]) else Status.BLOCKED


static func _closed_door(run: RunState, tile: Vector2i) -> bool:
	return run.mine != null and run.mine.native.effective_material(tile) == WorldIds.TileMaterial.WOODEN_DOOR
