class_name LoadSegment
extends RefCounted
## MNR-14: a two-person load as a rigid segment (Gameplay §4.3; GDD §15.8): the stretcher
## (movement.stretcher_length) or the drum gear (movement.drum_gear_length), a carrier at each end.
## No physics. Each tick it moves at its speed along the average of the two carriers' movement
## inputs, its heading turning at most movement.load_turn_per_tick toward it; an average more than
## 90° from the heading backs it up, the heading turning toward its reverse (Proposed). Inputs over
## movement.load_knock_angle apart, or one moving while the other stands, for over
## movement.load_knock_time by issue tick: one knock and a halt, held until the inputs agree again;
## a shorter disagreement keeps the last agreed velocity (Proposed). A Hurt or trap-wounded carrier
## slows it by movement.wound_gait_multiplier.
##
## The load and its carriers are one capsule: the segment between the ends, a body wide
## (movement.body_radius), so the carriers are its end caps. It never overlaps a solid tile: a move
## that would is tried as rotation only, then translation only, then refused without a knock, so
## long loads jam at tight corners.
##
## By issue tick (NET-03's stamps): a disagreement starts at the newer of the two inputs' stamps and
## lasts until the older one, so a carrier whose inputs arrive later never makes a knock, only a
## real disagreement does. Headings are u16 facings like a miner's (0 east, a quarter turn south)
## and directions come from LbDetMath's bit-identical unit vectors, so the same inputs move it the
## same on every platform. Pure: Loads drives it and places the carriers at its ends.

## One carrier's push this tick (NET-03's consumed input): a movement direction (0-254, or
## InputRecord.NO_DIRECTION standing), the tick its client showed when it was issued, and whether
## the input starved (the carrier's intent is unknown: the load waits, with no knock).
class Push:
	extends RefCounted
	var dir: int = InputRecord.NO_DIRECTION
	var stamp: int = 0
	var starved: bool = false

	static func of(direction: int, issued: int, is_starved: bool = false) -> Push:
		var p: Push = Push.new()
		p.dir = direction
		p.stamp = issued
		p.starved = is_starved
		return p


## What one tick did.
class Result:
	extends RefCounted
	var moved: bool = false
	var knock: bool = false
	## The move was cut to rotation or translation only, or refused.
	var blocked: bool = false
	## Step events due at each carrier this tick.
	var steps: int = 0


## An average further than this from the heading backs the load up: 90°, plus a little over one
## input step, so a keyboard's quarter turn (90.35° as an input byte) still turns it forward.
const REVERSE_BEYOND: int = 16384 + 512
const SKIN: float = 1e-9

var kind: ItemKinds.Kind = ItemKinds.Kind.STRETCHER
var length: float = 2.0
## Tiles a second with both carriers agreeing.
var speed: float = 2.5
var radius: float = 0.35
## The centre, in tiles.
var x: float = 0.0
var y: float = 0.0
## A u16 facing: the front carrier stands at the centre plus half the length along it.
var heading: int = 0
var halted: bool = false
## The issue tick the carriers began to disagree, -1 while they agree.
var disagree_since: int = -1
## The last agreed direction of motion (u16), -1 standing: kept through a short disagreement.
var last_dir: int = -1
## Seconds moved not yet stepped (each carrier steps every movement.step_interval).
var step_accum: float = 0.0


static func make(of_kind: ItemKinds.Kind, at: Vector2, heading_u16: int) -> LoadSegment:
	var s: LoadSegment = LoadSegment.new()
	s.kind = of_kind
	s.x = at.x
	s.y = at.y
	s.heading = heading_u16 & 0xFFFF
	s.radius = Tuning.f(&"movement.body_radius")
	s.length = Tuning.f(&"movement.drum_gear_length" if of_kind == ItemKinds.Kind.DRUM_GEAR else &"movement.stretcher_length")
	s.speed = speed_of(of_kind)
	return s


