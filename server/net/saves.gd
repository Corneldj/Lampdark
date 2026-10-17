class_name Saves
extends SimSystem
## NET-09 (stage RECORD, last; Gameplay §13.11, GDD §15.10): a friends or Night Shift run can always
## be resumed. Every net.snapshot_interval_s the run is snapshotted (Snapshot, at a tick with no grab
## under way) into a sealed container (SaveContainer) written to the host's or the offline disk
## atomically (a temporary file, then a rename, the write on a worker thread), and its changed
## sections go to every member on the bulk lane, who keep them and acknowledge them.
## Every fall and death is journaled the tick it happens (Journal): to the disk at once and to every
## member on the control lane. A knock-off save (MOD-05 asks) is the same, its timers frozen.
##
## Public runs are never saved: no file, no section, no journal entry leaves the server; an abnormal
## end voids them (STM-10 hears of it). Each section is held to its budget (net.save_budget_*); one
## over it is an error in a debug build and a log line in release. Files live under
## <save dir>/<run UUID>/ for STM-05's Cloud sync. Server-only.

const SNAPSHOT_FILE: String = "snapshot.lmpb"
const KNOCKOFF_FILE: String = "knockoff.lmpb"
const JOURNAL_FILE: String = "journal.bin"

## A public run ended before its outcome (STM-10 sends the backend an explicit void).
signal voided(reason: String)

## Where saves go (`--save-dir`; the scenario kit gives each run its own).
var save_dir: String = "user://saves"
var enabled: bool = true
## LFT-11: the run has ended with its outcome: no snapshot is written after it.
var closed: bool = false
## MOD-05: the crew knocked off: the knock-off save is the run's last until it resumes (the server's
## end writes nothing after it).
var knocked_off: bool = false
var seq: int = 0
var parent_hash: String = ""
## Every save written: {tick, seq, kind, bytes, sections (sizes), capture_usec, path}.
var written: Array[Dictionary] = []
## Budget breaches: {tick, section, bytes, budget}.
var breaches: Array[Dictionary] = []
## slot -> the last sequence number its client acknowledged (MOD-05 reads it).
var acks: Dictionary = {}
var journal: Journal = Journal.new()
var _net: ServerNet = null
var _last_plain: Dictionary = {}
## Section name -> its last sealed bytes: an unchanged section is kept as sealed, so every member's
## copy (which keeps what it was sent) is the host's file byte for byte.
var _last_sealed: Dictionary = {}
## Identities sent a whole save already (a member's first save carries every section).
var _sent_whole: Dictionary = {}
var _next_due: int = -1
var _pending_io: Array[int] = []
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.RECORD


func order() -> int:
	return 60


func system_name() -> String:
	return "saves"


func bind(run: RunState, net: ServerNet) -> void:
	_run = run
	_net = net
	enabled = run.header.mode != ServerConfig.Mode.PUBLIC
	journal.bind(run)
	journal.enabled = enabled
	journal.sink = func(sealed: PackedByteArray) -> void: _append_journal(sealed)
	journal.broadcast = func(sealed: PackedByteArray) -> void: _send_journal(sealed)
	run.add_system(journal)


func tick(run: RunState) -> void:
	_run = run
	_take_acks()
	_finish_io()
	if not enabled or closed:
		return
	var every: int = maxi(1, roundi(Tuning.f(&"net.snapshot_interval_s") * Tuning.f(&"net.tick_hz")))
	if _next_due < 0:
		_next_due = run.tick + every
	if run.tick >= _next_due and Snapshot.may_capture(run):
		snapshot(run)
		_next_due = run.tick + every


func run_dir() -> String:
	return save_dir.path_join(_run.header.run_uuid if _run != null and not _run.header.run_uuid.is_empty() else "run")


