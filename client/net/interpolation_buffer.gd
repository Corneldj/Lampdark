class_name InterpolationBuffer
extends RefCounted
## NET-05's interpolation of everything but the own miner: entities are drawn at the render time
## (ClientClock.shown_tick), between the frames either side of it. A token appears at its
## creating frame's time and vanishes at its removing frame's time; when frames are late,
## positions extrapolate for at most net.extrapolate_max_ms, then hold. Nothing moves without a
## frame: these are the server's records, only placed in time.

const KEEP: int = 40


class Frame:
	extends RefCounted
	var tick: int = 0
	## token -> entity dictionary
	var entities: Dictionary = {}


## Ascending by tick.
var frames: Array[Frame] = []
var extrapolate_ticks: float = 1.0


func _init() -> void:
	if Tuning.current.has_key(&"net.extrapolate_max_ms"):
		extrapolate_ticks = Tuning.f(&"net.extrapolate_max_ms") / 50.0


func push(tick: int, view: ReceivedView) -> void:
	if not frames.is_empty() and frames[frames.size() - 1].tick >= tick:
		return
	var f: Frame = Frame.new()
	f.tick = tick
	f.entities = view.entities.duplicate(true)
	frames.append(f)
	while frames.size() > KEEP:
		frames.pop_front()


## {token: entity dictionary with "position" placed at the render time}.
func sample(render_tick: float) -> Dictionary:
	var out: Dictionary = {}
	var i: int = -1
	for k: int in frames.size():
		if float(frames[k].tick) <= render_tick:
			i = k
	if i < 0:
		return out  # before the first frame: nothing has been sent yet
	var a: Frame = frames[i]
	if i + 1 < frames.size():
		var b: Frame = frames[i + 1]
		var t: float = (render_tick - a.tick) / float(b.tick - a.tick)
		for token: Variant in a.entities.keys():
			var e: Dictionary = Variants.dict(a.entities[token]).duplicate()
			if b.entities.has(token):
				var pa: Vector2 = e["position"]
				var pb: Vector2 = Variants.dict(b.entities[token])["position"]
				e["position"] = pa.lerp(pb, t)
			out[token] = e
		return out
	# Past the newest frame: extrapolate a little from the last two, then hold.
	var ahead: float = minf(render_tick - a.tick, extrapolate_ticks)
	var prev: Frame = frames[i - 1] if i > 0 else null
	for token: Variant in a.entities.keys():
		var e: Dictionary = Variants.dict(a.entities[token]).duplicate()
		if prev != null and prev.entities.has(token):
			var pa: Vector2 = Variants.dict(prev.entities[token])["position"]
			var pb: Vector2 = e["position"]
			e["position"] = pb + (pb - pa) / float(a.tick - prev.tick) * ahead
		out[token] = e
	return out
