class_name MinerMotion
extends RefCounted
## MNR-01's one movement step, run by the server (authority) and the owning client (NET-05's
## prediction): fixed gait speeds reached and dropped in the tick, facing turned toward the
## input's at no more than movement.turn_rate_deg_s (NET-12: so the server can see a turn coming;
## unless locked), slowdowns that multiply, and a circle of movement.body_radius sliding against solid
## tiles (x, then y). Pure: no nodes, no wall clock, and movement directions come from
## LbDetMath's bit-identical unit vectors, never GDScript's sin and cos.

## A miner's motion between ticks.
class State:
	extends RefCounted
	var x: float = 0.0
	var y: float = 0.0
	var facing: int = 0
	## The gait in effect last tick; STILL when nothing moved it.
	var gait: int = STILL
	## Distance actually covered over the last tick, per second.
	var speed: float = 0.0
	## Seconds of Walk or Run movement not yet stepped; never reset on stopping.
	var step_accum: float = 0.0
	## Solid tiles the circle is pressing against (for one bump per contact).
	var contacts: Array[Vector2i] = []

	func duplicate_state() -> State:
		var s: State = State.new()
		s.x = x
		s.y = y
		s.facing = facing
		s.gait = gait
		s.speed = speed
		s.step_accum = step_accum
		s.contacts = contacts.duplicate()
		return s

	func position() -> Vector2:
		return Vector2(x, y)


## The most restrictive of every gait request (MNR-02 stamina, MNR-03 states, MNR-13 and
## MNR-14 carries, MNR-16 aiming).
class Constraints:
	extends RefCounted
	var movement_off: bool = false
	var run_allowed: bool = true
	## Walk and nothing else: no running, no crouching (MNR-13's carries).
	var walk_only: bool = false
	## Tiles/s replacing the gait's speed (carries, the crawl); negative for none.
	var fixed_speed: float = -1.0
	var facing_lock: bool = false

	## Combines requests: any off is off, any lock locks, the slowest fixed speed wins.
	static func most_restrictive(requests: Array) -> Constraints:
		var c: Constraints = Constraints.new()
		for raw: Variant in requests:
			var r: Constraints = raw
			c.movement_off = c.movement_off or r.movement_off
			c.run_allowed = c.run_allowed and r.run_allowed
			c.walk_only = c.walk_only or r.walk_only
			c.facing_lock = c.facing_lock or r.facing_lock
			if r.fixed_speed >= 0.0 and (c.fixed_speed < 0.0 or r.fixed_speed < c.fixed_speed):
				c.fixed_speed = r.fixed_speed
		return c


## The numbers, from tuning (all client-visible except the step interval).
class Params:
	extends RefCounted
	var crouch_speed: float = 1.5
	var walk_speed: float = 3.0
	var run_speed: float = 5.5
	var body_radius: float = 0.35
	## NET-12: the fastest the facing turns, degrees a second; 0 turns at once.
	var turn_rate_deg_s: float = 0.0
	var step_interval: float = 0.5

	static func from_tuning() -> Params:
		var p: Params = Params.new()
		p.crouch_speed = Tuning.f(&"movement.crouch_speed")
		p.walk_speed = Tuning.f(&"movement.walk_speed")
		p.run_speed = Tuning.f(&"movement.run_speed")
		p.body_radius = Tuning.f(&"movement.body_radius")
		if Tuning.current.has_key(&"movement.step_interval"):
			p.step_interval = Tuning.f(&"movement.step_interval")
		if Tuning.current.has_key(&"movement.turn_rate_deg_s"):
			p.turn_rate_deg_s = Tuning.f(&"movement.turn_rate_deg_s")
		return p


## What one step did.
class Result:
	extends RefCounted
	var state: State
	## Step events due this tick, and the gait they belong to (WALK or RUN).
	var steps: int = 0
	var step_gait: int = STILL
	## The tile a new contact began against this tick (VIS-07's wall bump), if any.
	var bumped: Array[Vector2i] = []


const STILL: int = -1
const CROUCH: int = InputRecord.Gait.CROUCH
const WALK: int = InputRecord.Gait.WALK
const RUN: int = InputRecord.Gait.RUN
## Separation kept from a wall, so rounding never leaves a circle overlapping it.
const SKIN: float = 1e-9

static var _dirs: PackedFloat64Array = PackedFloat64Array()


## Run (held and allowed) beats crouch (held or toggled), which beats walk (MNR-15 calls this).
static func choose_gait(run_held: bool, crouch_on: bool, run_allowed: bool) -> InputRecord.Gait:
	if run_held and run_allowed:
		return InputRecord.Gait.RUN
	if crouch_on:
		return InputRecord.Gait.CROUCH
	return InputRecord.Gait.WALK


## The unit vector of an input direction (0-254), as [x, y] doubles.
static func direction(move_dir: int) -> PackedFloat64Array:
	if _dirs.is_empty():
		_dirs.resize(InputRecord.DIRECTIONS * 2)
		for i: int in InputRecord.DIRECTIONS:
			var u: PackedFloat64Array = LbDetMath.unit(float(i) / InputRecord.DIRECTIONS)
			_dirs[i * 2] = u[0]
			_dirs[i * 2 + 1] = u[1]
	return PackedFloat64Array([_dirs[move_dir * 2], _dirs[move_dir * 2 + 1]])


