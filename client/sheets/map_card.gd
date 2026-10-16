class_name MapCard
extends RefCounted
## LFT-14: the map card (Gameplay §12.7; GDD §14.3): a PNG of the map table's sheet as the cage left
## it or at the wipe, shown at Lamp Check (RSC-06) and kept by choice under
## user://map_cards/<run_uuid>.png and in the Steam screenshot library (Proposed). Square,
## mine.map_card_px a side, cropped to what was drawn with the printed shaft and north point always
## in, on survey paper in pencil grey. It is drawn on the CPU (LbSheet for the lines, the
## font's own glyph images for the labels), so every client holding the same sheet makes the same
## bytes, apart from what STM-08's filter and blocks change. It adds nothing of its own: no name,
## no SteamID, no lobby code, no date. Client-side.

## Survey paper, its faint squares, pencil grey and the printed marks (GDD §14.1: pencil grey on
## survey paper; never amber, umber or egg-glow).
const PAPER: Color = Color(0.86, 0.82, 0.71)
const SQUARES: Color = Color(0.62, 0.68, 0.70, 0.35)
const PENCIL: Color = Color(0.25, 0.25, 0.26)
const PRINT: Color = Color(0.16, 0.14, 0.12)
## A printed square, in sheet units.
const SQUARE_UNITS: int = 256
## The margin round what was drawn, in squares.
const MARGIN_SQUARES: float = 1.0
const DIR: String = "user://map_cards"


## The printed marks (Gameplay §12.7: only a north point and the shaft, at the centre) as polylines.
static func printed() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var h: float = SQUARE_UNITS * 0.25
	# The shaft: a small square with its cross.
	out.append(PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h), Vector2(-h, -h)]))
	out.append(PackedVector2Array([Vector2(-h, -h), Vector2(h, h)]))
	out.append(PackedVector2Array([Vector2(h, -h), Vector2(-h, h)]))
	# The north point beside it: an arrow up and an N.
	var n: Vector2 = Vector2(SQUARE_UNITS * 1.5, -SQUARE_UNITS * 0.5)
	out.append(PackedVector2Array([n + Vector2(0, 160), n + Vector2(0, -160)]))
	out.append(PackedVector2Array([n + Vector2(-60, -90), n + Vector2(0, -160), n + Vector2(60, -90)]))
	var m: Vector2 = n + Vector2(0, -260)
	out.append(PackedVector2Array([m + Vector2(-40, 50), m + Vector2(-40, -50), m + Vector2(40, 50), m + Vector2(40, -50)]))
	return out


## The square of the sheet the card shows: what was drawn and the printed marks, with a margin.
static func frame(sheet: Sheet) -> Rect2:
	var r: Rect2 = Rect2(Vector2(-SQUARE_UNITS * 1.0, -SQUARE_UNITS * 1.5), Vector2(SQUARE_UNITS * 3.0, SQUARE_UNITS * 2.5))
	if sheet.count() > 0:
		r = r.merge(sheet.extent())
	r = r.grow(SQUARE_UNITS * MARGIN_SQUARES)
	var side: float = maxf(r.size.x, r.size.y)
	return Rect2(r.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))


## The card for this client's copy of the sheet: an RGBA8 image `px` a side.
static func render(cs: ClientSheet, px: int) -> Image:
	var sheet: Sheet = cs.sheet
	var view: Rect2 = frame(sheet)
	var scale: float = px / view.size.x
	var min_px: float = Tuning.f(&"mine.pencil_min_px")
	var layers: Array = [_grid(view), _layer(printed(), PRINT, maxf(min_px, 2.0))]
	var lines: Array[PackedVector2Array] = []
	var ids: Array = sheet.strokes.keys()
	ids.sort()
	for raw: Variant in ids:
		var s: SheetStroke = sheet.strokes[raw]
		lines.append(s.points)
	layers.append(_layer(lines, PENCIL, maxf(min_px, Tuning.f(&"mine.pencil_width_units") * scale)))
	var bytes: PackedByteArray = LbSheet.render({"origin": view.position, "scale": scale, "size": Vector2i(px, px)},
		_rgba(PAPER), layers)
	if bytes.is_empty():
		return null
	var image: Image = Image.create_from_data(px, px, false, Image.FORMAT_RGBA8, bytes)
	var label_ids: Array = sheet.labels.keys()
	label_ids.sort()
	for raw: Variant in label_ids:
		var l: SheetLabel = sheet.labels[raw]
		_label(image, cs.shown_text(l), (l.anchor - view.position) * scale, Tuning.f(&"mine.sheet_label_height_units") * scale)
	return image


