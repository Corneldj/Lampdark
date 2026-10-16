extends SceneTree
## Writes GEN-04's debug tile palette, addons/lampblack_templates/palette.tres: one 16 px tile per
## CellFile tile character (custom data "char") and a row of rib-edge offsets (custom data "milli"),
## its texture embedded. Run once after changing TemplateScaffold.CHAR_ORDER or RIB_MILLI:
##   godot --headless --path . -s tools/build/gen_template_palette.gd

const PX: int = 16
## Tile character -> [fill, mark]: the mark draws rails (=), mud (~) or an open gate or door (s, d).
const LOOK: Dictionary = {
	".": [Color(0.78, 0.76, 0.70), ""],
	"=": [Color(0.78, 0.76, 0.70), "rails"],
	"~": [Color(0.45, 0.36, 0.24), "mud"],
	"#": [Color(0.27, 0.27, 0.29), ""],
	"c": [Color(0.07, 0.07, 0.08), ""],
	"B": [Color(0.62, 0.25, 0.18), ""],
	"T": [Color(0.70, 0.55, 0.32), ""],
	"S": [Color(0.35, 0.45, 0.58), ""],
	"s": [Color(0.35, 0.45, 0.58), "open"],
	"D": [Color(0.40, 0.27, 0.15), ""],
	"d": [Color(0.40, 0.27, 0.15), "open"],
}


func _init() -> void:
	var chars: Array[String] = TemplateScaffold.CHAR_ORDER
	var rib: Array[int] = TemplateScaffold.RIB_MILLI
	var img: Image = Image.create_empty(PX * maxi(chars.size(), rib.size()), PX * 2, false, Image.FORMAT_RGBA8)
	for i: int in chars.size():
		var look: Array = LOOK[chars[i]]
		var fill: Color = look[0]
		var x0: int = i * PX
		img.fill_rect(Rect2i(x0, 0, PX, PX), fill.darkened(0.35))
		img.fill_rect(Rect2i(x0 + 1, 1, PX - 2, PX - 2), fill)
		match str(look[1]):
			"rails":
				img.fill_rect(Rect2i(x0 + 2, 5, PX - 4, 1), Color(0.2, 0.2, 0.2))
				img.fill_rect(Rect2i(x0 + 2, 10, PX - 4, 1), Color(0.2, 0.2, 0.2))
			"mud":
				for k: int in 4:
					img.fill_rect(Rect2i(x0 + 3 + k * 3, 4 + (k % 2) * 5, 2, 2), fill.darkened(0.4))
			"open":
				img.fill_rect(Rect2i(x0 + 4, 4, PX - 8, PX - 8), Color(0.78, 0.76, 0.70))
	for j: int in rib.size():
		var x0: int = j * PX
		var length: int = maxi(2, roundi(float(rib[j]) / 250.0 * (PX - 2)))
		img.fill_rect(Rect2i(x0 + 1, PX + PX / 2 - 1, length, 3), Color(1.0, 0.95, 0.6))
	var tiles: TileSet = TileSet.new()
	tiles.tile_size = Vector2i(PX, PX)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(0, "char")
	tiles.set_custom_data_layer_type(0, TYPE_STRING)
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(1, "milli")
	tiles.set_custom_data_layer_type(1, TYPE_INT)
	var atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(img)
	atlas.texture_region_size = Vector2i(PX, PX)
	tiles.add_source(atlas, 0)
	for i: int in chars.size():
		atlas.create_tile(Vector2i(i, 0))
		atlas.get_tile_data(Vector2i(i, 0), 0).set_custom_data("char", chars[i])
	for j: int in rib.size():
		atlas.create_tile(Vector2i(j, 1))
		atlas.get_tile_data(Vector2i(j, 1), 0).set_custom_data("milli", rib[j])
	var err: Error = ResourceSaver.save(tiles, TemplateScaffold.PALETTE)
	print("gen_template_palette: %s %s" % [TemplateScaffold.PALETTE, error_string(err)])
	quit(0 if err == OK else 1)
