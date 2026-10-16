extends RefCounted
## Helpers for LFT-08's tests: base camp ready to start (every job but Start done, the tank filled),
## miners at the engine's prime, crank and throttle, and the start's moves.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const T = preload("res://tests/unit/lift/tank_world.gd")


## Base camp with a list of `kind`, every job but Start done and the tank at `fill` of full (Fuel
## done either way: it was full once).
static func ready(s: Scenario, kind: RepairList.Kind = RepairList.Kind.SHORT, fill: float = 1.0) -> void:
	T.camp(s, kind)
	var run: RunState = s.run
	for job: StringName in run.repair.list.jobs:
		if job != &"start":
			run.repair.done[job] = run.tick
	run.fuel.done = true
	run.fuel.level_ticks = roundi(run.fuel.capacity_ticks(run) * fill)
	s.step(2)


## The walkable tile nearest an engine anchor, in touch range of it.
static func spot(s: Scenario, anchor: String) -> Vector2i:
	var target: Vector2 = s.run.engine.anchors[anchor]
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var t: Vector2i = Vector2i(floori(target.x), floori(target.y)) + Vector2i(dx, dy)
			var d: float = (Vector2(t) + Vector2(0.5, 0.5)).distance_to(target)
			if d > 0.0 and d <= reach and d < best_d and s.run.mine.native.is_walkable(t):
				best = t
				best_d = d
	return best


## A miner at an engine anchor's spot, facing it.
static func at(s: Scenario, name: String, anchor: String) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, spot(s, anchor))
	face(s, h, anchor)
	s.step(3)
	return h


## `h` stepped across to another anchor's spot, facing it.
static func move_to(s: Scenario, h: MinerHandle, anchor: String) -> void:
	s.run.movement.place(s.run, h.entity_id, Vector2(spot(s, anchor)) + Vector2(0.5, 0.5))
	face(s, h, anchor)
	s.step(3)


static func face(s: Scenario, h: MinerHandle, anchor: String) -> void:
	var target: Vector2 = s.run.engine.anchors[anchor]
	var me: Vector2 = Vector2(spot(s, anchor)) + Vector2(0.5, 0.5)
	h.at(s.run.tick).face(rad_to_deg((target - me).angle()))


static func hold(s: Scenario, h: MinerHandle, ticks: int) -> void:
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, ticks)


## Prime: 66 ticks of held interact (3 s and the input's way there).
static func prime(s: Scenario, h: MinerHandle) -> void:
	hold(s, h, 66)
	s.step(70)


## Steps until `h`'s client presents the crank's clank (the engine's cue: the ENGINE_CRANK event at
## the stroke's top, not the heave at its start), then presses `seconds` after it on h's own
## timeline, as NET-06's tests do. False if the cue never shows.
static func throttle_after_cue(s: Scenario, h: MinerHandle, seconds: float, after: int = 40) -> bool:
	var offset: float = seconds * Tuning.f(&"net.tick_hz")
	var since: int = s.run.tick
	for i: int in 400:
		s.step(1)
		var job: CuePress = s.run.engine.crank
		# A cue from this stroke: an earlier one's tick stays on the job after a miss.
		if job == null or job.cue_tick < since:
			continue
		var want: int = TimedCues.cue_id(NoiseTypes.Type.ENGINE_CRANK, job.cue_tick)
		for p: PackedInt64Array in h.connection.cues.presented:
			if p[0] != want:
				continue
			var arrived: float = float(p[1]) + p[2] / 256.0
			var stamp: PackedInt64Array = h.connection.shown_stamp(Transport.now_usec())
			if float(stamp[0]) + stamp[1] / 256.0 + 1.0 >= arrived + offset:
				h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
				s.step(after)
				return true
	return false


## Every noise event of `type` since `from`.
static func events(s: Scenario, type: NoiseTypes.Type, from: int = 0) -> Array[NoiseSystem.Event]:
	var out: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from):
		if e.type == type:
			out.append(e)
	return out
