extends GutTest
## RSC-06 (Gameplay §11.9, §13.2): every row of the outcome table, from the record to the hook and the
## roster. Escaped (conscious or carried unconscious): the check hangs, the number is read, the miner
## returns. Dead, brought home: the check hangs and is read, the miner leaves for good. Left Below
## (conscious, Caught, kept or dead): an empty hook and silence, the miner leaves. A wipe: no check
## hangs, silence at every hook, every miner leaves. Each counts the run toward the New Brigade.

## row, record miner (outcome, dead), wipe, hangs, the own outcome sent, and the roster's result
## ("returns", or the reason the miner left).
const ROWS: Array = [
	["escaped, conscious", "escaped", false, false, true, "escaped", "returns"],
	["escaped, carried unconscious", "escaped", false, false, true, "escaped", "returns"],
	["dead, brought home", "escaped", true, false, true, "dead", "dead"],
	["left below, conscious", "left_below", false, false, false, "left_below", "left_below"],
	["left below, dead", "left_below", true, false, false, "left_below", "left_below"],
	["a wipe", "left_below", false, true, false, "left_below", "wipe"],
]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _len(line_id: String, _form: String) -> float:
	return 0.4 if line_id.begins_with("digit_") else 2.0


func test_every_row_maps_to_its_hook_and_roster() -> void:
	for row: Array in ROWS:
		var label: String = row[0]
		var outcome: String = row[1]
		var dead: bool = row[2]
		var wipe: bool = row[3]
		var hangs: bool = row[4]
		var own_expected: String = row[5]
		var result: String = row[6]
		var m: Dictionary = {"miner_id": 7, "name": "Ada Rowe", "lamp_number": 114, "outcome": outcome, "dead": dead, "solo_rules": false}
		var record: Dictionary = {"run_uuid": "u-%d" % ROWS.find(row), "crew_size": 1, "up_count": 1 if outcome == "escaped" else 0,
			"miners": [m], "wipe": wipe, "deepest_ring": 1, "time_below_s": 600.0}
		var f: Dictionary = LampCheckFacts.build(record, FallCause.Cause.DRAG)
		var hook: Dictionary = Variants.dict(Variants.array(f["hooks"])[0])
		assert_eq(Variants.flag(hook["hangs"]), hangs, "%s: the check hangs or not" % label)
		var q: LampmanSequence = LampmanSequence.build(Variants.array(f["hooks"]), str(f["remark"]), _len)
		assert_eq(q.digits_read(0), "114" if hangs else "", "%s: the number read, or silence" % label)
		var own: String = LampCheckFacts.outcome_name(m)
		assert_eq(own, own_expected, "%s: the own outcome" % label)
		var p: Profile = Profile.create(4242, 99)
		var sent: RosterMiner = p.state().roster[0]
		assert_true(p.send_below(str(record["run_uuid"]), sent.id, 1))
		assert_true(LampCheckRoster.apply(p, str(record["run_uuid"]), own, Variants.flag(f["wipe"]), 2), "%s: applied" % label)
		var s: Profile.State = p.state()
		assert_eq(s.new_brigade_runs, 1, "%s: the run counts toward the New Brigade" % label)
		if result == "returns":
			assert_true(s.miner(sent.id) != null and s.miner(sent.id).available(), "%s: back on the roster" % label)
		else:
			assert_true(s.miner(sent.id) == null, "%s: gone from the roster" % label)
			assert_eq(s.gone[0].left if not s.gone.is_empty() else "", result, "%s: left for good" % label)
