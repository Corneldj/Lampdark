extends "res://tools/bots/soak.gd"
## LFT-14's bot harness: five bots at the map table drawing at the cap for 30 minutes (accelerated).
## Each commits a stroke of mine.sheet_stroke_max_points every 100 ms (mine.sheet_strokes_per_s),
## sends its stroke as made at mine.sheet_sketch_hz, and rubs twice a second, so the sheet reaches
## mine.sheet_max_strokes within minutes and churns there. Judged on NET-04's budget (no client's
## download, voice aside, over net.down_budget_kbps in any 1 s window), NET-12's tick
## (net.tick_budget_ms_p99), and the cap itself (reached, never passed, never a rate refusal).
## run_soak.sh sheet_cap [--minutes T]

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

var _rng: LbRng = null
var _seq: Dictionary = {}
## bot -> the cumulative bytes it received (voice aside) at each of the last tick_hz ticks.
var _history: Dictionary = {}
var _worst_window: Dictionary = {}
var _cap_reached_tick: int = -1
var _max_count: int = 0
var _ticks: int = 0


func setup(_ctx: Dictionary) -> void:
	profile = {"servers": 1, "bots": 5, "minutes": 30.0, "seed": 1414, "brains": ["idle"], "link": "", "accelerated": true,
		"capture_keep_s": 5.0}


func scenario_config(_server: int) -> Dictionary:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("#".repeat(16))
	for y: int in 6:
		rows.append("#" + ".".repeat(14) + "#")
	rows.append("#".repeat(16))
	return {"fixture": FixtureMap.from_ascii(rows), "slots": 8}


func spawn_tile(_s: Scenario, bot: int) -> Vector2i:
	return Vector2i(2 + bot * 2, 3)


## Every bot reads the table from the start; the soak draws for them each tick.
func prepare(s: Scenario) -> void:
	_rng = LbRng.from_seed(int(Variants.number(profile["seed"])))
	for h: MinerHandle in s.miners:
		s.run.closeups.open_for(s.run, h.entity_id, CloseupKind.Kind.MAP_TABLE, "soak")
		_seq[h.name] = 0
		_history[h.name] = []
		_worst_window[h.name] = 0
	s.on_tick = func(sc: Scenario) -> void: _draw(sc)


func _draw(s: Scenario) -> void:
	_ticks += 1
	var hz: int = roundi(Tuning.f(&"net.tick_hz"))
	var every: int = maxi(1, roundi(hz / float(Tuning.i(&"mine.sheet_strokes_per_s"))))
	var points: int = Tuning.i(&"mine.sheet_stroke_max_points")
	for i: int in s.miners.size():
		var h: MinerHandle = s.miners[i]
		if not h.is_connected_now():
			continue
		if s.run.closeups.kind_of(h.entity_id) != CloseupKind.Kind.MAP_TABLE:
			s.run.closeups.open_for(s.run, h.entity_id, CloseupKind.Kind.MAP_TABLE, "soak")
		var start: Vector2 = Vector2(_rng.range(-16000, 8000), _rng.range(-16000, 8000))
		var stroke: PackedVector2Array = PackedVector2Array()
		for p: int in points:
			stroke.append(start + Vector2(p * 120, (p % 2) * 40))
		if (_ticks + i) % every == 0:
			var seq: int = (int(Variants.number(_seq[h.name])) % 0xFFFF) + 1
			_seq[h.name] = seq
			h.connection.send(Lane.Id.BULK, SheetCodec.commit_stroke(seq, stroke), Protocol.Msg.SHEET)
		else:
			h.connection.sheet.sketching(floori(_ticks / float(every)), stroke.slice(0, 2 + _ticks % 10))
		if (_ticks + i * 3) % 10 == 0:
			var at: Vector2 = Vector2(_rng.range(-16000, 16000), _rng.range(-16000, 16000))
			h.connection.send(Lane.Id.BULK, SheetCodec.rub(PackedVector2Array([at, at + Vector2(24, 0), at + Vector2(48, 0)])),
				Protocol.Msg.SHEET)
		_window(h, hz)
	var count: int = s.run.sheets.table.sheet.count()
	_max_count = maxi(_max_count, count)
	if _cap_reached_tick < 0 and count >= Tuning.i(&"mine.sheet_max_strokes"):
		_cap_reached_tick = s.run.tick


## The bot's worst 1 s window of download, voice aside.
func _window(h: MinerHandle, hz: int) -> void:
	var total: int = 0
	for lane: Variant in h.connection.bytes_in.keys():
		if int(Variants.number(lane)) != Lane.Id.VOICE:
			total += int(Variants.number(h.connection.bytes_in[lane]))
	var hist: Array = _history[h.name]
	hist.append(total)
	if hist.size() > hz + 1:
		hist.pop_front()
	if hist.size() == hz + 1:
		var window: int = total - int(Variants.number(hist[0]))
		_worst_window[h.name] = maxi(int(Variants.number(_worst_window[h.name])), window)


func inspect(s: Scenario) -> Dictionary:
	var whys: Dictionary = {}
	for r: Dictionary in s.run.sheets.refused:
		whys[str(r["why"])] = int(Variants.number(whys.get(str(r["why"]), 0))) + 1
	var backlog: int = 0
	for raw: Variant in s.run.sheets.sync.clients.keys():
		var c: SheetSync.Client = s.run.sheets.sync.clients[raw]
		backlog = maxi(backlog, c.queue.size() + c.backlog.size())
	return {"worst_window_bytes": _worst_window, "cap_reached_tick": _cap_reached_tick, "max_count": _max_count,
		"final_count": s.run.sheets.table.sheet.count(), "refused_recent": whys, "max_backlog_ops": backlog,
		"sent_bytes": s.run.sheets.sync.sent_bytes, "pen_bytes": s.run.sheets.sync.pen_bytes,
		"map_table_bytes": s.run.diff_log.sizes()["map_table"]}


func verify(report: Dictionary) -> Array[String]:
	var errors: Array[String] = standard_checks(report, roundi(float(Variants.number(profile["minutes"])) * 60.0
		* Tuning.f(&"net.tick_hz")))
	var budget: int = roundi(Tuning.f(&"net.down_budget_kbps") * 1000.0 / 8.0)
	var tick_budget_us: float = Tuning.f(&"net.tick_budget_ms_p99") * 1000.0
	var cap: int = Tuning.i(&"mine.sheet_max_strokes")
	for raw: Variant in Variants.array(report.get("servers", [])):
		var server: Dictionary = Variants.dict(raw)
		var tick: Dictionary = Variants.dict(Variants.dict(server.get("stats", {})).get("tick_usec", {}))
		if float(Variants.number(tick.get("p99", 1e9))) > tick_budget_us:
			errors.append("the tick took %s us at p99, over %s us" % [tick.get("p99"), tick_budget_us])
		var g: Dictionary = Variants.dict(server.get("inspect", {}))
		var worst: Dictionary = Variants.dict(g.get("worst_window_bytes", {}))
		for bot: Variant in worst.keys():
			if int(Variants.number(worst[bot])) > budget:
				errors.append("%s received %s bytes in one second, over %d" % [bot, worst[bot], budget])
		if int(Variants.number(g.get("cap_reached_tick", -1))) < 0:
			errors.append("the sheet never reached its cap (most %s)" % g.get("max_count"))
		if int(Variants.number(g.get("max_count", 1 << 30))) > cap:
			errors.append("the sheet passed its cap: %s" % g.get("max_count"))
		if int(Variants.number(Variants.dict(g.get("refused_recent", {})).get("rate", 0))) > 0:
			errors.append("commits at the cap's rate were refused for rate")
	return errors
