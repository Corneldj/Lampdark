class_name SheetService
extends SimSystem
## LFT-14 (stage INPUTS, after UI-02's close-ups and SND-11's callouts): the server's hand on the
## map table's sheet (Gameplay §12.7, §14.3; GDD §15.11). Each client's commits (SheetCodec, bulk
## lane) are checked and applied here, journalled to the diff log, and handed to SheetSync.
##
## Only a miner at the table with its close-up open draws: conscious, standing (the board's
## operator is seated in another close-up, §4.10), the sheet not frozen. Caps, as rules (NET-13
## audits them): mine.sheet_strokes_per_s commits in any second (a label counts as a stroke; rubs
## have their own window at the same rate, Proposed); a stroke of 1 to mine.sheet_stroke_max_points
## points, mine.sheet_point_spacing_units to SheetStroke.STEP_MAX apart, on the sheet; a label of
## 1 to mine.sheet_label_max_chars characters; and at mine.sheet_max_strokes a new stroke or label
## marks nothing (it is dropped and its drawer told, so their pencil shows nothing) until
## something is rubbed out. In a public lobby the rubber touches only its own miner's strokes.
## Nothing here ever adds a stroke without a miner's commit. Server-only.

## What a refused op did: {tick, slot, op, why}, the newest REFUSED_KEPT.
const REFUSED_KEPT: int = 256

var table: MapTable = MapTable.new()
var sync: SheetSync = null
## {tick, slot, op, why}, for tests and the log.
var refused: Array[Dictionary] = []
## Commits accepted this run, per identity (QA-04: a stroke in a first session).
var strokes_by: Dictionary = {}
var _net: ServerNet = null
var _run: RunState = null
## entity -> the ticks of their recent commits (strokes and labels) and of their rubs.
var _commits: Dictionary = {}
var _rubs: Dictionary = {}
## entity -> the tick they opened the table, and the strokes they drew since (QA-04's telemetry:
## minutes at the table and strokes, a session at a time).
var _at_table: Dictionary = {}
var _session_strokes: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.INPUTS


func order() -> int:
	return 30


func system_name() -> String:
	return "sheets"


func bind(run: RunState, net: ServerNet) -> void:
	_run = run
	_net = net
	table.bind(run)
	sync = SheetSync.new()
	sync.bind(run, net, table)
	if net != null:
		net.sheet_sketch = sync.on_sketch


func tick(run: RunState) -> void:
	_run = run
	_watch_table(run)
	if _net == null:
		return
	var items: Array = Variants.array(_net.routed.get(Lane.Id.BULK, []))
	if items.is_empty():
		return
	var rest: Array = []
	for raw: Variant in items:
		var m: Array = raw
		if int(Variants.number(m[1])) != Protocol.Msg.SHEET:
			rest.append(m)
			continue
		var payload: PackedByteArray = m[2]
		on_message(run, int(Variants.number(m[0])), payload)
	_net.routed[Lane.Id.BULK] = rest


## One client's SHEET message (bulk lane): its ops in order.
func on_message(run: RunState, slot: int, payload: PackedByteArray) -> void:
	var ops: Array[Dictionary] = SheetCodec.decode(payload)
	if ops.is_empty():
		_refuse(run, slot, -1, "malformed")
		return
	var entity: int = _miner_of(run, slot)
	for d: Dictionary in ops:
		var op: int = d["op"]
		match op:
			SheetCodec.Op.COMMIT_STROKE:
				var points: PackedVector2Array = d["points"]
				var blob: PackedByteArray = d["blob"]
				_commit_stroke(run, slot, entity, int(Variants.number(d["seq"])), points, blob)
			SheetCodec.Op.COMMIT_LABEL:
				var anchor: Vector2 = d["anchor"]
				_commit_label(run, slot, entity, int(Variants.number(d["seq"])), anchor, str(d["text"]))
			SheetCodec.Op.RUB:
				var centres: PackedVector2Array = d["points"]
				_rub(run, slot, entity, centres)
			SheetCodec.Op.RESYNC:
				sync.resync(slot)
			_:
				_refuse(run, slot, op, "not a client op")


## "" when `entity` may draw on the table now, else why not.
func why_not_draw(run: RunState, entity: int) -> String:
	if table.frozen:
		return "frozen"
	if entity == 0 or run.closeups == null:
		return "no miner"
	match run.closeups.kind_of(entity):
		CloseupKind.Kind.MAP_TABLE:
			return ""
		CloseupKind.Kind.SWITCHBOARD:
			return "seated"
	return "not at the table"


func _commit_stroke(run: RunState, slot: int, entity: int, seq: int, points: PackedVector2Array, blob: PackedByteArray) -> void:
	var why: String = _gate(run, entity, _commits)
	if why.is_empty():
		if points.size() > Tuning.i(&"mine.sheet_stroke_max_points"):
			why = "too long"
		elif not SheetStroke.spaced(points, Tuning.f(&"mine.sheet_point_spacing_units")):
			why = "spacing"
		elif table.at_cap():
			why = "full"
	if not why.is_empty():
		_refuse(run, slot, SheetCodec.Op.COMMIT_STROKE, why)
		sync.dropped(slot, seq)
		return
	var identity: String = _identity_of(slot)
	var s: SheetStroke = SheetStroke.make(table.take_id(), table.author_index(identity), points, blob)
	table.sheet.add_stroke(s)
	table.keep_stroke(s)
	sync.added(s.id, slot, seq)
	_count_stroke(run, identity, entity)


