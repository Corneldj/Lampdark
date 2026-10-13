class_name MothMemory
extends RefCounted
## CRT-04: the awake Moth's memory of recent lights (Gameplay §7.2): the last 2 + crew count
## (moth.memory_lights_by_crew), each a centroid, a score and a time, for moth.memory_s; a light
## within moth.memory_merge_tiles of a remembered one refreshes it. Server-only, never sent.

class Light:
	extends RefCounted
	var centroid: Vector2 = Vector2.ZERO
	var score: float = 0.0
	var tick: int = 0


var lights: Array[Light] = []


func remember(centroid: Vector2, score: float, now: int, capacity: int) -> void:
	var merge: float = Tuning.f(&"moth.memory_merge_tiles")
	for l: Light in lights:
		if l.centroid.distance_to(centroid) <= merge:
			l.centroid = centroid
			l.score = score
			l.tick = now
			_sort()
			return
	var l: Light = Light.new()
	l.centroid = centroid
	l.score = score
	l.tick = now
	lights.append(l)
	_sort()
	while lights.size() > capacity:
		lights.pop_back()


## Forgets lights older than moth.memory_s.
func prune(now: int) -> void:
	var keep_ticks: int = roundi(Tuning.f(&"moth.memory_s") * Tuning.f(&"net.tick_hz"))
	lights = lights.filter(func(l: Light) -> bool: return now - l.tick < keep_ticks)


## Remembered lights, nearest to `from` first (ties: newest, then centroid order).
func nearest_first(from: Vector2) -> Array[Light]:
	var out: Array[Light] = lights.duplicate()
	out.sort_custom(func(a: Light, b: Light) -> bool:
		var da: float = a.centroid.distance_squared_to(from)
		var db: float = b.centroid.distance_squared_to(from)
		if da != db:
			return da < db
		return a.tick > b.tick)
	return out


## Newest first, so the oldest falls off the end.
func _sort() -> void:
	lights.sort_custom(func(a: Light, b: Light) -> bool:
		if a.tick != b.tick:
			return a.tick > b.tick
		return a.centroid.x < b.centroid.x or (a.centroid.x == b.centroid.x and a.centroid.y < b.centroid.y))
