extends GutTest
## GEN-13: the log's API. Payloads encode canonically; a key holds its latest write; records replay
## in the design's order (falls, doors and gates, traps, items, chalk and blood, bodies, fixtures)
## through each owner's handler, advanced first, one left with nothing dropped; a record with no
## handler is reported; run sections hold keyed payloads. The advance functions: a lamp's oil at
## its wick and ring's drink, Dry at empty; candles and flares burn down and out.

var _run: RunState = null


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	_run = RunState.create(5, ServerConfig.Mode.FRIENDS, false)
	_run.diff_log = DiffLog.new()
	_run.diff_log.bind(_run)


func after_each() -> void:
	WorldCoords.ring_override = -1


func test_payloads_encode_canonically() -> void:
	var a: Dictionary = {"b": 1, "a": {"z": 2.5, "y": [1, {"q": true, "p": "x"}]}}
	var b: Dictionary = {"a": {"y": [1, {"p": "x", "q": true}], "z": 2.5}, "b": 1}
	assert_eq(DiffLog.encode(a), DiffLog.encode(b), "insertion order never changes the bytes")
	var canon: Dictionary = DiffLog.canonical(a)
	assert_eq(DiffLog.decode(DiffLog.encode(a)), canon, "and decode back")
	assert_eq(DiffLog.decode(PackedByteArray()), {})


func test_a_key_holds_its_latest_write() -> void:
	var d: DiffLog = _run.diff_log
	_run.tick = 10
	d.record(Vector2i(3, -2), DiffLog.Kind.TRAP, "trap:4", {"sprung": false})
	_run.tick = 14
	d.record(Vector2i(3, -2), DiffLog.Kind.TRAP, "trap:4", {"sprung": true})
	assert_eq(d.store.record_count(), 1, "state, not history")
	assert_eq(d.payload_of(Vector2i(3, -2), DiffLog.Kind.TRAP, "trap:4"), {"sprung": true})
	assert_eq(d.tick_of(Vector2i(3, -2), DiffLog.Kind.TRAP, "trap:4"), 14)
	assert_eq(d.tick_of(Vector2i(3, -2), DiffLog.Kind.TRAP, "trap:5"), -1)
	d.taken(Vector2i(3, -2), "p00ab")
	assert_eq(str(d.payload_of(Vector2i(3, -2), DiffLog.Kind.ITEM, "p00ab")["where"]), DiffLog.TAKEN)


func test_replay_runs_in_the_design_order() -> void:
	var d: DiffLog = _run.diff_log
	var seen: Array[String] = []
	for k: int in DiffLog.Kind.values():
		if k == DiffLog.Kind.BLOOD:
			continue
		var kind_name: String = str(DiffLog.Kind.find_key(k))
		d.register(k, func(_r: RunState, _c: Vector2i, key: String, _p: Dictionary, _t: int) -> void:
			seen.append("%s %s" % [kind_name, key]))
	d.register(DiffLog.Kind.BLOOD, func(_r: RunState, _c: Vector2i, key: String, p: Dictionary, _t: int) -> void:
		var smears: Array = Variants.array(p["smears"])
		var first: Dictionary = smears[0]
		seen.append("BLOOD %s %d %s %d" % [key, smears.size(), first["tile"], int(Variants.number(first["direction"]))]))
	var cell: Vector2i = Vector2i(1, 1)
	var kinds: Array = DiffLog.Kind.values()
	kinds.reverse()
	for raw: Variant in kinds:
		var k: int = int(Variants.number(raw))
		if k != DiffLog.Kind.BLOOD:
			d.record(cell, k, "b", {})
			d.record(cell, k, "a", {})
	d.mark_blood(Vector2i(26, 21), 5)
	d.mark_blood(Vector2i(25, 21), 3)
	d.replay(_run, cell)
	assert_eq(seen, ["FALL a", "FALL b", "BARRIER a", "BARRIER b", "TRAP a", "TRAP b", "ITEM a", "ITEM b",
		"CHALK a", "CHALK b", "BLOOD blood 2 (25, 21) 3", "BODY a", "BODY b", "LINE a", "LINE b", "FIXTURE a", "FIXTURE b",
		"HOARD a", "HOARD b", "LAIR a", "LAIR b"] as Array[String])
	assert_eq(d.replays.size(), 1)


func test_prefixes_share_a_kind_and_a_missing_handler_is_reported() -> void:
	var d: DiffLog = _run.diff_log
	var got: Array[String] = []
	d.register(DiffLog.Kind.BARRIER, func(_r: RunState, _c: Vector2i, key: String, _p: Dictionary, _t: int) -> void:
		got.append("door " + key), Callable(), Callable(), "door:")
	d.register(DiffLog.Kind.BARRIER, func(_r: RunState, _c: Vector2i, key: String, _p: Dictionary, _t: int) -> void:
		got.append("gate " + key), Callable(), Callable(), "gate:")
	d.record(Vector2i.ZERO, DiffLog.Kind.BARRIER, "door:1", {})
	d.record(Vector2i.ZERO, DiffLog.Kind.BARRIER, "gate:west", {})
	d.record(Vector2i.ZERO, DiffLog.Kind.LINE, "phone:3", {"route": [1, 2]})
	d.replay(_run, Vector2i.ZERO)
	assert_eq(got, ["door door:1", "gate gate:west"] as Array[String])
	assert_push_error("no replay handler for kind LINE", "loudly, in a debug build")
	assert_eq(d.unhandled.size(), 1, "a kind with no handler is reported")
	assert_eq(int(Variants.number(d.unhandled[0]["kind"])), DiffLog.Kind.LINE)


