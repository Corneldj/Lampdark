extends GutTest
## VIS-06: the light texture holds each drawn tile's light, class, sent flag and solidity; its
## sampling (the light pool's rule) never lets light bleed into an unsent tile and blends only over
## sent neighbours, so a bite stays a hard notch.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _drawn(tiles: Dictionary) -> DrawnSet:
	var d: DrawnSet = DrawnSet.new()
	for raw: Variant in tiles.keys():
		d.tiles[raw] = {"light": tiles[raw], "colour": 1, "material": WorldIds.TileMaterial.FLOOR, "state": 0, "provisional": false}
	return d


func test_texels() -> void:
	var lt: LightTexture = LightTexture.new()
	var d: DrawnSet = _drawn({Vector2i(3, 2): 1.0, Vector2i(4, 2): 0.5})
	d.tiles[Vector2i(5, 2)] = {"light": 0.3, "colour": 3, "material": WorldIds.TileMaterial.ROCK, "state": 0, "provisional": false}
	lt.build(d, {}, Vector2(0, 0), Vector2(30, 16.875))
	var c: Color = lt.image.get_pixelv(Vector2i(4, 2) - lt.origin)
	assert_eq(c.r8, 128, "light 0.5")
	assert_eq(c.b8, 255, "sent")
	var w: Color = lt.image.get_pixelv(Vector2i(5, 2) - lt.origin)
	assert_eq(w.g8, 3, "colour class")
	assert_eq(w.a8, 255, "solid")
	assert_eq(lt.image.get_pixelv(Vector2i(9, 9) - lt.origin).b8, 0, "unsent")


func test_no_bleed_into_unsent() -> void:
	var lt: LightTexture = LightTexture.new()
	# A bright tile beside an unsent one (a bite).
	lt.build(_drawn({Vector2i(10, 5): 1.0, Vector2i(10, 6): 1.0}), {}, Vector2(0, 0), Vector2(30, 16.875))
	assert_eq(lt.sample(Vector2(11.01, 5.5)), 0.0, "one step inside the unsent neighbour: nothing")
	assert_eq(lt.sample(Vector2(10.99, 5.5)), 1.0, "up to the edge: full, no fade toward the unsent tile")
	assert_almost_eq(lt.sample(Vector2(10.5, 6.0)), 1.0, 1e-6, "between two sent tiles: blended")


func test_blends_only_sent_neighbours() -> void:
	var lt: LightTexture = LightTexture.new()
	lt.build(_drawn({Vector2i(2, 2): 0.2, Vector2i(3, 2): 1.0}), {}, Vector2(0, 0), Vector2(30, 16.875))
	assert_almost_eq(lt.sample(Vector2(3.0, 2.5)), 0.6, 1e-6, "halfway between centres")
	assert_almost_eq(lt.sample(Vector2(2.5, 2.5)), 0.2, 1e-6, "at a centre: its own value")
