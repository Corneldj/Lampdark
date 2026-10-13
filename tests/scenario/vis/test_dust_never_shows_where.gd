extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-09: the Moth's dust never shows where it is. The flag is one bit for the whole view, so the
## client draws dust on exactly the lit tiles it draws, whatever the Moth's position, and never on
## an unlit or unseen tile.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_dust_covers_exactly_the_drawn_lit_tiles() -> void:
	var view: ReceivedView = ReceivedView.new()
	for x: int in range(0, 12):
		var light: int = 200 if x < 6 else (20 if x < 9 else 0)
		view.tiles[Vector2i(x, 3)] = PackedByteArray([light, 1, 0])
		view.geometry[Vector2i(x, 3)] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])
	view.own["position"] = Vector2(2.5, 3.5)
	var drawn: DrawnSet = DrawnSet.new()
	drawn.build(view, {"position": Vector2(2.5, 3.5), "facing": 0, "lamp": {}}, 0, -1)
	var dust: DustHaze = DustHaze.new()
	autofree(dust)
	dust.set_frame(drawn, view, Vector2.ZERO, 64.0, 0.0)
	assert_eq(dust.tiles().size(), 0, "no flag, no dust")
	view.dust = true
	dust.set_frame(drawn, view, Vector2.ZERO, 64.0, 0.0)
	var want: Array[Vector2i] = []
	for raw: Variant in drawn.tiles.keys():
		var t: Vector2i = raw
		var rec: PackedByteArray = view.tiles[t]
		if rec[0] >= roundi(Tuning.f(&"light.dust_min_light") * 255.0):
			want.append(t)
	var got: Array[Vector2i] = dust.tiles()
	got.sort()
	want.sort()
	assert_eq(got, want, "every drawn lit tile, no other")
	for t: Vector2i in got:
		assert_lt(t.x, 6, "never the dim (under 0.12) or unlit tiles")
