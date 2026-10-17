class_name GlyphPrint
extends RefCounted
## Text printed onto an Image on the CPU, from the UI font's own cached glyph images (LFT-14's map
## card labels, RSC-06's Lamp Check card): the same font, size and text give the same pixels on
## every client, with a screen or without one. Client-side.


## Prints `text` with its left end at `at` (pixels), `height_px` tall, in `ink`.
static func line(image: Image, text: String, at: Vector2, height_px: float, ink: Color) -> void:
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
				_blit(image, glyphs, Rect2i(uv), Vector2i((pen + offset).round()), ink)
		pen.x += advance
	ts.free_rid(shaped)


## How wide `text` prints at `height_px` (pixels).
static func width(text: String, height_px: float) -> float:
	var size: int = clampi(roundi(height_px * 0.7), 6, 256)
	if text.is_empty():
		return 0.0
	var ts: TextServer = TextServerManager.get_primary_interface()
	var shaped: RID = ts.create_shaped_text()
	ts.shaped_text_add_string(shaped, text, ThemeDB.fallback_font.get_rids(), size)
	ts.shaped_text_shape(shaped)
	var w: float = ts.shaped_text_get_width(shaped)
	ts.free_rid(shaped)
	return w


## `text`'s words in lines no wider than `max_px` at `height_px` (a word too long stands alone).
static func wrap(text: String, height_px: float, max_px: float) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var current: String = ""
	for word: String in text.split(" ", false):
		var tried: String = word if current.is_empty() else current + " " + word
		if current.is_empty() or width(tried, height_px) <= max_px:
			current = tried
		else:
			out.append(current)
			current = word
	if not current.is_empty():
		out.append(current)
	return out


## The glyph's coverage as ink over the image.
static func _blit(image: Image, glyphs: Image, src: Rect2i, dst: Vector2i, ink: Color) -> void:
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
			image.set_pixel(tx, ty, image.get_pixel(tx, ty).lerp(ink, a))
