extends RefCounted
## Helpers for MNR-07's tests: points in each ring, and lamps parked there.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")


## A point (y = 10.5) in ring `ring`, a few tiles past its inner edge.
static func point_in_ring(ring: int) -> Vector2:
	var x: int = 10
	while WorldCoords.ring_of_point(Vector2(x + 0.5, 10.5)) < ring:
		x += 1
	return Vector2(x + 3.5, 10.5)


## The last point (y = 10.5) still in ring `ring`, and the first beyond it.
static func ring_edge(ring: int) -> Array[Vector2]:
	var x: int = 10
	while WorldCoords.ring_of_point(Vector2(x + 1.5, 10.5)) <= ring:
		x += 1
	return [Vector2(x + 0.5, 10.5), Vector2(x + 1.5, 10.5)]


## A burning lamp lying open at `at`, at `wick`, with `oil`.
static func parked(s: Scenario, at: Vector2, wick: int, oil: float = 1.0) -> GauzeLamp:
	return s.run.lamps.create(s.run, oil, 3, true, wick, at)


## Runs the server alone (no clients) for `ticks`.
static func run_server(s: Scenario, ticks: int) -> void:
	for _i: int in ticks:
		s.run.run_tick()
