extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-12 (Gameplay §6.6, §12.5; GDD §15.4): a phone's road home, through GEN-05's derived cells
## from a phone cells out to a gate of base camp, is computed once, as the phone first
## generates: met again (its cell back from eviction) it is as it was. A fall on an alternate it
## crosses cuts the line for the run; a fall anywhere else does not. A fall that came before the
## phone generated, on its road, cuts it at once.

const G = preload("res://tests/scenario/hazards/test_collapse_generated_arming.gd")

## Road crossings of grid cells south of base camp, whose roads home run north through the cells'
## north columns (where the pack's alternate lies).
const CANDIDATES: Array[Vector2i] = [Vector2i(25, 75), Vector2i(45, 75), Vector2i(25, 55), Vector2i(65, 65), Vector2i(-35, 75)]

var cuts: Array[int] = []


func before_all() -> void:
	assert_true(Tuning.load_server())


func _generated(run_seed: int) -> Scenario:
	var s: Scenario = make({"seed": run_seed, "generated": {"pack": G.pack()}})
	cuts.clear()
	s.run.phones.line_cut.connect(func(n: int) -> void: cuts.append(n))
	return s


## The first candidate whose road crosses an alternate: [tile, route].
static func _crossing_phone(s: Scenario) -> Array:
	for t: Vector2i in CANDIDATES:
		var r: Dictionary = LineRouter.route(s.run.placed.layouts, t)
		if Variants.flag(r["found"]) and not Variants.array(r["crossings"]).is_empty():
			return [t, r]
	return []


func test_found_once_and_cut_only_by_its_own_falls() -> void:
	var s: Scenario = _generated(4401)
	var picked: Array = _crossing_phone(s)
	assert_false(picked.is_empty(), "a phone whose road crosses an alternate")
	var phone_tile: Vector2i = picked[0]
	var r: Dictionary = picked[1]
	assert_true(Variants.flag(r["found"]), "a road home")
	var cells: Array = r["cells"]
	var last: Vector2i = cells[cells.size() - 1]
	assert_eq(absi(last.x) + absi(last.y), 1, "to a gate of base camp")
	assert_gte(int(Variants.number(r["tiles"])), 40, "%s tiles from cells out" % r["tiles"])
	var p: PitPhone = s.run.phones.meet(s.run, "p1", phone_tile)
	assert_false(s.run.phones.live(s.run, p), "dead until its road is stored")
	assert_eq(s.run.phones.pending_routes(), 1, "its road found on a later tick")
	s.step()
	assert_eq(s.run.phones.pending_routes(), 0)
	assert_true(p.routed)
	assert_eq(p.crossings, Variants.array(r["crossings"]), "the line kept is the road found")
	assert_false(p.crossings.is_empty(), "it crosses alternates (the grid's north-column falls)")
	# Met again, as its cell comes back: never routed again.
	s.run.phones.meet(s.run, "p1", phone_tile)
	var generated: Array = s.run.phones.history.filter(func(h: Dictionary) -> bool: return str(h["what"]) == "generated")
	assert_eq(generated.size(), 1, "computed once, at first generation")
	var payload: Dictionary = s.run.diff_log.payload_of(p.cell, DiffLog.Kind.LINE, PhoneLines.KEY_PREFIX + "p1")
	assert_eq(int(Variants.number(payload.get("number", -1))), p.number, "kept in GEN-13's log")
	# A fall elsewhere: nothing; one it crosses: cut for the run.
	var crossing: Array = p.crossings[0]
	var at: Vector2i = crossing[0]
	var alt: int = int(Variants.number(crossing[1]))
	s.run.phones.on_tiles_fallen(s.run, at + Vector2i(0, 9), [] as Array[Vector2i], alt)
	s.run.phones.on_tiles_fallen(s.run, at, [] as Array[Vector2i], alt + 7)
	assert_false(p.cut, "a fall off its road leaves it")
	assert_eq(cuts.size(), 0)
	s.run.phones.on_tiles_fallen(s.run, at, [] as Array[Vector2i], alt)
	assert_true(p.cut, "a fall across it cuts it")
	assert_eq(cuts, [p.number], "and the board is told")
	assert_true(Variants.flag(s.run.diff_log.payload_of(p.cell, DiffLog.Kind.LINE, PhoneLines.KEY_PREFIX + "p1").get("cut", false)), "kept")
	s.run.power.switch_closed = true
	assert_false(s.run.phones.live(s.run, p), "dead for the run")


func test_a_fall_before_the_phone_cuts_it_at_birth() -> void:
	var s: Scenario = _generated(4402)
	var picked: Array = _crossing_phone(s)
	assert_false(picked.is_empty())
	var phone_tile: Vector2i = picked[0]
	var r: Dictionary = picked[1]
	var crossing: Array = Variants.array(r["crossings"])[0]
	var at: Vector2i = crossing[0]
	s.run.diff_log.record(at, DiffLog.Kind.FALL, CollapsePoints.KEY_PREFIX + str(int(Variants.number(crossing[1]))), {"fallen_at": 1, "cuts": []})
	var p: PitPhone = s.run.phones.meet(s.run, "p1", phone_tile)
	s.step()
	assert_true(p.routed, "the road is the seed's")
	assert_true(p.cut, "and a fall already on it cuts it")
