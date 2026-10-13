extends GutTest
## VIS-06: each edge-glow bucket shows at the border its bearing meets, coloured by class; an off-screen
## seen tile shows where its bearing meets the border; a mark carries direction and colour only.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_buckets_meet_the_right_border() -> void:
	var view: Rect2 = Rect2(Vector2.ZERO, ViewGeometry.view_size())
	var miner: Vector2 = view.get_center()
	var n: int = roundi(Tuning.f(&"vision.cone_deg") / Tuning.f(&"vision.edge_glow_bucket_deg"))
	var colours: PackedByteArray = PackedByteArray()
	colours.resize(32)
	var middle: int = n / 2
	colours[middle] = 3
	for facing_deg: float in [0.0, 90.0, 180.0, 270.0]:
		var marks: Array[Dictionary] = EdgeGlow.layout(view, miner, Intents.facing_u16(facing_deg), 1 << middle, colours, {})
		assert_eq(marks.size(), 1)
		var want_side: int = {0.0: 1, 90.0: 2, 180.0: 3, 270.0: 0}[facing_deg]
		assert_eq(int(Variants.number(marks[0]["side"])), want_side, "facing %.0f: the %s border" % [facing_deg, ["top", "right", "bottom", "left"][want_side]])
		assert_eq(int(Variants.number(marks[0]["colour"])), 3, "base camp white")
		assert_eq(marks[0].keys(), ["at", "side", "colour"], "direction and colour only: no distance, no brightness")


func test_off_screen_tiles() -> void:
	var view: Rect2 = Rect2(Vector2(0, 0), ViewGeometry.view_size())
	var miner: Vector2 = Vector2(15, 8.4)
	var marks: Array[Dictionary] = EdgeGlow.layout(view, miner, 0, 0, PackedByteArray(), {Vector2i(40, 8): 1, Vector2i(10, 4): 1})
	assert_eq(marks.size(), 1, "only the tile beyond the view")
	assert_eq(int(Variants.number(marks[0]["side"])), 1, "on the right border")
	var at: Vector2 = marks[0]["at"]
	assert_almost_eq(at.x, view.end.x, 1e-4)
