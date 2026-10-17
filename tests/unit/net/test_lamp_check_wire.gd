extends GutTest
## RSC-06: LAMP_CHECK's messages round-trip, and a malformed one reads as nothing. The opening holds
## lamp numbers, the remark's cause, the card's text, the wipe flag, the own outcome and the budget:
## nothing a record field outside them (a Steam name, a lobby code) could ride in.

const HOOKS: Array = [{"lamp": 108, "hangs": true}, {"lamp": 114, "hangs": false}]
const CARD: String = "Morrow Main, first shift. Up 1 of 2. Left Below: Ada Rowe, Lamp 114. Deepest: the Third Level. Below 1 h 42 min."


func test_the_opening_round_trips() -> void:
	var bytes: PackedByteArray = LampCheckWire.open(HOOKS, "drag", CARD, false, "left_below", "a-run-uuid", {"public_s": 120.0})
	var d: Dictionary = LampCheckWire.read(bytes)
	assert_eq(str(d["kind"]), LampCheckWire.OPEN)
	assert_eq(str(d["run_uuid"]), "a-run-uuid")
	assert_eq(Variants.array(d["hooks"]), HOOKS)
	assert_eq(str(d["remark"]), "drag")
	assert_eq(str(d["card"]), CARD)
	assert_false(Variants.flag(d["wipe"]))
	assert_eq(str(d["own"]), "left_below")
	assert_eq(Variants.number(d["public_s"]), 120.0)
	var friends: Dictionary = LampCheckWire.read(LampCheckWire.open([], "", CARD, true, "", "u", {}))
	assert_eq(Variants.number(friends["public_s"]), 0.0, "friends: when everyone is ready")
	assert_eq(str(friends["own"]), "", "no miner: no outcome")
	assert_true(Variants.flag(friends["wipe"]))


func test_end_and_ready() -> void:
	assert_eq(LampCheckWire.read(LampCheckWire.end("time")), {"kind": LampCheckWire.END, "why": "time"})
	assert_eq(LampCheckWire.read(LampCheckWire.end("ready")), {"kind": LampCheckWire.END, "why": "ready"})
	assert_eq(LampCheckWire.read(LampCheckWire.ready()), {"kind": LampCheckWire.READY})


func test_malformed_reads_as_nothing() -> void:
	var good: PackedByteArray = LampCheckWire.open(HOOKS, "drag", CARD, false, "escaped", "u", {})
	for n: int in good.size():
		assert_eq(LampCheckWire.read(good.slice(0, n)), {}, "cut at %d" % n)
	var longer: PackedByteArray = good.duplicate()
	longer.append(0)
	assert_eq(LampCheckWire.read(longer), {}, "a byte too many")
	assert_eq(LampCheckWire.read(PackedByteArray([9])), {}, "an unknown kind")
	assert_eq(LampCheckWire.read(PackedByteArray([2, 0])), {}, "a Ready with a body")
	assert_eq(LampCheckWire.read(PackedByteArray([1, 7])), {}, "an unknown end")


func test_the_opening_holds_no_more_than_its_fields() -> void:
	var record: Dictionary = {"run_uuid": "u", "crew_size": 2, "up_count": 1, "wipe": false, "deepest_ring": 3, "time_below_s": 6140.0,
		"miners": [{"miner_id": 1, "name": "Harry", "lamp_number": 108, "outcome": "escaped", "dead": false, "steam_name": "xX_Collier_Xx"},
			{"miner_id": 2, "name": "Ada Rowe", "lamp_number": 114, "outcome": "left_below", "dead": false, "lobby_code": "QX7-44K"}],
		"steam_name": "xX_Collier_Xx", "lobby_code": "QX7-44K"}
	var f: Dictionary = LampCheckFacts.build(record, FallCause.Cause.DRAG)
	var bytes: PackedByteArray = LampCheckWire.open(Variants.array(f["hooks"]), str(f["remark"]), str(f["card"]), false, "escaped", "u", {})
	var text: String = bytes.get_string_from_ascii() + str(f["card"])
	for word: String in ["xX_Collier_Xx", "QX7-44K"]:
		assert_false(text.contains(word), "never %s on the card or the wire" % word)
		assert_false(bytes.hex_encode().contains(word.to_utf8_buffer().hex_encode()))
