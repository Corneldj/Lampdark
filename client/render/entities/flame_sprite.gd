class_name FlameSprite
extends RefCounted
## VIS-06: the base flame, light.flame_sprite_tiles across (a third of a tile), per source type: the
## gauze lamp's amber teardrop, a candle's smaller one. VIS-08's states reshape it (FlameStateView);
## the electric lamp is no flame and never gets one.


static func draw(ci: CanvasItem, at_px: Vector2, px: float, kind: int, flags: int, t: float) -> void:
	if kind == ItemKinds.Kind.ELECTRIC_LAMP:
		return
	var across: float = Tuning.f(&"light.flame_sprite_tiles") * px * (0.75 if kind == ItemKinds.Kind.CANDLE else 1.0)
	var scale: float = across / FlameStateView.BASE_W
	var polys: Array[PackedVector2Array] = FlameStateView.shapes(flags, t)
	var body: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in polys[0]:
		body.append(at_px + p * scale)
	ci.draw_colored_polygon(body, Palette.PALE_AMBER if (flags & FlameFlags.FLARE_UP) != 0 else Palette.LAMP_AMBER)
	if polys.size() > 1:
		var cap: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in polys[1]:
			cap.append(at_px + p * scale)
		ci.draw_colored_polygon(cap, Palette.FIREDAMP_BLUE)
