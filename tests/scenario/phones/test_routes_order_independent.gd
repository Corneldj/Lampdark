extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-12 (Gameplay §6.6; GDD §15.4, §15.9): the same play history in two generation orders gives
## the same lines. One mine generates base camp's window first, the other a far window first; the
## same phones get the same roads home and crossings, and the same fall, landing before a phone
## generated in one and after it in the other, cuts the same line in both.

const G = preload("res://tests/scenario/hazards/test_collapse_generated_arming.gd")
const R = preload("res://tests/unit/phones/test_line_routes.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_two_orders_one_set_of_lines() -> void:
	var near: Scenario = make({"seed": 4901, "generated": {"pack": G.pack()}})
	var far: Scenario = make({"seed": 4901, "generated": {"pack": G.pack(), "centres": [Vector2i(4, 3)]}})
	assert_true(far.run_until(func(sc: Scenario) -> bool: return sc.mine.native.loaded_cells().size() >= 40, 600), "the far window first")
	var lines: Array = []
	for s: Scenario in [near, far]:
		var got: Array = []
		for t: Vector2i in R.CANDIDATES:
			got.append(LineRouter.route(s.run.placed.layouts, t))
		lines.append(got)
	for i: int in R.CANDIDATES.size():
		var a: Dictionary = lines[0][i]
		var b: Dictionary = lines[1][i]
		assert_eq(var_to_str(b), var_to_str(a), "phone %s: the same road home in both orders" % R.CANDIDATES[i])
	# The same fall: before the phone generates in one mine, after it in the other.
	var picked: Array = R._crossing_phone(near)
	assert_false(picked.is_empty())
	var tile: Vector2i = picked[0]
	var crossing: Array = Variants.array(Variants.dict(picked[1])["crossings"])[0]
	var cell: Vector2i = crossing[0]
	var alt: int = int(Variants.number(crossing[1]))
	near.run.diff_log.record(cell, DiffLog.Kind.FALL, CollapsePoints.KEY_PREFIX + str(alt), {"fallen_at": near.run.tick, "cuts": []})
	var first: PitPhone = near.run.phones.meet(near.run, "p", tile)
	var second: PitPhone = far.run.phones.meet(far.run, "p", tile)
	near.step()
	far.step()
	far.run.phones.on_tiles_fallen(far.run, cell, [] as Array[Vector2i], alt)
	assert_eq(var_to_str(second.crossings), var_to_str(first.crossings), "the same crossings")
	assert_true(first.cut and second.cut, "and the same line cut, whichever came first")