## Takes a snapshot now (or a knock-off save): written, sent, logged. Returns the row, or {} in public.
func snapshot(run: RunState, kind: String = "snapshot") -> Dictionary:
	if not enabled:
		return {}
	var started: int = Time.get_ticks_usec()  # determinism: allow (measures the capture, decides nothing)
	var sections: Dictionary = Snapshot.capture(run, _net)
	var took: int = Time.get_ticks_usec() - started  # determinism: allow (as above)
	seq += 1
	journal.after_seq = seq
	var header: Dictionary = plain_header(run, kind)
	var sealed: Dictionary = {}
	var changed: Dictionary = {}
	var names: Array = sections.keys()
	names.sort()
	for raw: Variant in names:
		var plain: PackedByteArray = sections[raw]
		var h: String = SaveContainer.hash_of(plain)
		if str(_last_plain.get(raw, "")) != h or not _last_sealed.has(raw):
			_last_sealed[raw] = SaveContainer.seal_section(plain)
			_last_plain[raw] = h
			changed[raw] = _last_sealed[raw]
		sealed[raw] = _last_sealed[raw]
	var order_names: PackedStringArray = PackedStringArray(names)
	var bytes: PackedByteArray = SaveContainer.assemble(header, sealed, order_names)
	parent_hash = SaveContainer.hash_of(bytes)
	var sizes: Dictionary = SaveContainer.sizes(bytes)
	_check_budgets(run, sections, sizes)
	var path: String = run_dir().path_join(KNOCKOFF_FILE if kind == "knockoff" else SNAPSHOT_FILE)
	_write_atomic(path, bytes)
	var row: Dictionary = {"tick": run.tick, "seq": seq, "kind": kind, "bytes": bytes.size(), "sections": sizes,
		"capture_usec": took, "path": path}
	written.append(row)
	_send_save(header, order_names, sealed, changed)
	return row


## LFT-11: the run ended with its outcome (`why`: surfaced or wipe): the journal's last entry says
## so on the disk and at every member, so no resume opens it, and no later snapshot or abnormal end
## writes a finished run as one to resume.
func close(run: RunState, why: String) -> void:
	if closed:
		return
	closed = true
	journal.write_end(run, why)
	flush()
	Log.info("saves: the run ended (%s); the chain is closed" % why)


## The server going while the run is under way (everyone gone, the host quitting): a friends or Night
## Shift run's last snapshot, written before the process ends; a public run voided, nothing written.
func end_abnormally(run: RunState, why: String) -> Dictionary:
	if closed or knocked_off:
		return {}
	if not enabled:
		Log.info("public run voided (%s): no save, no outcomes" % why)
		voided.emit(why)
		return {}
	var row: Dictionary = snapshot(run)
	flush()
	return row


## MOD-05: the knock-off save, every timer frozen (the caller freezes the run first).
func knockoff(run: RunState) -> Dictionary:
	var row: Dictionary = snapshot(run, "knockoff")
	knocked_off = not row.is_empty()
	flush()
	return row


## MOD-05: this tick's acknowledgements, taken at once (a frozen run's systems do not tick).
func take_acks() -> void:
	_take_acks()


## The plain header: what a resume checks before opening anything, and what the Pithead's resume
## list shows (MOD-05: the list, the run time, the deepest ring reached). No seed, no state.
func plain_header(run: RunState, kind: String) -> Dictionary:
	var list_kind: int = run.repair.list.kind if run.repair != null and run.repair.list != null else -1
	return {"run_uuid": run.header.run_uuid, "seq": seq, "parent_hash": parent_hash, "kind": kind,
		"build": _net.build_id if _net != null else "", "generator": generator_version(run), "templates": templates_version(run),
		"bundle": Tuning.content_hash("server") if Tuning.current.entries.size() > 0 else "", "mode": run.header.mode,
		"list": RunOptions.LIST_NAMES[list_kind] if list_kind >= 0 else "", "run_time_s": run.tick / Tuning.f(&"net.tick_hz"),
		"deepest": run.outcomes.deepest_ring if run.outcomes != null else 0}


## The generator a run's mine comes from: a fixed map is its own; a generated mine's is GEN-08's
## version, as its plan records it (MOD-05: a resume needs this build to make it).
static func generator_version(run: RunState) -> String:
	if not run.header.map_name.is_empty():
		return "fixed:" + run.header.map_name
	return run.header.generator if not run.header.generator.is_empty() else "none"


## The template set a generated mine's cells come from (GEN-04's versions; a resume loads that set,
## not the build's newest), "none" for a fixed map.
static func templates_version(run: RunState) -> String:
	return run.header.templates if not run.header.templates.is_empty() else "none"


