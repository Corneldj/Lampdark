extends RefCounted
## LFT-04's scenarios: a 16 x 7 room with a job for two. The holder's place H (the trip, the crank)
## is west of the presser's place P (the switch, the throttle); the cue is a real ENGINE_CRANK event
## (a TimedCues type) emitted at H, which each presser's client presents and reports (NET-06). A
## PairedWork's places A and B sit on the north wall. Miners are placed beside a place, facing it.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

const H_TILE: Vector2i = Vector2i(3, 3)
const P_TILE: Vector2i = Vector2i(11, 3)
const A_TILE: Vector2i = Vector2i(4, 1)
const B_TILE: Vector2i = Vector2i(9, 1)
## Alone: H and P either side of one spot, a step apart.
const LONE_SPOT: Vector2i = Vector2i(7, 4)
const LONE_H: Vector2i = Vector2i(6, 4)
const LONE_P: Vector2i = Vector2i(8, 4)


static func room() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("#".repeat(16))
	for y: int in 5:
		rows.append("#" + ".".repeat(14) + "#")
	rows.append("#".repeat(16))
	return FixtureMap.from_ascii(rows)


static func centre(t: Vector2i) -> Vector2:
	return Vector2(t) + Vector2(0.5, 0.5)


## A CuePress at `h` and `p`; its outcomes go into `events` as [what, tick, detail].
static func cue_press(s: Scenario, events: Array, hold_to_ready_s: float = 0.0, h: Vector2i = H_TILE,
		p: Vector2i = P_TILE) -> CuePress:
	var cue: Callable = func(run: RunState, _j: CuePress) -> int:
		run.noise.emit(NoiseTypes.Type.ENGINE_CRANK, h)
		events.append(["cue", run.tick, 0])
		return NoiseTypes.Type.ENGINE_CRANK
	var ok: Callable = func(run: RunState, _j: CuePress, presser: int) -> void: events.append(["success", run.tick, presser])
	var miss: Callable = func(run: RunState, _j: CuePress, why: String) -> void: events.append(["miss", run.tick, why])
	var job: CuePress = CuePress.make({"name": "main_switch", "holder_anchor": centre(h), "presser_anchor": centre(p),
		"hold_to_ready_s": hold_to_ready_s, "on_cue": cue, "on_success": ok, "on_miss": miss})
	s.run.two_miner.add(job)
	return job


## A PairedWork on A and B; completions go into `events`.
static func paired_work(s: Scenario, events: Array, work_s: float = 10.0) -> PairedWork:
	var done: Callable = func(run: RunState, _j: PairedWork) -> void: events.append(["complete", run.tick, 0])
	var job: PairedWork = PairedWork.make({"name": "drum_gear", "anchor_a": centre(A_TILE), "anchor_b": centre(B_TILE),
		"work_s": work_s, "on_complete": done})
	s.run.two_miner.add(job)
	return job


## A miner one tile from `place` on `side`, facing it.
static func beside(s: Scenario, name: String, place: Vector2i, side: Vector2i) -> MinerHandle:
	var facing: float = fposmod(rad_to_deg(Vector2(-side).angle()), 360.0)
	var h: MinerHandle = s.add_miner(name, place + side, {"facing_deg": facing})
	h.at(s.run.tick).face(facing)
	return h


## The lone spot between H (west) and P (east), facing H.
static func lone(s: Scenario, name: String) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, LONE_SPOT, {"facing_deg": 180.0})
	h.at(s.run.tick).face(180.0)
	return h


## Interact held from the next tick for `ticks`.
static func hold(s: Scenario, h: MinerHandle, ticks: int) -> void:
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, ticks)


## Steps until the newest cue shows on `h`'s screen, then presses `seconds` after it on h's own
## timeline (as NET-06's test does), and steps on `after` ticks. False if the cue never showed.
static func press_after_cue(s: Scenario, h: MinerHandle, seconds: float, after: int = 40) -> bool:
	var offset: float = seconds * Tuning.f(&"net.tick_hz")
	var seen: int = h.connection.cues.presented.size()
	for i: int in 200:
		s.step(1)
		if h.connection.cues.presented.size() <= seen:
			continue
		var p: PackedInt64Array = h.connection.cues.presented[h.connection.cues.presented.size() - 1]
		var arrived: float = float(p[1]) + p[2] / 256.0
		var stamp: PackedInt64Array = h.connection.shown_stamp(Transport.now_usec())
		# The next input leaves during the next step, about a tick on.
		if float(stamp[0]) + stamp[1] / 256.0 + 1.0 >= arrived + offset:
			h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
			s.step(after)
			return true
	return false


static func whats(events: Array) -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in events:
		var e: Array = raw
		out.append(str(e[0]) if str(e[0]) != "miss" else "miss:" + str(e[2]))
	return out
