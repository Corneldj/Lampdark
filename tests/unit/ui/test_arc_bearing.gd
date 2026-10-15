extends GutTest
## UI-03: a positional caption's arc is a noise.caption_arc_deg segment of the view's inscribed
## ellipse centred on the apparent position's bearing, the same at 2 tiles and at 20; a diffuse tell
## has none.


func before_all() -> void:
	assert_true(Tuning.load_client())


func _record(at: Vector2, flags: int = 0) -> AudioRecord:
	var r: AudioRecord = AudioRecord.new()
	r.type = NoiseTypes.Type.HAMMER
	r.apparent = at
	r.duration_s = 0.5
	r.flags = flags
	return r


func test_bearing_and_size_ignore_distance() -> void:
	var listener: Vector2 = Vector2(50, 50)
	var bearings: Array[float] = []
	for d: float in [2.0, 20.0]:
		var sys: CaptionSystem = CaptionSystem.new()
		var at: Vector2 = listener + Vector2(1, 1).normalized() * d
		sys.on_played(_record(at), at - listener, 0.0)
		var line: Dictionary = sys.visible_lines()[0]
		bearings.append(float(Variants.number(line["bearing"])))
		assert_false(str(line["text"]).contains(str(int(d))), "no distance in the text")
	assert_almost_eq(bearings[0], 45.0, 0.01, "south-east, clockwise from east")
	assert_almost_eq(bearings[0], bearings[1], 0.0001, "the same bearing at 2 and 20 tiles")
	var ellipse: Vector2 = Vector2(900, 480)
	var near: PackedVector2Array = CaptionArc.segment(bearings[0], ellipse, CaptionArc.span())
	var far: PackedVector2Array = CaptionArc.segment(bearings[1], ellipse, CaptionArc.span())
	assert_eq(near, far, "one size at any distance")
	assert_almost_eq(CaptionArc.span(), 45.0, 0.0001)
	var first: float = rad_to_deg(near[0].angle())
	var last: float = rad_to_deg(near[near.size() - 1].angle())
	assert_almost_eq(first, 45.0 - 22.5, 0.01)
	assert_almost_eq(last, 45.0 + 22.5, 0.01)
	for p: Vector2 in near:
		assert_almost_eq(pow(p.x / ellipse.x, 2.0) + pow(p.y / ellipse.y, 2.0), 1.0, 1e-4, "on the inscribed ellipse")


func test_a_diffuse_tell_has_no_arc() -> void:
	var sys: CaptionSystem = CaptionSystem.new()
	sys.on_played(_record(Vector2(3, 0), AudioRecord.DIFFUSE), null, 0.0)
	var b: Variant = sys.visible_lines()[0]["bearing"]
	assert_true(b == null, "no bearing")


func test_mono_keeps_arcs_without_text() -> void:
	var sys: CaptionSystem = CaptionSystem.new()
	sys.captions_on = false
	sys.arcs_only = true
	sys.on_played(_record(Vector2(3, 0)), Vector2(3, 0), 0.0)
	sys.on_played(_record(Vector2(3, 0), AudioRecord.DIFFUSE), null, 0.0)
	var shown: Array[Dictionary] = sys.visible_lines()
	assert_eq(shown.size(), 1, "the positional sound keeps its arc; the diffuse tell has none to keep")
	assert_eq(str(shown[0]["text"]), "")
	sys.arcs_only = false
	assert_eq(sys.visible_lines().size(), 0, "captions off, mono off: nothing")
