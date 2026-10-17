extends GutTest
## RSC-06 (GDD §14.3): the Lamp Check card as a PNG. It renders at rescue.lamp_check_card_px with the
## card's text in ink, the same bytes every time, with no screen; it carries pixels only (no text,
## date or metadata chunk where a Steam name or lobby code could ride); it is kept under
## user://cards/<run uuid>.png and added to Steam's screenshot library.

const FakeSteam = preload("res://tests/unit/client/net/steam/fake_steam_api.gd")
const CARD: String = "Morrow Main, first shift. Up 4 of 5. Left Below: Ada Rowe, Lamp 114. Deepest: the Third Level. Below 1 h 42 min.\nDead: Wilfred Dodd, Lamp 207, brought home."


func before_all() -> void:
	assert_true(Tuning.load_client())


func _px() -> Vector2i:
	var px: Array[int] = Tuning.list_i(&"rescue.lamp_check_card_px")
	return Vector2i(px[0], px[1])


## The PNG's chunk types, in order.
func _chunk_types(png: PackedByteArray) -> Array[String]:
	var out: Array[String] = []
	var at: int = 8
	while at + 8 <= png.size():
		var length: int = (png[at] << 24) | (png[at + 1] << 16) | (png[at + 2] << 8) | png[at + 3]
		out.append(png.slice(at + 4, at + 8).get_string_from_ascii())
		at += 12 + length
	return out


func test_it_renders_the_card_in_ink_the_same_every_time() -> void:
	assert_eq(_px(), Vector2i(1920, 1080))
	var image: Image = LampCheckCardImage.render(CARD, _px())
	assert_eq(image.get_size(), _px())
	var inked: int = 0
	for y: int in range(0, image.get_height(), 3):
		for x: int in range(0, image.get_width(), 3):
			if image.get_pixel(x, y).get_luminance() < 0.3:
				inked += 1
	assert_gt(inked, 2000, "the text and the rule are printed")
	var again: PackedByteArray = LampCheckCardImage.render(CARD, _px()).save_png_to_buffer()
	assert_true(image.save_png_to_buffer() == again, "the same card, the same bytes")
	var blank: Image = LampCheckCardImage.render("", _px())
	assert_false(blank.save_png_to_buffer() == again, "the text is what is printed")


func test_it_carries_pixels_only() -> void:
	var png: PackedByteArray = LampCheckCardImage.render(CARD, _px()).save_png_to_buffer()
	var chunks: Array[String] = _chunk_types(png)
	assert_true(chunks.has("IDAT"))
	for chunk: String in chunks:
		assert_false(chunk in ["tEXt", "zTXt", "iTXt", "eXIf", "tIME"], "a %s chunk in the card" % chunk)


func test_it_is_kept_on_disk_and_in_steam() -> void:
	var image: Image = LampCheckCardImage.render(CARD, Vector2i(480, 270))
	var uuid: String = "test-lamp-card-%d" % Time.get_ticks_usec()
	var path: String = LampCheckCardImage.save(image, uuid)
	assert_eq(path, "user://cards/%s.png" % uuid)
	assert_true(FileAccess.file_exists(path))
	assert_eq(Image.load_from_file(path).get_size(), Vector2i(480, 270))
	assert_eq(LampCheckCardImage.save(image, "../escape"), "", "a run uuid is a file name, nothing else")
	var steam: SteamApi = FakeSteam.new()
	steam.init(0)
	assert_true(LampCheckCardImage.to_steam_library(steam, path, image))
	var fake: Object = steam
	assert_eq(Variants.array(fake.get(&"screenshots")).size(), 1, "into the screenshot library")
	assert_false(LampCheckCardImage.to_steam_library(null, path, image), "without Steam, the file only")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
