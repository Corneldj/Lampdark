class_name EmergencyLights
extends RefCounted
## LFT-01: base camp's emergency lamps, one VIS-02 area source of basecamp.emergency_light_level
## over base camp's floor (the deck included, never the arches), base camp white. Electric, never
## a flame: no snuff, smother, brood, blackdamp or gutter reaches it (those act on point sources
## and flames), and the Moth cannot take it (CRT-04 finds it by its kind, KIND, to cover it).

const KIND: String = "emergency"

var source: int = 0


func install(run: RunState, inside: Dictionary) -> void:
	var tiles: Array = inside.keys()
	tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	source = run.light.grid.add_area(KIND, LbLightGrid.COLOUR_WHITE, 0, Tuning.f(&"basecamp.emergency_light_level"), tiles)