func _commit_label(run: RunState, slot: int, entity: int, seq: int, anchor: Vector2, text: String) -> void:
	var why: String = _gate(run, entity, _commits)
	if why.is_empty():
		if not SheetOps.label_ok(text, Tuning.i(&"mine.sheet_label_max_chars")):
			why = "label"
		elif anchor.x < SheetStroke.MIN or anchor.x > SheetStroke.MAX or anchor.y < SheetStroke.MIN or anchor.y > SheetStroke.MAX:
			why = "off the sheet"
		elif table.at_cap():
			why = "full"
	if not why.is_empty():
		_refuse(run, slot, SheetCodec.Op.COMMIT_LABEL, why)
		sync.dropped(slot, seq)
		return
	var identity: String = _identity_of(slot)
	var l: SheetLabel = SheetLabel.make(table.take_id(), table.author_index(identity), anchor, text)
	table.sheet.add_label(l)
	table.keep_label(l)
	sync.added(l.id, slot, seq)
	_count_stroke(run, identity, entity)


func _rub(run: RunState, slot: int, entity: int, centres: PackedVector2Array) -> void:
	var why: String = _gate(run, entity, _rubs)
	if why.is_empty() and centres.size() > Tuning.i(&"mine.sheet_stroke_max_points"):
		why = "too long"
	if not why.is_empty():
		_refuse(run, slot, SheetCodec.Op.RUB, why)
		return
	# In a public lobby a miner rubs out only their own strokes (GDD §15.11).
	var mine_only: bool = run.header.mode == ServerConfig.Mode.PUBLIC
	var me: int = table.author_of(_identity_of(slot))
	var may_touch: Callable = func(author: int) -> bool: return not mine_only or (me >= 0 and author == me)
	var change: Dictionary = table.sheet.rub(centres, Tuning.f(&"mine.sheet_rubber_radius_units"), may_touch,
		Tuning.i(&"mine.sheet_max_strokes"), table.take_id)
	var removed: Array[int] = change["removed"]
	var added: Array[SheetStroke] = change["added"]
	for id: int in removed:
		table.forget(id)
		sync.removed(id)
	for s: SheetStroke in added:
		table.keep_stroke(s)
		sync.added(s.id, -1, 0)


## The checks every commit and rub share: at the table, and inside its window (the ticks of the
## last commits; the next is refused once mine.sheet_strokes_per_s fall within one second).
func _gate(run: RunState, entity: int, windows: Dictionary) -> String:
	var why: String = why_not_draw(run, entity)
	if not why.is_empty():
		return why
	var hz: int = roundi(Tuning.f(&"net.tick_hz"))
	var recent: Array[int] = []
	for raw: Variant in Variants.array(windows.get(entity, [])):
		var t: int = int(Variants.number(raw))
		if run.tick - t < hz:
			recent.append(t)
	if recent.size() >= Tuning.i(&"mine.sheet_strokes_per_s"):
		windows[entity] = recent
		return "rate"
	recent.append(run.tick)
	windows[entity] = recent
	return ""


## Who reads the table: telemetry of minutes at it, and a drawer who leaves lifts their pen.
func _watch_table(run: RunState) -> void:
	if run.closeups == null:
		return
	for raw: Variant in _at_table.keys():
		var entity: int = raw
		if run.closeups.kind_of(entity) != CloseupKind.Kind.MAP_TABLE:
			var since: int = _at_table[raw]
			_at_table.erase(raw)
			sync.left_table(_slot_of(run, entity))
			Log.info("telemetry map_table_session miner=%d minutes=%.2f strokes=%d sheet=%d run_time=%.1f" % [entity,
				(run.tick - since) / Tuning.f(&"net.tick_hz") / 60.0, int(Variants.number(_session_strokes.get(entity, 0))),
				table.sheet.count(), run.tick / Tuning.f(&"net.tick_hz")])
			_session_strokes.erase(raw)
	for raw: Variant in run.closeups.open.keys():
		var entity: int = raw
		if run.closeups.kind_of(entity) == CloseupKind.Kind.MAP_TABLE and not _at_table.has(entity):
			_at_table[entity] = run.tick


## QA-04: the run's first stroke from each player (GDD §14.4: a stroke in 80% of first
## sessions), and each table session's strokes when it ends.
func _count_stroke(run: RunState, identity: String, entity: int) -> void:
	var n: int = int(Variants.number(strokes_by.get(identity, 0))) + 1
	strokes_by[identity] = n
	_session_strokes[entity] = int(Variants.number(_session_strokes.get(entity, 0))) + 1
	if n == 1:
		Log.info("telemetry map_table_first_stroke miner=%d run_time=%.1f" % [entity, run.tick / Tuning.f(&"net.tick_hz")])


func _refuse(run: RunState, slot: int, op: int, why: String) -> void:
	refused.append({"tick": run.tick, "slot": slot, "op": op, "why": why})
	if refused.size() > REFUSED_KEPT:
		refused.pop_front()


func _identity_of(slot: int) -> String:
	if _net != null:
		for session: Sessions.Session in _net.sessions.welcomed():
			if session.slot == slot:
				return session.identity
	return "slot%d" % slot


func _miner_of(run: RunState, slot: int) -> int:
	if run.movement == null or run.movement.miner(slot) == null:
		return 0
	return run.movement.miner(slot).entity_id


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


## NET-09: the sheet itself is in the diff log's section; this keeps the freeze.
func save_state() -> Dictionary:
	return {"frozen": table.frozen, "freeze_cause": table.freeze_cause}


## NET-09's resume: the sheet rebuilt from the restored diff log.
func load_state(_r: RunState, state: Dictionary) -> void:
	table.load_from_section()
	table.frozen = Variants.flag(state.get("frozen", false))
	table.freeze_cause = str(state.get("freeze_cause", ""))
	sync.restart()
