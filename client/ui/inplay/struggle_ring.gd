class_name StruggleRing
extends Node2D
## RSC-03's struggle as a standard skill check (Proposed after the first playtest): a ring above the
## own miner with the zone marked and a needle sweeping it at the server's pace, from the own status
## (StatusWire); a pip for each hit made and needed; dimmed through a miss's lockout. The client
## draws it only: the press goes up as ActionRecord.Kind.STRUGGLE and the server judges it at the
## tick shown here.

const RADIUS: float = 52.0

var status: Dictionary = {}
var needle: float = 0.0
var locked: bool = false
var _at: Vector2 = Vector2.ZERO


func _init() -> void:
	ScreenElementRegistry.mark(self, &"struggle")
	visible = false


## One frame. `shown`: a struggle is offered and play is on screen; `own_px`: the own miner on the
## canvas; `shown_tick`: the tick the client shows, with its fraction.
func update(shown: bool, own_status: Dictionary, own_px: Vector2, shown_tick: float) -> void:
	status = own_status
	visible = shown and (int(Variants.number(own_status.get("flags", 0))) & StatusWire.STRUGGLE) != 0
	if not visible:
		return
	needle = StatusWire.needle_deg(own_status, shown_tick)
	locked = shown_tick < float(Variants.number(own_status.get("lockout_until", 0)))
	_at = own_px + Vector2(0.0, -RADIUS * 2.4)
	queue_redraw()


func _draw() -> void:
	var ink: Color = ScreenElementRegistry.DIM if locked else ScreenElementRegistry.INK
	draw_circle(_at, RADIUS + 10.0, ScreenElementRegistry.PANEL)
	draw_arc(_at, RADIUS, 0.0, TAU, 48, ScreenElementRegistry.DIM, 4.0, true)
	var start: float = deg_to_rad(float(Variants.number(status.get("zone_start", 0.0))) - 90.0)
	var size: float = deg_to_rad(float(Variants.number(status.get("zone_size", 0.0))))
	draw_arc(_at, RADIUS, start, start + size, 24, ink, 12.0, true)
	var a: float = deg_to_rad(needle - 90.0)
	draw_line(_at, _at + Vector2(cos(a), sin(a)) * (RADIUS + 8.0), ink, 4.0, true)
	draw_circle(_at, 6.0, ink)
	var needed: int = int(Variants.number(status.get("needed", 0)))
	var hits: int = int(Variants.number(status.get("hits", 0)))
	for i: int in needed:
		var p: Vector2 = _at + Vector2((i - (needed - 1) * 0.5) * 18.0, RADIUS + 24.0)
		if i < hits:
			draw_circle(p, 6.0, ScreenElementRegistry.INK)
		else:
			draw_arc(p, 6.0, 0.0, TAU, 12, ScreenElementRegistry.DIM, 2.0, true)