## Tiles a second with two carriers agreeing.
static func speed_of(of_kind: ItemKinds.Kind) -> float:
	return Tuning.f(&"movement.carry_drum_gear_speed" if of_kind == ItemKinds.Kind.DRUM_GEAR else &"movement.carry_stretcher_speed")


## An input direction byte as a u16 facing.
static func dir_u16(move_dir: int) -> int:
	return roundi(move_dir * 65536.0 / InputRecord.DIRECTIONS) & 0xFFFF


## `to` minus `from` the shorter way round, in u16 units (-32768 to 32767).
static func signed_diff(from: int, to: int) -> int:
	return ((to - from + 32768) & 0xFFFF) - 32768


static func degrees_u16(degrees: float) -> int:
	return roundi(degrees * 65536.0 / 360.0)


func centre() -> Vector2:
	return Vector2(x, y)


func front_end() -> Vector2:
	var u: PackedFloat64Array = LbDetMath.unit(float(heading) / 65536.0)
	return Vector2(x + u[0] * length * 0.5, y + u[1] * length * 0.5)


func rear_end() -> Vector2:
	var u: PackedFloat64Array = LbDetMath.unit(float(heading) / 65536.0)
	return Vector2(x - u[0] * length * 0.5, y - u[1] * length * 0.5)


## One tick. `wounded`: a carrier is Hurt or trap-wounded; `is_solid(tile: Vector2i) -> bool`.
func step(front: Push, rear: Push, wounded: bool, is_solid: Callable) -> Result:
	var out: Result = Result.new()
	if front.starved or rear.starved:
		return out
	var front_moving: bool = front.dir != InputRecord.NO_DIRECTION
	var rear_moving: bool = rear.dir != InputRecord.NO_DIRECTION
	var agree: bool = not front_moving and not rear_moving
	var average: int = -1
	if front_moving and rear_moving:
		var a: int = dir_u16(front.dir)
		var d: int = signed_diff(a, dir_u16(rear.dir))
		agree = absi(d) <= degrees_u16(Tuning.f(&"movement.load_knock_angle"))
		average = (a + d / 2) & 0xFFFF
	var motion: int = -1
	if agree:
		disagree_since = -1
		halted = false
		last_dir = average
		motion = average
	else:
		if disagree_since < 0:
			disagree_since = maxi(front.stamp, rear.stamp)
		var elapsed: int = mini(front.stamp, rear.stamp) - disagree_since + 1
		var limit: int = roundi(Tuning.f(&"movement.load_knock_time") * Tuning.f(&"net.tick_hz"))
		if not halted and elapsed > limit:
			halted = true
			out.knock = true
			last_dir = -1
		motion = -1 if halted else last_dir
	if motion < 0:
		return out
	var dt: float = 1.0 / Tuning.f(&"net.tick_hz")
	var pace: float = speed * (Tuning.f(&"movement.wound_gait_multiplier") if wounded else 1.0) * dt
	var u: PackedFloat64Array = LbDetMath.unit(float(motion) / 65536.0)
	var nx: float = x + u[0] * pace
	var ny: float = y + u[1] * pace
	var aim: int = motion if absi(signed_diff(heading, motion)) <= REVERSE_BEYOND else (motion + 32768) & 0xFFFF
	var nh: int = MinerMotion.turn_toward(heading, aim, degrees_u16(Tuning.f(&"movement.load_turn_per_tick")))
	if not collides(nx, ny, nh, is_solid):
		x = nx
		y = ny
		heading = nh
	elif nh != heading and not collides(x, y, nh, is_solid):
		heading = nh
		out.blocked = true
	elif not collides(nx, ny, heading, is_solid):
		x = nx
		y = ny
		out.blocked = true
	else:
		out.blocked = true
		return out
	out.moved = true
	var interval: float = Tuning.f(&"movement.step_interval")
	step_accum += dt
	while step_accum >= interval - SKIN:
		step_accum -= interval
		out.steps += 1
	return out