static func gait_speed(gait: int, p: Params) -> float:
	match gait:
		CROUCH:
			return p.crouch_speed
		RUN:
			return p.run_speed
		WALK:
			return p.walk_speed
	return 0.0


## The largest facing change (u16 units) in `dt` seconds at `rate_deg_s`; 65536 (any turn) at 0.
static func turn_step(rate_deg_s: float, dt: float) -> int:
	if rate_deg_s <= 0.0:
		return 65536
	return maxi(1, roundi(rate_deg_s * dt * 65536.0 / 360.0))


## `from` turned toward `to` by at most `max_step` (u16 facings, the shorter way round).
static func turn_toward(from: int, to: int, max_step: int) -> int:
	var d: int = ((to - from + 32768) & 0xFFFF) - 32768
	if absi(d) <= max_step:
		return to & 0xFFFF
	return (from + (max_step if d > 0 else -max_step)) & 0xFFFF


## One tick. `factor` is the product of the miner's speed modifiers (wound slot included);
## is_solid(tile: Vector2i) -> bool is GEN-01's solidity, doors and gates included.
static func step(prev: State, input: InputRecord, c: Constraints, factor: float, is_solid: Callable, dt: float, p: Params) -> Result:
	var s: State = prev.duplicate_state()
	var out: Result = Result.new()
	out.state = s
	if input != null and not c.facing_lock:
		s.facing = turn_toward(s.facing, input.facing, turn_step(p.turn_rate_deg_s, dt))
	var gait: int = STILL
	var speed: float = 0.0
	if input != null and input.move_dir != InputRecord.NO_DIRECTION and not c.movement_off:
		gait = input.gait
		if gait == RUN and (not c.run_allowed or c.walk_only):
			gait = WALK
		elif gait == CROUCH and c.walk_only:
			gait = WALK
		speed = (c.fixed_speed if c.fixed_speed >= 0.0 else gait_speed(gait, p)) * factor
	var start_x: float = s.x
	var start_y: float = s.y
	var touching: Array[Vector2i] = []
	if speed > 0.0:
		var d: PackedFloat64Array = direction(input.move_dir)
		var dx: float = d[0] * speed * dt
		var dy: float = d[1] * speed * dt
		if dx != 0.0:
			s.x = _resolve(s, true, dx, p.body_radius, is_solid, touching)
		if dy != 0.0:
			s.y = _resolve(s, false, dy, p.body_radius, is_solid, touching)
	var mx: float = s.x - start_x
	var my: float = s.y - start_y
	var moved: float = sqrt(mx * mx + my * my)
	s.speed = moved / dt
	s.gait = gait if moved > 0.0 else STILL
	if moved > 0.0 and (gait == WALK or gait == RUN):
		s.step_accum += dt
		while s.step_accum >= p.step_interval - SKIN:
			s.step_accum -= p.step_interval
			out.steps += 1
		out.step_gait = gait
	# One bump per contact: pressing on from one wall tile to the next (sliding along a rib)
	# is the same contact.
	if prev.contacts.is_empty() and not touching.is_empty():
		out.bumped.append(touching[0])
	s.contacts = touching
	return out


## Moves along one axis, stopping the circle where it would overlap a solid tile.
static func _resolve(s: State, along_x: bool, delta: float, r: float, is_solid: Callable, touching: Array[Vector2i]) -> float:
	var nx: float = s.x + (delta if along_x else 0.0)
	var ny: float = s.y + (0.0 if along_x else delta)
	var x0: int = floori(nx - r)
	var x1: int = floori(nx + r)
	var y0: int = floori(ny - r)
	var y1: int = floori(ny + r)
	for ty: int in range(y0, y1 + 1):
		for tx: int in range(x0, x1 + 1):
			var tile: Vector2i = Vector2i(tx, ty)
			var solid: bool = is_solid.call(tile)
			if not solid:
				continue
			var qx: float = clampf(nx, tx, tx + 1)
			var qy: float = clampf(ny, ty, ty + 1)
			var ex: float = nx - qx
			var ey: float = ny - qy
			if ex * ex + ey * ey >= r * r - SKIN:
				continue
			if along_x:
				if (delta > 0.0 and tx + 0.5 < s.x) or (delta < 0.0 and tx + 0.5 > s.x):
					continue
				var push: float = sqrt(maxf(r * r - ey * ey, 0.0)) + SKIN
				nx = minf(nx, tx - push) if delta > 0.0 else maxf(nx, tx + 1 + push)
			else:
				if (delta > 0.0 and ty + 0.5 < s.y) or (delta < 0.0 and ty + 0.5 > s.y):
					continue
				var push_y: float = sqrt(maxf(r * r - ex * ex, 0.0)) + SKIN
				ny = minf(ny, ty - push_y) if delta > 0.0 else maxf(ny, ty + 1 + push_y)
			if not touching.has(tile):
				touching.append(tile)
	return nx if along_x else ny
