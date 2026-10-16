extends "res://tests/unit/vis/render/render_test.gd"
## LFT-14 with GDD §14.1: on the map table's close-up at a Steam Deck's 1280 x 800, a pencil line is
## at least 3 px wide at 1x however far the sheet is zoomed out, and twice that at the 2x line weight
## (UI-06's option). The width is the line's ink across a row: each pixel counts as far as it is
## from paper towards pencil, less the faint printed squares beside it.


func _closeup(cs: ClientSheet, squares: float, weight: float) -> MapTableCloseup:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = CloseupManager.LAYER
	add_child_autofree(layer)
	var m: MapTableCloseup = MapTableCloseup.new()
	m.client_sheet = func() -> ClientSheet: return cs
	layer.add_child(m)
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m.position = Vector2.ZERO
	m.size = Vector2(1280, 800)
	m.visible = true
	m.on_open({"kind": CloseupKind.Kind.MAP_TABLE})
	m.squares_across = squares
	m.line_weight = weight
	m.step(0.016)
	return m


## The line's ink across row `y` near x: the sum of each pixel's darkening, paper to pencil.
func _ink(img: Image, x: int, y: int) -> float:
	var paper: float = CloseupBase.PAPER.get_luminance()
	var pencil: float = MapTableCloseup.PENCIL_GREY.get_luminance()
	var ink: float = 0.0
	for dx: int in range(-12, 13):
		var l: float = img.get_pixel(x + dx, y).get_luminance()
		ink += clampf((paper - l) / (paper - pencil), 0.0, 1.0)
	return ink


func test_pencil_lines_are_at_least_3_px_on_a_deck_at_1x() -> void:
	if skip_without_renderer():
		return
	var cs: ClientSheet = ClientSheet.new()
	cs.sheet.add_stroke(SheetStroke.make(1, -1, PackedVector2Array([Vector2(1024, -16000), Vector2(1024, 16000)])))
	var seen: Array[String] = []
	for squares: float in [12.0, Tuning.f(&"mine.sheet_view_squares_max")]:
		for weight: float in [1.0, 2.0]:
			var m: MapTableCloseup = _closeup(cs, squares, weight)
			var img: Image = await capture()
			var at: Vector2 = m.to_screen(Vector2(1024, 0))
			# Less the paper's own faint squares nearby (the same count of them in each window).
			var ink: float = _ink(img, roundi(at.x), 200) - _ink(img, roundi(at.x) - 50, 200)
			seen.append("%d squares %.0fx %.2f px" % [squares, weight, ink])
			assert_gte(ink, Tuning.f(&"mine.pencil_min_px") * weight - 0.25, "at least 3 px a weight")
			var layer: CanvasLayer = m.get_parent()
			layer.visible = false
	gut.p("pencil ink across a line at 1280 x 800: " + ", ".join(seen))