## True when the capsule (the load and its carriers) centred at (cx, cy) on heading `h` would
## overlap a solid tile; touching one is not overlapping.
func collides(cx: float, cy: float, h: int, is_solid: Callable) -> bool:
	var u: PackedFloat64Array = LbDetMath.unit(float(h & 0xFFFF) / 65536.0)
	var half: float = length * 0.5
	var ax: float = cx + u[0] * half
	var ay: float = cy + u[1] * half
	var bx: float = cx - u[0] * half
	var by: float = cy - u[1] * half
	for ty: int in range(floori(minf(ay, by) - radius), floori(maxf(ay, by) + radius) + 1):
		for tx: int in range(floori(minf(ax, bx) - radius), floori(maxf(ax, bx) + radius) + 1):
			if not Variants.flag(is_solid.call(Vector2i(tx, ty))):
				continue
			if segment_box_distance_sq(ax, ay, bx, by, tx, ty, tx + 1, ty + 1) < radius * radius - SKIN:
				return true
	return false


## The squared distance between segment a-b and the box [x0, x1] x [y0, y1]: 0 where they meet,
## else the least of each end to the box and each corner to the segment (in 2D that is exact).
static func segment_box_distance_sq(ax: float, ay: float, bx: float, by: float, x0: float, y0: float, x1: float, y1: float) -> float:
	if _segment_meets_box(ax, ay, bx, by, x0, y0, x1, y1):
		return 0.0
	var best: float = minf(_point_box_sq(ax, ay, x0, y0, x1, y1), _point_box_sq(bx, by, x0, y0, x1, y1))
	best = minf(best, _point_segment_sq(x0, y0, ax, ay, bx, by))
	best = minf(best, _point_segment_sq(x1, y0, ax, ay, bx, by))
	best = minf(best, _point_segment_sq(x0, y1, ax, ay, bx, by))
	return minf(best, _point_segment_sq(x1, y1, ax, ay, bx, by))


## Liang-Barsky: whether any point of segment a-b lies in the box.
static func _segment_meets_box(ax: float, ay: float, bx: float, by: float, x0: float, y0: float, x1: float, y1: float) -> bool:
	var dx: float = bx - ax
	var dy: float = by - ay
	var p: PackedFloat64Array = PackedFloat64Array([-dx, dx, -dy, dy])
	var q: PackedFloat64Array = PackedFloat64Array([ax - x0, x1 - ax, ay - y0, y1 - ay])
	var t0: float = 0.0
	var t1: float = 1.0
	for i: int in 4:
		if p[i] == 0.0:
			if q[i] < 0.0:
				return false
			continue
		var r: float = q[i] / p[i]
		if p[i] < 0.0:
			if r > t1:
				return false
			t0 = maxf(t0, r)
		else:
			if r < t0:
				return false
			t1 = minf(t1, r)
	return t0 <= t1


static func _point_box_sq(px: float, py: float, x0: float, y0: float, x1: float, y1: float) -> float:
	var ex: float = px - clampf(px, x0, x1)
	var ey: float = py - clampf(py, y0, y1)
	return ex * ex + ey * ey


static func _point_segment_sq(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var dx: float = bx - ax
	var dy: float = by - ay
	var len_sq: float = dx * dx + dy * dy
	var t: float = 0.0 if len_sq <= 0.0 else clampf(((px - ax) * dx + (py - ay) * dy) / len_sq, 0.0, 1.0)
	var ex: float = ax + dx * t - px
	var ey: float = ay + dy * t - py
	return ex * ex + ey * ey


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(kind)
	writer.put_f64(x)
	writer.put_f64(y)
	writer.put_i64(heading)
	writer.put_bool(halted)
	writer.put_i64(disagree_since)
	writer.put_i64(last_dir)
	writer.put_f64(step_accum)
