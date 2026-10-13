extends GutTest
## VIS-05: the drawn set is the server's seen tiles, revealed margin records and provisional held
## tiles; entities only from fringe tokens, identities and revealed margin records; a hidden margin
## record is never drawn before its reveal; an entity the server stops sending is gone at once.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _view() -> ReceivedView:
	var v: ReceivedView = ReceivedView.new()
	v.own["position"] = Vector2(10.5, 10.5)
	for x: int in range(11, 15):
		v.tiles[Vector2i(x, 10)] = PackedByteArray([200, 1, 0])
		v.geometry[Vector2i(x, 10)] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])
	v.entities[7] = {"level": 2, "size_or_kind": 1, "position": Vector2(12.5, 10.5)}
	v.entities[8] = {"level": 1, "size_or_kind": 1, "position": Vector2(13.5, 10.5)}
	# A hidden margin record far beyond the lamp.
	v.entities[9] = {"level": 3, "size_or_kind": 1, "position": Vector2(30.5, 10.5)}
	return v


func _predicted(radius: float) -> Dictionary:
	return {"position": Vector2(10.5, 10.5), "facing": 0, "lamp": {"position": Vector2(10.5, 10.5), "radius": radius}}


func test_seen_tiles_and_entities() -> void:
	var d: DrawnSet = DrawnSet.new()
	d.build(_view(), _predicted(4.0), 0, -1)
	assert_eq(d.tiles.size(), 4)
	assert_almost_eq(float(Variants.number(Variants.dict(d.tiles[Vector2i(11, 10)])["light"])), 200.0 / 255.0, 1e-6)
	assert_eq(d.entities, [7, 8] as Array[int], "a token and an identity; the hidden margin record is not drawn")


func test_hidden_margin_drawn_once_revealed() -> void:
	var v: ReceivedView = _view()
	v.entities[9] = {"level": 3, "size_or_kind": 1, "position": Vector2(13.0, 10.5)}
	var d: DrawnSet = DrawnSet.new()
	d.build(v, _predicted(1.5), 0, -1)
	assert_false(d.entities.has(9), "the predicted light does not reach it: hidden")
	d.build(v, _predicted(5.5), 0, -1)
	assert_true(d.entities.has(9), "the wick up reaches it: revealed")


func test_an_entity_the_server_stops_sending_is_gone() -> void:
	var v: ReceivedView = _view()
	var d: DrawnSet = DrawnSet.new()
	d.build(v, _predicted(4.0), 0, -1)
	assert_true(d.entities.has(7))
	v.entities.erase(7)
	d.build(v, _predicted(4.0), 0, -1)
	assert_false(d.entities.has(7), "gone the next frame: no ghost, no fade, no last-known marker")


func test_never_anything_not_received() -> void:
	var v: ReceivedView = _view()
	var d: DrawnSet = DrawnSet.new()
	d.build(v, _predicted(8.0), 0, 0)
	for raw: Variant in d.tiles.keys():
		assert_true(v.tiles.has(raw) or v.geometry.has(raw), "%s was received" % raw)
	for token: int in d.entities:
		assert_true(v.entities.has(token))