func test_advance_first_and_nothing_left_drops_the_record() -> void:
	var d: DiffLog = _run.diff_log
	var got: Array[Dictionary] = []
	d.register(DiffLog.Kind.FIXTURE, func(_r: RunState, _c: Vector2i, _k: String, p: Dictionary, _t: int) -> void: got.append(p),
		func(p: Dictionary, from_tick: int, to_tick: int) -> Dictionary:
			var left: int = int(Variants.number(p["left"])) - (to_tick - from_tick)
			return {"left": left} if left > 0 else {})
	_run.tick = 100
	d.record(Vector2i.ZERO, DiffLog.Kind.FIXTURE, "a", {"left": 50})
	d.record(Vector2i.ZERO, DiffLog.Kind.FIXTURE, "b", {"left": 500})
	_run.tick = 200
	d.replay(_run, Vector2i.ZERO)
	assert_eq(got, [{"left": 400}] as Array[Dictionary], "advanced by the 100 ticks away")
	assert_true(d.payload_of(Vector2i.ZERO, DiffLog.Kind.FIXTURE, "a").is_empty(), "burnt out: dropped")


func test_sections_hold_run_level_payloads() -> void:
	var d: DiffLog = _run.diff_log
	var table: DiffLog.Section = d.run_section(DiffLog.MAP_TABLE)
	table.put("label:1", {"text": "old fall", "at": [10, -4]})
	table.put_raw("s:2", PackedByteArray([1, 2, 3]))
	var text: String = str(table.get_payload("label:1")["text"])
	assert_eq(text, "old fall")
	assert_eq(table.get_raw("s:2"), PackedByteArray([1, 2, 3]))
	assert_eq(table.keys(), PackedStringArray(["label:1", "s:2"]))
	assert_gt(table.bytes(), 0)
	assert_eq(int(Variants.number(d.sizes()["map_table"])), table.bytes())
	assert_eq(int(Variants.number(d.sizes()["pocket_books"])), 0)
	assert_true(table.erase("s:2"))
	assert_true(d.run_section(DiffLog.POCKET_BOOKS).get_payload("x").is_empty())


func test_a_lamp_left_burning_loses_its_oil() -> void:
	WorldCoords.ring_override = 3
	var lamps: LampSystem = LampSystem.new()
	var per_tick: float = 1.0 / (Tuning.f(&"lamp.fill_minutes") * 60.0 * Tuning.f(&"net.tick_hz"))
	var drink: float = Tuning.by_ring(&"lamp.seam_drink_by_ring", 3)
	var lit: Dictionary = {"lit": true, "oil": 0.9, "wick": LampRules.WICK_DOWN, "shutter": false}
	var after: Dictionary = lamps.advance_lying(lit.duplicate(), Vector2(5.5, 5.5), 0, 1000)
	assert_almost_eq(float(Variants.number(after["oil"])), 0.9 - per_tick * Tuning.f(&"lamp.burn_factor_wick_down") * drink * 1000.0, 1e-9,
		"its wick's rate times its ring's drink")
	var shut: Dictionary = lamps.advance_lying({"lit": true, "oil": 0.9, "wick": 1, "shutter": true}, Vector2(5.5, 5.5), 0, 1000)
	assert_almost_eq(float(Variants.number(shut["oil"])), 0.9 - per_tick * Tuning.f(&"lamp.burn_factor_closed") * drink * 1000.0, 1e-9,
		"a shuttered lamp at the closed rate")
	var dry: Dictionary = lamps.advance_lying({"lit": true, "oil": 0.01, "wick": 1, "shutter": false}, Vector2(5.5, 5.5), 0, 100000)
	assert_eq(float(Variants.number(dry["oil"])), 0.0)
	assert_false(Variants.flag(dry["lit"]))
	assert_eq(int(Variants.number(dry["lamp_phase"])), LampRules.Phase.DRY, "dry when it runs out")
	var out_lamp: Dictionary = lamps.advance_lying({"lit": false, "oil": 0.5}, Vector2(5.5, 5.5), 0, 1000)
	assert_eq(float(Variants.number(out_lamp["oil"])), 0.5, "an Out lamp burns nothing")
	var hoarded: Dictionary = lamps.advance_lying({"lit": false, "oil": 0.5, "lamp_phase": LampRules.Phase.HOARDED}, Vector2(5.5, 5.5), 0, 1000)
	assert_eq(float(Variants.number(hoarded["oil"])), 0.5)


func test_candles_and_flares_burn_down_then_out() -> void:
	var candles: Candles = Candles.new()
	var full: int = candles.full_burn_ticks()
	var spent: bool = candles.advance_lying({"lit": true, "burn_ticks": full}, Vector2.ZERO, 0, full) == null
	assert_true(spent, "spent after its full burn")
	var part: Dictionary = candles.advance_lying({"lit": true, "burn_ticks": full}, Vector2.ZERO, 0, 100)
	assert_eq(int(Variants.number(part["burn_ticks"])), full - 100)
	var found: Dictionary = candles.advance_lying({"lit": true}, Vector2.ZERO, 0, 100)
	assert_eq(int(Variants.number(found["burn_ticks"])), full - 100, "a lit one with no time on it had its full burn")
	var unlit: Dictionary = candles.advance_lying({"lit": false, "burn_ticks": 40}, Vector2.ZERO, 0, 100)
	assert_eq(unlit, {"lit": false, "burn_ticks": 40}, "unlit waits")
	var flares: Flares = Flares.new()
	var out_flare: bool = flares.advance_lying({"lit": true, "burn_ticks": 10}, Vector2.ZERO, 0, 10) == null
	assert_true(out_flare, "a flare burns out")
	var bare: Variant = flares.advance_lying({}, Vector2.ZERO, 0, 10)
	assert_true(bare is Dictionary and Variants.dict(bare).is_empty(), "an unlit one, with no state at all, stays")
