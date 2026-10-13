class_name CollapseHook
extends RefCounted
## SND-02's collapse trigger: any event of noise.collapse_trigger_np or more within
## noise.collapse_trigger_path_tiles of an armed collapse point, by AIR-mode path cost (so a
## shut door between them blocks it), or a firedamp blast within hazards.collapse_blast_trigger_tiles,
## starts that point's creak (HAZ-03 listens to collapse_triggered). The roof is not a creature:
## a Fan surge never stops it. Only NoiseSystem calls it; SND-01's delivery function and illusions never do.

signal collapse_triggered(point_id: int, event_id: int)

var road_graph: RoadGraphService = null
## point id -> tile, in arming order.
var _points: Dictionary = {}
var trigger_np: float = 18.0
var trigger_tiles: float = 6.0
var blast_tiles: float = 7.0


func _init(graph: RoadGraphService = null) -> void:
	road_graph = graph
	trigger_np = Tuning.f(&"noise.collapse_trigger_np")
	trigger_tiles = Tuning.f(&"noise.collapse_trigger_path_tiles")
	blast_tiles = Tuning.f(&"hazards.collapse_blast_trigger_tiles")


## HAZ-03 arms a point at its trigger tile, and disarms it once it falls.
func arm(point_id: int, tile: Vector2i) -> void:
	_points[point_id] = tile


func disarm(point_id: int) -> void:
	_points.erase(point_id)


func armed() -> Array:
	return _points.keys()


## Called by NoiseSystem for each event, after the creatures and the players.
func on_event(event_id: int, type: NoiseTypes.Type, origins: Array[Vector2i], level_np: float) -> PackedInt64Array:
	var fired: PackedInt64Array = PackedInt64Array()
	if road_graph == null:
		return fired
	var reach: float = -1.0
	if type == NoiseTypes.Type.FIREDAMP_BLAST:
		reach = blast_tiles
	elif level_np >= trigger_np:
		reach = trigger_tiles
	if reach < 0.0:
		return fired
	var ids: Array = _points.keys()
	ids.sort()
	for id: Variant in ids:
		var tile: Vector2i = _points[id]
		for origin: Vector2i in origins:
			var cost: float = road_graph.graph.path_cost(origin, tile, RoadGraphService.MODE_AIR, reach + 0.5)
			if cost >= 0.0 and cost <= reach + 0.001:
				fired.append(int(Variants.number(id)))
				collapse_triggered.emit(int(Variants.number(id)), event_id)
				break
	return fired
