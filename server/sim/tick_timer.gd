class_name TickTimer
extends RefCounted
## Per-stage and per-system tick timings in µs, kept for a rolling window of ticks
## (net.tick_timing_window), with p50, p95 and p99 (NET-01). Feeds NET-12, FND-08 and QA-04.
## Measuring is the one wall-clock read the simulation makes; it never decides anything.

const TICK: String = "tick"

var window: int = 1200
## key -> PackedInt64Array ring buffer
var _samples: Dictionary = {}
var _cursor: Dictionary = {}
## key -> the slowest sample since the run began (not just the window)
var _max: Dictionary = {}


func _init(window_ticks: int = 1200) -> void:
	window = maxi(window_ticks, 1)


static func now_usec() -> int:
	return Time.get_ticks_usec()  # determinism: allow (timing measurement only)


func record(key: String, usec: int) -> void:
	var buffer: PackedInt64Array = _samples.get(key, PackedInt64Array())
	var cursor: int = int(Variants.number(_cursor.get(key, 0)))
	if buffer.size() < window:
		buffer.append(usec)
	else:
		buffer[cursor] = usec
	_samples[key] = buffer
	_cursor[key] = (cursor + 1) % window
	if usec > int(Variants.number(_max.get(key, -1))):
		_max[key] = usec


## The slowest sample of a key since the run began; 0 when none.
func max_usec(key: String) -> int:
	return int(Variants.number(_max.get(key, 0)))


func has(key: String) -> bool:
	return _samples.has(key)


func sample_count(key: String) -> int:
	var buffer: PackedInt64Array = _samples.get(key, PackedInt64Array())
	return buffer.size()


## The p-th percentile (0-100) of key's window, nearest-rank; 0 when empty.
func percentile(key: String, p: float) -> int:
	var buffer: PackedInt64Array = _samples.get(key, PackedInt64Array())
	if buffer.is_empty():
		return 0
	var sorted: PackedInt64Array = buffer.duplicate()
	sorted.sort()
	var rank: int = clampi(ceili(p / 100.0 * sorted.size()) - 1, 0, sorted.size() - 1)
	return sorted[rank]


## {p50, p95, p99} in µs for one key.
func summary(key: String) -> Dictionary:
	return {"p50": percentile(key, 50.0), "p95": percentile(key, 95.0), "p99": percentile(key, 99.0)}


func keys() -> PackedStringArray:
	return PackedStringArray(_samples.keys())


static func stage_key(stage: int) -> String:
	return "stage.%02d.%s" % [stage, StageTable.stage_name(stage)]


static func system_key(system: SimSystem) -> String:
	return "system.%02d.%s" % [system.stage(), system.system_name()]
