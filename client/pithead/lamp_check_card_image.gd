class_name LampCheckCardImage
extends RefCounted
## RSC-06 (GDD §14.3): the shareable Lamp Check card as a PNG, rescue.lamp_check_card_px (1920x1080,
## Proposed): the card's text in Company print, dark ink on pale card stock inside a ruled border,
## printed on the CPU from the UI font's own glyphs (GlyphPrint), so it renders the same without a
## screen. It holds only the card's text as pixels: no metadata, no text chunk, and so never a
## Steam name or a lobby code. Kept under user://cards/<run_uuid>.png and added to Steam's
## screenshot library (Proposed: how a Deck player shares it). Placeholder layout until the final
## card in period print. Client-side.

const DIR: String = "user://cards"
const CARD: Color = Color(0.92, 0.88, 0.78)
const INK: Color = Color(0.13, 0.11, 0.09)


## The card at `px`, from its text (LampCheckCard's: the first line the card, then a line for
## each body brought home).
static func render(text: String, px: Vector2i) -> Image:
	var image: Image = Image.create(maxi(64, px.x), maxi(64, px.y), false, Image.FORMAT_RGB8)
	image.fill(CARD)
	var w: int = image.get_width()
	var h: int = image.get_height()
	var margin: int = w / 12
	var rule: int = maxi(2, h / 270)
	for edge: Rect2i in [Rect2i(margin / 2, margin / 2, w - margin, rule), Rect2i(margin / 2, h - margin / 2 - rule, w - margin, rule),
			Rect2i(margin / 2, margin / 2, rule, h - margin), Rect2i(w - margin / 2 - rule, margin / 2, rule, h - margin)]:
		image.fill_rect(edge, INK)
	var height_px: float = h / 14.0
	var y: float = margin + height_px
	for paragraph: String in text.split("\n", false):
		for line: String in GlyphPrint.wrap(paragraph, height_px, w - margin * 2):
			GlyphPrint.line(image, line, Vector2(margin, y), height_px, INK)
			y += height_px * 1.25
		y += height_px * 0.5
	return image


## Writes the card to user://cards/<run_uuid>.png: its path, or "" on failure.
static func save(image: Image, run_uuid: String) -> String:
	if image == null or run_uuid.is_empty() or not run_uuid.is_valid_filename():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path: String = DIR.path_join(run_uuid + ".png")
	return path if image.save_png(path) == OK else ""


## Adds a saved card to Steam's screenshot library (Proposed); false without Steam.
static func to_steam_library(api: SteamApi, path: String, image: Image) -> bool:
	if api == null or image == null or path.is_empty():
		return false
	return api.add_screenshot(ProjectSettings.globalize_path(path), image.get_width(), image.get_height())
