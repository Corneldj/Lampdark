class_name ClientClock
extends RefCounted
## NET-05's client timeline. The server timeline as received is estimated from each frame's tick
## and arrival time, smoothed: it runs one way's latency behind the true server, so frames are
## always at hand for interpolation whatever the round trip. The client ticks a little faster or slower than 20 Hz
## (up to net.input_clock_nudge_max) to keep NET-03's server input buffer at its target depth.
## shown_tick is the render time, net.interp_delay_ms behind that timeline: everything but the
## own miner is drawn there, and NET-03 stamps it on every input, so NET-06's rewind (T - S) is
## about the round trip plus the interpolation delay plus the input buffer.

const TICK_USEC: int = 50000

var interp_delay_ms: float = 100.0
var nudge_max: float = 0.05
var target_depth: int = 1
## Smoothing of the estimate (0 keeps the old offset, 1 takes each frame's).
var smoothing: float = 0.1
var _offset_usec: float = 0.0   # server tick time minus local time, in usec
var _have_estimate: bool = false
var _accum_usec: float = 0.0
var _last_usec: int = -1
var nudge: float = 0.0


func _init() -> void:
	if Tuning.current.has_key(&"net.interp_delay_ms"):
		interp_delay_ms = Tuning.f(&"net.interp_delay_ms")
		nudge_max = Tuning.f(&"net.input_clock_nudge_max")


## A frame for `tick` arrived at local `now_usec`.
func on_frame(tick: int, now_usec: int) -> void:
	# The frame left at the end of its tick; its arrival is that moment on the received timeline.
	var sent_server_usec: float = float(tick + 1) * TICK_USEC
	var offset: float = sent_server_usec - now_usec
	if not _have_estimate:
		_offset_usec = offset
		_have_estimate = true
	else:
		_offset_usec += (offset - _offset_usec) * smoothing


func has_estimate() -> bool:
	return _have_estimate


## The server tick as received by now (the newest frame's end, advanced by local time), with a
## fraction. One way's latency behind the server's own clock.
func server_tick(now_usec: int) -> float:
	return (now_usec + _offset_usec) / TICK_USEC


## The render time in ticks, with a fraction: interp_delay_ms behind the server.
func shown_tick(now_usec: int) -> float:
	return server_tick(now_usec) - interp_delay_ms * 1000.0 / TICK_USEC


## NET-03's frame header reports the server's buffer depth: below target, tick faster.
func on_depth(depth: int) -> void:
	nudge = clampf((target_depth - depth) * 0.02, -nudge_max, nudge_max)


## How many client ticks are due by `now_usec` (at 20 Hz times 1 + nudge).
func advance(now_usec: int) -> int:
	if _last_usec < 0:
		_last_usec = now_usec
		return 0
	_accum_usec += (now_usec - _last_usec) * (1.0 + nudge)
	_last_usec = now_usec
	var due: int = floori(_accum_usec / TICK_USEC)
	_accum_usec -= due * TICK_USEC
	return due
