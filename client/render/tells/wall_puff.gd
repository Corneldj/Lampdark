class_name WallPuffs
extends Node2D
## VIS-09: puffs of dust off lit wall faces where the tapper tapped, and bursts of dust (laying, a
## flinch), from the server's VisualEvents: each a soft ring of dust that grows and fades. Only
## where the server sent one (it sends only to viewers who see the place lit).

## {at (tiles), radius (tiles), start_s, seconds}
var active: Array[Dictionary] = []
var _origin: Vector2 = Vector2.ZERO
var _px: float = 64.0
var _now: float = 0.0


func add(record: AudioRecord, now_s: float) -> void:
	var radius: float = 0.6 if record.type == VisualEvents.Type.PUFF else maxf(0.5, record.level_np)
	active.append({"at": record.apparent, "radius": radius, "start_s": now_s, "seconds": maxf(0.2, record.duration_s)})


func set_frame(origin: Vector2, px: float, now_s: float) -> void:
	_origin = origin
	_px = px
	_now = now_s
	var kept: Array[Dictionary] = []
	for p: Dictionary in active:
		if now_s - float(Variants.number(p["start_s"])) <= float(Variants.number(p["seconds"])):
			kept.append(p)
	active = kept
	queue_redraw()


func _draw() -> void:
	for p: Dictionary in active:
		var age: float = clampf((_now - float(Variants.number(p["start_s"]))) / float(Variants.number(p["seconds"])), 0.0, 1.0)
		var c: Color = Palette.DUST_GREY
		c.a = 0.5 * (1.0 - age)
		var at: Vector2 = p["at"]
		draw_circle((at - _origin) * _px, float(Variants.number(p["radius"])) * _px * (0.4 + 0.6 * age), c)
