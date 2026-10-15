extends GutTest
## CRT-15: the trail store. The grab tile takes the heading of the first step off it; every tile
## the victim crosses is smeared toward travel; a tile crossed twice keeps its latest direction; a
## roof fall erases exactly the tiles it covers; every smear and wipe goes to VIS-10's trail.


class FakeStythe:
	extends RefCounted
	signal drag_tile_crossed(tile: Vector2i, dir: int)


var _smeared: Dictionary = {}
var _wiped: Array[Vector2i] = []


func _trail() -> BloodTrail:
	_smeared.clear()
	_wiped.clear()
	var t: BloodTrail = BloodTrail.new()
	t.smear = func(tile: Vector2i, direction: int) -> void: _smeared[tile] = direction
	t.wipe = func(tile: Vector2i) -> void:
		_wiped.append(tile)
		_smeared.erase(tile)
	return t


func _drag(t: BloodTrail, path: Array[Vector2i]) -> void:
	t._on_crossed(path[0], -1)
	for i: int in range(1, path.size()):
		t._on_crossed(path[i], VisionSystem.trail_direction(Vector2(path[i - 1]), Vector2(path[i])))


func test_every_tile_crossed_points_along_the_drag() -> void:
	var t: BloodTrail = _trail()
	var path: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(4, 6)]
	_drag(t, path)
	assert_eq(t.tiles.size(), 5, "the grab tile and every tile after it")
	assert_eq(t.direction_at(Vector2i(3, 3)), 0, "the grab tile: the first step's heading (east)")
	assert_eq(t.direction_at(Vector2i(4, 3)), 0)
	assert_eq(t.direction_at(Vector2i(5, 4)), 1, "south-east")
	assert_eq(t.direction_at(Vector2i(5, 5)), 2, "south")
	assert_eq(t.direction_at(Vector2i(4, 6)), 3, "south-west")
	assert_eq(_smeared.size(), 5, "each smeared through VIS-10's trail")
	assert_eq(int(Variants.number(_smeared[Vector2i(5, 5)])), 2)


func test_a_tile_crossed_twice_keeps_its_latest_direction() -> void:
	var t: BloodTrail = _trail()
	_drag(t, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i])
	_drag(t, [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)] as Array[Vector2i])
	assert_eq(t.direction_at(Vector2i(1, 0)), 2, "crossed again heading south: south")
	assert_eq(t.direction_at(Vector2i(0, 0)), 0, "the rest unchanged")
	assert_eq(t.direction_at(Vector2i(1, -1)), 2, "the second grab tile")


func test_a_roof_fall_erases_only_its_tiles() -> void:
	var t: BloodTrail = _trail()
	var path: Array[Vector2i] = []
	for x: int in 10:
		path.append(Vector2i(x, 0))
	_drag(t, path)
	t.erase([Vector2i(3, 0), Vector2i(4, 0), Vector2i(4, 1)] as Array[Vector2i])
	assert_eq(t.tiles.size(), 8, "two of its tiles gone")
	assert_false(t.tiles.has(Vector2i(3, 0)))
	assert_true(t.tiles.has(Vector2i(2, 0)) and t.tiles.has(Vector2i(5, 0)), "its neighbours kept")
	assert_eq(_wiped, [Vector2i(3, 0), Vector2i(4, 0), Vector2i(4, 1)] as Array[Vector2i], "every fallen tile wiped")
	assert_eq(_smeared.size(), 8)


func test_it_follows_the_drag_signal() -> void:
	var t: BloodTrail = _trail()
	var st: FakeStythe = FakeStythe.new()
	st.drag_tile_crossed.connect(t._on_crossed)
	st.drag_tile_crossed.emit(Vector2i(7, 7), -1)
	st.drag_tile_crossed.emit(Vector2i(7, 8), 2)
	assert_eq(t.direction_at(Vector2i(7, 7)), 2)
	assert_eq(t.direction_at(Vector2i(7, 8)), 2)


func test_a_pull_of_more_than_a_tile_leaves_no_gap() -> void:
	var t: BloodTrail = _trail()
	t._on_crossed(Vector2i(37, 2), -1)
	t._on_crossed(Vector2i(39, 2), 0)
	t._on_crossed(Vector2i(43, 6), 1)
	for x: int in range(37, 40):
		assert_eq(t.direction_at(Vector2i(x, 2)), 0, "the grab pulled her across %d" % x)
	for i: int in range(1, 5):
		assert_eq(t.direction_at(Vector2i(39 + i, 2 + i)), 1, "the diagonal filled")
