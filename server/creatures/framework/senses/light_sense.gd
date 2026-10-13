class_name LightSense
extends RefCounted
## The Moth's one sense: the light grid (VIS-02), current state only, never rewound, never a
## client, an illusion or another creature. CRT-03 and CRT-04 extend what it reads.

var _run: RunState


func _init(run: RunState) -> void:
	_run = run


## Light at a tile, 0-1 (0 with no light grid).
func light_at(tile: Vector2i) -> float:
	return _run.light.light_at(tile) if _run.light != null else 0.0


## CRT-04: the awake Moth's sight (LightSystem.lit_in_sight): lit tiles in line of sight, no cone.
func lit_in_sight(from: Vector2i, range: float, min_light: float, excluded: PackedInt64Array) -> PackedInt64Array:
	return _run.light.lit_in_sight(from, range, min_light, excluded) if _run.light != null else PackedInt64Array()

