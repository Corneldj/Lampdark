extends GutTest
## RSC-06 (Gameplay §11.9, GDD §14.3): the Lamp Check card's text. §3.9's ending reads exactly as the
## design prints it; a revolver death brought home adds its line and counts in Up; a wipe of four
## reads 'Up none of 4.'; Below is 'N h M min', or 'M min' under the hour; the Level is named, never
## the ring; the card names nobody by anything but period name and lamp number.


func _record(miners: Array, up: int, crew: int, wipe: bool, ring: int, below_s: float) -> Dictionary:
	return {"run_uuid": "u", "crew_size": crew, "up_count": up, "miners": miners, "wipe": wipe, "deepest_ring": ring,
		"time_below_s": below_s, "ended_tick": 0, "lamp_check_wait_s": 0.0}


func _m(id: int, name: String, lamp: int, outcome: String, dead: bool = false) -> Dictionary:
	return {"miner_id": id, "name": name, "lamp_number": lamp, "outcome": outcome, "dead": dead, "solo_rules": false}


## §3.9: Harry, Ellis, Wilf and Nell up; Ada Rowe, Lamp 114, kept below; the Third Level; 1:42:20.
func _first_shift() -> Dictionary:
	return _record([_m(11, "Harry", 108, "escaped"), _m(12, "Ellis", 131, "escaped"), _m(13, "Wilfred Dodd", 207, "escaped"),
		_m(14, "Nell", 162, "escaped"), _m(15, "Ada Rowe", 114, "left_below")], 4, 5, false, 3, 6140.0)


func test_the_first_shift_reads_as_the_design_prints_it() -> void:
	var f: Dictionary = LampCheckFacts.build(_first_shift(), FallCause.Cause.DRAG)
	assert_eq(str(f["card"]), "Morrow Main, first shift. Up 4 of 5. Left Below: Ada Rowe, Lamp 114. Deepest: the Third Level. Below 1 h 42 min.")
	assert_eq(str(f["remark"]), "drag", "the remark: what felled someone last")
	var lamps: Array = []
	for raw: Variant in Variants.array(f["hooks"]):
		var h: Dictionary = raw
		lamps.append([int(Variants.number(h["lamp"])), Variants.flag(h["hangs"])])
	assert_eq(lamps, [[108, true], [114, false], [131, true], [162, true], [207, true]], "hooks by lamp number; Ada's is empty")


func test_a_body_brought_home_adds_its_line_and_counts_up() -> void:
	var rec: Dictionary = _record([_m(11, "Harry", 108, "escaped"), _m(13, "Wilfred Dodd", 207, "escaped", true),
		_m(15, "Ada Rowe", 114, "left_below")], 2, 3, false, 1, 2700.0)
	var f: Dictionary = LampCheckFacts.build(rec, FallCause.Cause.SHOT_DEAD)
	var lines: PackedStringArray = str(f["card"]).split("\n")
	assert_eq(lines[0], "Morrow Main, first shift. Up 2 of 3. Left Below: Ada Rowe, Lamp 114. Deepest: the First Level. Below 45 min.")
	assert_eq(lines.size(), 2)
	assert_eq(lines[1], "Dead: Wilfred Dodd, Lamp 207, brought home.")
	var hung: Array = []
	for raw: Variant in Variants.array(f["hooks"]):
		if Variants.flag(Variants.dict(raw)["hangs"]):
			hung.append(int(Variants.number(Variants.dict(raw)["lamp"])))
	assert_eq(hung, [108, 207], "his check hangs too")
	assert_eq(LampCheckFacts.outcome_name(_m(13, "Wilfred Dodd", 207, "escaped", true)), "dead")


func test_a_wipe_of_four() -> void:
	var rec: Dictionary = _record([_m(1, "Ann", 301, "left_below"), _m(2, "Bob", 302, "left_below"), _m(3, "Cid", 303, "left_below"),
		_m(4, "", 304, "left_below")], 0, 4, true, 2, 1500.0)
	var f: Dictionary = LampCheckFacts.build(rec, -1)
	assert_string_contains(str(f["card"]), "Up none of 4.")
	assert_string_contains(str(f["card"]), "Left Below: Ann, Lamp 301; Bob, Lamp 302; Cid, Lamp 303; Lamp 304.", "listed by lamp; an unnamed miner by lamp alone")
	assert_eq(str(f["remark"]), "", "nobody's fall known: no remark")
	for raw: Variant in Variants.array(f["hooks"]):
		assert_false(Variants.flag(Variants.dict(raw)["hangs"]), "no check hangs")
	assert_true(Variants.flag(f["wipe"]))


func test_below_and_deepest() -> void:
	assert_eq(LampCheckCard.time_below(59.0), "Below 0 min.")
	assert_eq(LampCheckCard.time_below(3599.0), "Below 59 min.")
	assert_eq(LampCheckCard.time_below(3600.0), "Below 1 h 0 min.")
	assert_eq(LampCheckCard.time_below(6140.0), "Below 1 h 42 min.")
	assert_eq(LampCheckCard.time_below(-5.0), "Below 0 min.")
	for ring: int in 5:
		var name: String = LampCheckCard.level(ring)
		assert_false(name.is_empty())
		assert_false(name.to_lower().contains("ring"), "the Level, never the ring")
	assert_eq(LampCheckCard.level(0), "the pit-bottom roads")


func test_nobody_left_below_has_no_such_line() -> void:
	var rec: Dictionary = _record([_m(1, "Ann", 301, "escaped"), _m(2, "Bob", 302, "escaped")], 2, 2, false, 0, 600.0)
	assert_eq(str(LampCheckFacts.build(rec, FallCause.Cause.ROOF_FALL)["card"]),
		"Morrow Main, first shift. Up 2 of 2. Deepest: the pit-bottom roads. Below 10 min.")
