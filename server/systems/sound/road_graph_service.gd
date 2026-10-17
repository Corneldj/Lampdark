class_name RoadGraphService
extends RefCounted
## The run's Road Graph (SND-01): one per run, stitched from every committed cell's block as
## GEN-01 loads it, unloaded with it, and rebuilt in the same tick when a barrier flips or a
## collapse falls. Server-only: deliveries carry true_source, which no client record holds.

const MODE_AIR: int = 0
const MODE_VOICE: int = 1
## Gameplay §6.2, §3.2, §4.10: a voice's own Road Graph event (SND-09's bands, SND-11's callouts,
## SND-15's scream, all to creatures only) passes a closed air door or a shut gate at -12 np like any
## sound; only the voice itself (SND-07's delivery, MODE_VOICE) is cut there.
const MODE_VOICE_EVENT: int = MODE_AIR

var graph: LbRoadGraph = LbRoadGraph.new()
var mine: Mine
## Cells whose block failed to stitch (reported once each).
var failed_cells: Array[Vector2i] = []


func _init(server_mine: Mine, run_seed: int) -> void:
	mine = server_mine
	graph.attach(mine.native)
	graph.set_params(Tuning.f(&"noise.closed_portal_cost"), Tuning.f(&"noise.jitter_per_path_tile"), 64.0, run_seed)
	for raw: Variant in mine.native.loaded_cells():
		var cell: Vector2i = raw
		_stitch(cell)
	mine.native.cell_loaded.connect(_stitch)
	mine.native.cell_unloading.connect(func(cell: Vector2i) -> void: graph.unload(cell))
	mine.native.tiles_changed.connect(graph.on_tiles_changed)


func _stitch(cell: Vector2i) -> void:
	if not graph.stitch(cell):
		failed_cells.append(cell)


## A player listener: hears anything with 0 np or more left (noise.player_threshold).
func set_player_listener(id: int, tile: Vector2i) -> void:
	graph.set_listener(id, tile, Tuning.f(&"noise.player_threshold"), 1.0)


## A creature listener at its listening tile, with its ring's multiplier (DIR-04's table).
func set_creature_listener(id: int, tile: Vector2i, multiplier: float) -> void:
	graph.set_listener(id, tile, Tuning.f(&"noise.tapper_threshold"), multiplier)


func remove_listener(id: int) -> void:
	graph.remove_listener(id)


## Every listener that hears an event. Each result is a delivery Dictionary (server-only).
func propagate(event_id: int, origins: Array[Vector2i], level_np: float, mode: int = MODE_AIR) -> Array:
	return graph.propagate(event_id, origins, level_np, mode)
