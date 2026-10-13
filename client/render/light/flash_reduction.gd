class_name FlashReduction
extends RefCounted
## VIS-06 (GDD §14.5): with flash reduction on, a pool that jumps up within a frame (a flare, a
## blast, the brood burst, the muzzle flash) draws at light.muzzle_flash_reduced_peak of its value at
## once, building to full over light.flash_build_s; so the 0.1 s muzzle flash draws at half peak for
## its 2 ticks and a flare reaches full exposure no sooner than 0.5 s (Proposed rule). Tiles merely
## coming into view are not flashes. No frame is pure white (LightPool's max_channel). Off, nothing
## changes. Ordinary flicker stays: only jumps are shaped.

## A rise this large within one frame is a flash.
const JUMP: float = 0.3

var enabled: bool = false
## tile -> [onset time (s), previous light]
var _onset: Dictionary = {}
var _prev: Dictionary = {}


func filter(lights: Dictionary, now_s: float) -> Dictionary:
	if not enabled:
		_prev = lights.duplicate()
		_onset.clear()
		return lights
	var build: float = Tuning.f(&"light.flash_build_s")
	var start: float = Tuning.f(&"light.muzzle_flash_reduced_peak")
	var out: Dictionary = {}
	for raw: Variant in lights.keys():
		var target: float = float(Variants.number(lights[raw]))
		if _prev.has(raw) and target - float(Variants.number(_prev[raw])) >= JUMP:
			_onset[raw] = now_s
		var shaped: float = target
		if _onset.has(raw):
			var k: float = start + (1.0 - start) * clampf((now_s - float(Variants.number(_onset[raw]))) / build, 0.0, 1.0)
			shaped = target * k
			if k >= 1.0:
				_onset.erase(raw)
		out[raw] = shaped
	for raw: Variant in _onset.keys().duplicate():
		if not lights.has(raw):
			_onset.erase(raw)
	_prev = lights.duplicate()
	return out


## The pool's ceiling per channel: never a pure-white frame with flash reduction on.
func max_channel() -> float:
	return 250.0 / 255.0 if enabled else 1.0
