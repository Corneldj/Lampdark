extends GutTest
## VIS-05 (GDD §5.6): an about-turn draws held walls at once under the predicted own light, as
## provisional tiles; once the server frame acknowledging the input that carried the new facing
## arrives, only tiles it lists stay, so a bite or a shadow disappears within one server frame.


func before_all() -> void:
	assert_true(Tuning.load_server())


## Facing east, seen tiles ahead; held walls and floor behind (west), never listed as seen.
func _view() -> ReceivedView:
	var v: ReceivedView = ReceivedView.new()
	v.own["position"] = Vector2(20.5, 10.5)
	v.own["lamp_radius"] = 4.0  # the server's own lamp, as the own block carries it
	for x: int in range(21, 24):
		v.tiles[Vector2i(x, 10)] = PackedByteArray([220, 1, 0])
		v.geometry[Vector2i(x, 10)] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])
	for x: int in range(16, 20):
		v.geometry[Vector2i(x, 10)] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])
	v.geometry[Vector2i(15, 10)] = PackedByteArray([WorldIds.TileMaterial.ROCK, 0])
	return v


func _west(radius: float = 4.0) -> Dictionary:
	return {"position": Vector2(20.5, 10.5), "facing": Intents.facing_u16(180.0), "lamp": {"position": Vector2(20.5, 10.5), "radius": radius}}


func test_about_turn_draws_held_walls_provisionally_then_reconciles() -> void:
	var v: ReceivedView = _view()
	var d: DrawnSet = DrawnSet.new()
	# The input that turned west is seq 41; the server has applied up to 40.
	d.build(v, _west(), 40, 41)
	assert_gt(d.provisional_count, 0, "held walls drawn at once")
	assert_true(d.tiles.has(Vector2i(18, 10)) and Variants.flag(Variants.dict(d.tiles[Vector2i(18, 10)])["provisional"]))
	assert_true(d.tiles.has(Vector2i(17, 10)), "under the predicted lamp")
	assert_false(d.tiles.has(Vector2i(15, 10)), "beyond the predicted light: not drawn")
	# The server's frame acknowledging seq 41 lists only 18 and 19 (a bite took the rest).
	var acked: ReceivedView = _view()
	acked.tiles.clear()
	for x: int in [18, 19]:
		acked.tiles[Vector2i(x, 10)] = PackedByteArray([200, 1, 0])
	d.build(acked, _west(), 41, 41)
	assert_eq(d.provisional_count, 0, "nothing provisional once acknowledged")
	assert_false(d.tiles.has(Vector2i(17, 10)), "the bite: gone within one server frame")
	assert_true(d.tiles.has(Vector2i(18, 10)))


func test_no_provisional_without_light_or_outside_the_cone() -> void:
	var v: ReceivedView = _view()
	var d: DrawnSet = DrawnSet.new()
	d.build(v, _west(0.0), 40, 41)
	assert_eq(d.provisional_count, 0, "no own light: nothing provisional")
	var east: Dictionary = {"position": Vector2(20.5, 10.5), "facing": Intents.facing_u16(0.0), "lamp": {"position": Vector2(20.5, 10.5), "radius": 4.0}}
	d.build(v, east, 40, 41)
	assert_false(d.tiles.has(Vector2i(18, 10)), "outside the predicted cone: never")


func test_sequence_numbers_wrap() -> void:
	var v: ReceivedView = _view()
	var d: DrawnSet = DrawnSet.new()
	d.build(v, _west(), 65535, 1)
	assert_gt(d.provisional_count, 0, "seq 1 is after 65535")
	d.build(v, _west(), 1, 1)
	assert_eq(d.provisional_count, 0)