func _check_budgets(run: RunState, sections: Dictionary, sizes: Dictionary) -> void:
	var mb: float = 1024.0 * 1024.0
	var snapshot_bytes: int = 0
	for n: String in [Snapshot.SECTION_RUN, Snapshot.SECTION_REGISTRY, Snapshot.SECTION_STATE]:
		snapshot_bytes += int(Variants.number(sizes.get(n, 0)))
	var rows: Array = [["snapshot", snapshot_bytes, Tuning.f(&"net.save_budget_snapshot_mb")],
		["windows", int(Variants.number(sizes.get(Snapshot.SECTION_WINDOWS, 0))), Tuning.f(&"net.save_budget_windows_mb")],
		["total", int(Variants.number(sizes["total"])), Tuning.f(&"net.save_budget_mb")]]
	if run.diff_log != null and sections.has(Snapshot.SECTION_DIFF_LOG):
		var d: Dictionary = run.diff_log.sizes()
		rows.append(["diff_log", int(Variants.number(d["diff_log"])), Tuning.f(&"net.save_budget_diff_log_mb")])
		rows.append(["map_table", int(Variants.number(d["map_table"])), Tuning.f(&"net.save_budget_map_table_mb")])
		rows.append(["pocket_books", int(Variants.number(d["pocket_books"])), Tuning.f(&"net.save_budget_pocket_books_mb")])
	for row: Array in rows:
		var budget: int = roundi(Variants.number(row[2]) * mb)
		var used: int = int(Variants.number(row[1]))
		if used > budget:
			breaches.append({"tick": run.tick, "section": row[0], "bytes": used, "budget": budget})
			var text: String = "Saves: %s is %d bytes, over its %d" % [row[0], used, budget]
			if OS.is_debug_build():
				push_error(text)
			else:
				Log.warn(text)


## Atomic: a temporary file, then a rename; the write itself on a worker thread.
func _write_atomic(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var task: int = WorkerThreadPool.add_task(func() -> void:
		var tmp: String = path + ".tmp"
		var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
		if f == null:
			return
		f.store_buffer(bytes)
		f.close()
		DirAccess.rename_absolute(tmp, path))
	_pending_io.append(task)


func _finish_io() -> void:
	for task: int in _pending_io.duplicate():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_pending_io.erase(task)


## Waits for every write under way (tests; a clean end).
func flush() -> void:
	for task: int in _pending_io:
		WorkerThreadPool.wait_for_task_completion(task)
	_pending_io.clear()


## The journal goes to disk at once, synchronously: an abnormal end never loses a fall.
func _append_journal(sealed: PackedByteArray) -> void:
	var path: String = run_dir().path_join(JOURNAL_FILE)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_32(sealed.size())
	f.store_buffer(sealed)
	f.close()


## Every sealed journal entry in a run's journal file, opened (server side only).
static func read_journal(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var at: int = 0
	while at + 4 <= bytes.size():
		var size: int = bytes.decode_u32(at)
		at += 4
		if at + size > bytes.size():
			break
		var plain: PackedByteArray = LbSeal.open(bytes.slice(at, at + size))
		at += size
		if not plain.is_empty():
			out.append(Variants.dict(bytes_to_var(plain)))
	return out


func _send_journal(sealed: PackedByteArray) -> void:
	if _net == null:
		return
	var msg: PackedByteArray = Protocol.frame(Protocol.Msg.JOURNAL, SaveWire.journal(_run.header.run_uuid, sealed))
	for session: Sessions.Session in _net.sessions.welcomed():
		_net.transport.send(session.peer, Lane.Id.CONTROL, msg)


func _send_save(header: Dictionary, order_names: PackedStringArray, whole: Dictionary, changed: Dictionary) -> void:
	if _net == null:
		return
	var delta: PackedByteArray = Protocol.frame(Protocol.Msg.SAVE_DATA, SaveWire.save_data(_run.header.run_uuid, seq, header, order_names, changed))
	var all: PackedByteArray = PackedByteArray()
	for session: Sessions.Session in _net.sessions.welcomed():
		if _sent_whole.has(session.identity):
			_net.transport.send(session.peer, Lane.Id.BULK, delta)
			continue
		if all.is_empty():
			all = Protocol.frame(Protocol.Msg.SAVE_DATA, SaveWire.save_data(_run.header.run_uuid, seq, header, order_names, whole))
		_net.transport.send(session.peer, Lane.Id.BULK, all)
		_sent_whole[session.identity] = true


func _take_acks() -> void:
	if _net == null:
		return
	var control: Array = Variants.array(_net.routed.get(Lane.Id.CONTROL, []))
	var rest: Array = []
	for raw: Variant in control:
		var m: Array = raw
		if int(Variants.number(m[1])) == Protocol.Msg.SAVE_ACK:
			var payload: PackedByteArray = m[2]
			var at: int = SaveWire.read_ack(payload)
			if at >= 0:
				acks[int(Variants.number(m[0]))] = at
		else:
			rest.append(m)
	if not control.is_empty():
		_net.routed[Lane.Id.CONTROL] = rest


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(seq)