## Writes the card to user://map_cards/<run_uuid>.png; its path, or "" on failure.
static func save(image: Image, run_uuid: String) -> String:
	if image == null or run_uuid.is_empty() or not run_uuid.is_valid_filename():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path: String = DIR.path_join(run_uuid + ".png")
	return path if image.save_png(path) == OK else ""


## Adds a saved card to the Steam screenshot library (Proposed); false without Steam.
static func to_steam_library(api: SteamApi, path: String, image: Image) -> bool:
	if api == null or image == null or path.is_empty():
		return false
	return api.add_screenshot(ProjectSettings.globalize_path(path), image.get_width(), image.get_height())


## The faint squares inside the view.
static func _grid(view: Rect2) -> Dictionary:
	var lines: Array[PackedVector2Array] = []
	var x0: int = ceili(view.position.x / SQUARE_UNITS) * SQUARE_UNITS
	var y0: int = ceili(view.position.y / SQUARE_UNITS) * SQUARE_UNITS
	var x: int = x0
	while x <= view.end.x:
		lines.append(PackedVector2Array([Vector2(x, view.position.y), Vector2(x, view.end.y)]))
		x += SQUARE_UNITS
	var y: int = y0
	while y <= view.end.y:
		lines.append(PackedVector2Array([Vector2(view.position.x, y), Vector2(view.end.x, y)]))
		y += SQUARE_UNITS
	return _layer(lines, SQUARES, 1.0)


static func _layer(lines: Array[PackedVector2Array], colour: Color, width_px: float) -> Dictionary:
	var xy: PackedInt32Array = PackedInt32Array()
	var starts: PackedInt32Array = PackedInt32Array()
	for line: PackedVector2Array in lines:
		starts.append(xy.size() >> 1)
		for p: Vector2 in line:
			xy.append(roundi(p.x))
			xy.append(roundi(p.y))
	return {"xy": xy, "starts": starts, "rgba": _rgba(colour), "width_px": width_px}


static func _rgba(c: Color) -> int:
	return c.to_rgba32()


## Blits a label's glyphs, from the font's own cached glyph images, onto the card: its left end at
## `at` (pixels), `height_px` tall. The same font and size give the same pixels everywhere.
static func _label(image: Image, text: String, at: Vector2, height_px: float) -> void:
	var size: int = clampi(roundi(height_px * 0.7), 6, 256)
	if text.is_empty() or height_px < 4.0:
		return
	var ts: TextServer = TextServerManager.get_primary_interface()
	var font: Font = ThemeDB.fallback_font
	var shaped: RID = ts.create_shaped_text()
	ts.shaped_text_add_string(shaped, text, font.get_rids(), size)
	ts.shaped_text_shape(shaped)
	var pen: Vector2 = at + Vector2(0, size * 0.35)
	for g: Dictionary in ts.shaped_text_get_glyphs(shaped):
		var frid: RID = g["font_rid"]
		var index: int = g["index"]
		var at_size: Vector2i = Vector2i(size, 0)
		var advance: float = g["advance"]
		var tex: int = ts.font_get_glyph_texture_idx(frid, at_size, index)
		if tex >= 0:
			var uv: Rect2 = ts.font_get_glyph_uv_rect(frid, at_size, index)
			var offset: Vector2 = ts.font_get_glyph_offset(frid, at_size, index)
			var glyphs: Image = ts.font_get_texture_image(frid, at_size, tex)
			if glyphs != null and uv.size.x > 0 and uv.size.y > 0:
				_blit(image, glyphs, Rect2i(uv), Vector2i((pen + offset).round()))
		pen.x += advance
	ts.free_rid(shaped)


## The glyph's coverage as pencil over the card.
static func _blit(image: Image, glyphs: Image, src: Rect2i, dst: Vector2i) -> void:
	# A font's cache is LA8 (coverage in alpha) or, for some fonts, RGBA8.
	var use_alpha: bool = glyphs.get_format() == Image.FORMAT_LA8 or glyphs.get_format() == Image.FORMAT_RGBA8
	for y: int in src.size.y:
		var ty: int = dst.y + y
		if ty < 0 or ty >= image.get_height():
			continue
		for x: int in src.size.x:
			var tx: int = dst.x + x
			if tx < 0 or tx >= image.get_width():
				continue
			var g: Color = glyphs.get_pixel(src.position.x + x, src.position.y + y)
			var a: float = g.a if use_alpha else g.r
			if a <= 0.0:
				continue
			image.set_pixel(tx, ty, image.get_pixel(tx, ty).lerp(PENCIL, a))
