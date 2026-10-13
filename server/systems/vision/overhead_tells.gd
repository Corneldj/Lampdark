class_name OverheadTells
extends RefCounted
## VIS-09's server side of the overhead camera's tells (Gameplay §5.8), never state and never read
## by a rule: Replication calls prepare() each tick just before it builds frames.
##   The Moth's dust: a per-viewer flag, set while the viewer's miner is within moth.tell_reach_tiles
##     (straight-line) of a Moth whose tell plays (awake or stirring); the client then draws dust on
##     every lit tile it sees, so the flag's edge never traces the Moth.
##   The Tapper's puffs: each hunting tap's three wall points (CRT-09's `tapped`; never its true
##     face). A viewer gets a puff at a point only where open floor beside that wall is in its seen
##     set lit to light.dust_min_light, in the tap's own tick.
##   Bursts: dust_burst(at, radius, seconds) for CRT-06's laying and MNR-16's flinch, to viewers who
##     see a lit tile within the radius.
## Puffs and bursts go out as VisualEvents on NET-04's event channel; the dust flag in the frame.

var dust: Dictionary = {}
## [points (Array[Vector2i]), tick] from this tick's taps.
var _taps: Array[Array] = []
## [at (Vector2), radius, seconds]
var _bursts: Array[Array] = []
var puffs_sent: int = 0
var bursts_sent: int = 0


func bind(run: RunState) -> void:
	if run.creatures == null:
		return
	run.creatures.spawned.connect(func(c: Creature) -> void:
		var t: Tapper = c as Tapper
		if t != null:
			t.tapped.connect(_on_tapped))


func _on_tapped(points: Array[Vector2i], _lit: Array[Vector2i]) -> void:
	_taps.append([points.duplicate()])


## CRT-06's laying and MNR-16's flinch.
func dust_burst(at: Vector2, radius_tiles: float, seconds: float) -> void:
	_bursts.append([at, radius_tiles, seconds])


func dust_for(slot: int) -> bool:
	return Variants.flag(dust.get(slot, false))


## Before the frames are built: this tick's dust flags, puffs and bursts.
func prepare(run: RunState) -> void:
	dust.clear()
	if run.movement == null:
		_taps.clear()
		_bursts.clear()
		return
	var moths: Array[Creature] = []
	if run.creatures != null:
		for c: Creature in run.creatures.creatures:
			var m: Moth = c as Moth
			if m != null and m.tell_active():
				moths.append(m)
	var reach: float = Tuning.f(&"moth.tell_reach_tiles")
	var min_light: int = roundi(Tuning.f(&"light.dust_min_light") * 255.0)
	for slot: int in run.movement.miner_slots():
		var mm: MovementSystem.Miner = run.movement.miner(slot)
		var at: Vector2 = Vector2(mm.state.x, mm.state.y)
		for m: Creature in moths:
			if at.distance_to(m.position(run)) <= reach + 1e-9:
				dust[slot] = true
		if _taps.is_empty() and _bursts.is_empty():
			continue
		var seen: Dictionary = _seen_lit(run, slot, min_light)
		for tap: Array in _taps:
			for p: Vector2i in Variants.array(tap[0]):
				if _beside_seen(p, seen):
					_send(run, slot, VisualEvents.Type.PUFF, Vector2(p) + Vector2(0.5, 0.5), 0.0, 0.6)
					puffs_sent += 1
		for b: Array in _bursts:
			var centre: Vector2 = b[0]
			var radius: float = float(Variants.number(b[1]))
			for raw: Variant in seen.keys():
				var t: Vector2i = raw
				if (Vector2(t) + Vector2(0.5, 0.5)).distance_to(centre) <= radius + 0.5:
					_send(run, slot, VisualEvents.Type.DUST_BURST, centre, radius, float(Variants.number(b[2])))
					bursts_sent += 1
					break
	_taps.clear()
	_bursts.clear()


## The viewer's seen tiles lit to the dust threshold (this tick's frame).
static func _seen_lit(run: RunState, slot: int, min_light: int) -> Dictionary:
	var out: Dictionary = {}
	if run.vision == null:
		return out
	var tiles: Dictionary = Variants.dict(run.vision.frame_for(slot).get("tiles", {}))
	var xs: PackedInt32Array = tiles.get("x", PackedInt32Array())
	var ys: PackedInt32Array = tiles.get("y", PackedInt32Array())
	var lights: PackedByteArray = tiles.get("light", PackedByteArray())
	for i: int in xs.size():
		if lights[i] >= min_light:
			out[Vector2i(xs[i], ys[i])] = true
	return out


static func _beside_seen(face: Vector2i, seen: Dictionary) -> bool:
	for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if seen.has(face + d):
			return true
	return seen.has(face)


static func _send(run: RunState, slot: int, type: int, at: Vector2, radius: float, seconds: float) -> void:
	var r: AudioRecord = AudioRecord.new()
	r.type = type
	r.start_tick = run.tick
	r.apparent = at
	r.level_np = radius
	r.remaining_np = radius
	r.duration_s = seconds
	run.replication.queue_visual(slot, r)
