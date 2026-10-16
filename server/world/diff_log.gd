class_name DiffLog
extends SimSystem
## GEN-13 (stage RECORD): the diff log, the pit's memory (Gameplay §12.6, GDD §15.9). Cells are
## never stored, only re-derived; what play changes is kept here, keyed by cell, and replayed
## whenever the cell is committed again, anything burning advanced to the present. Each owner
## records its own changes (`record`, `taken`, `mark_blood`) and registers, per kind, a replay
## handler (and optionally an advance function and a generated-default test); a record of a kind
## with no handler is reported loudly. Records upsert: a key holds its latest state, not history.
##
## Replay order at commit: falls; doors and gates; traps; items; chalk and blood; bodies;
## fixtures (lines, fitted parts, the hoard, the lair), i.e. the order of Kind. Before a cell
## unloads, owners pack what lies in it (`on_evict`); before a save or a compaction they bring
## their records up to date (`on_refresh`). Compaction runs every net.snapshot_interval_s (and on
## NET-09's call): records equal to their generated default go, blood is kept packed by the native
## store (LbDiffStore) throughout. Run-level sections hold the map table and the Pocket Books.
## Server-only: the log never reaches a client; a client learns a change by seeing the thing.

## Replay order (Gameplay §12.6, GDD §15.9).
enum Kind {
	FALL = 0,
	BARRIER = 1,
	TRAP = 2,
	ITEM = 3,
	CHALK = 4,
	BLOOD = 5,
	BODY = 6,
	LINE = 7,
	FIXTURE = 8,
	HOARD = 9,
	LAIR = 10,
}

const MAP_TABLE: String = "map_table"
const POCKET_BOOKS: String = "pocket_books"
## An item's record once it has left the cell (taken into a belt, or moved to another cell).
const TAKEN: String = "taken"
## How many replays `replays` keeps.
const REPLAYS_KEPT: int = 4096


## One owner's handlers for a kind (or for the keys of a kind with its prefix).
class Handler:
	extends RefCounted
	var prefix: String = ""
	## (run, cell: Vector2i, key: String, payload: Dictionary, tick: int) -> void
	var replay: Callable = Callable()
	## (payload: Dictionary, from_tick: int, to_tick: int) -> Dictionary: the payload itself when
	## nothing changed, a new one when it did, {} when nothing is left (a candle burnt out): the
	## record then goes and nothing is replayed.
	var advance: Callable = Callable()
	## (cell: Vector2i, key: String, payload: Dictionary) -> bool: generation recreates it as is.
	var is_default: Callable = Callable()


## A run-level section (the map table, the Pocket Books): keyed payloads outside any cell.
class Section:
	extends RefCounted
	var name: String = ""
	var _store: LbDiffStore = null

	func put(key: String, payload: Dictionary) -> void:
		_store.section_put(name, key, DiffLog.encode(payload))

	func get_payload(key: String) -> Dictionary:
		return DiffLog.decode(_store.section_get(name, key)) if _store.section_has(name, key) else {}

	## An owner's own compact encoding (LFT-14's strokes: an int16 start and int8 deltas).
	func put_raw(key: String, raw: PackedByteArray) -> void:
		_store.section_put(name, key, raw)

	func get_raw(key: String) -> PackedByteArray:
		return _store.section_get(name, key)

	func erase(key: String) -> bool:
		return _store.section_erase(name, key)

	func keys() -> PackedStringArray:
		return _store.section_keys(name)

	func bytes() -> int:
		return _store.section_bytes(name)


var store: LbDiffStore = LbDiffStore.new()
## MNR-04's items: their records, eviction and replay (owners register advances in `items.advances`).
var items: ItemDiff = ItemDiff.new()
## Kind -> Array[Handler].
var handlers: Dictionary = {}
## Records met at replay with no handler: {tick, cell, kind, key}.
var unhandled: Array[Dictionary] = []
## Replays: {tick, cell, records, usec}, the last REPLAYS_KEPT (GEN-11: cells come and go all
## run, so the list may not grow with them).
var replays: Array[Dictionary] = []
## Compactions: {tick, dropped, bytes}.
var compactions: Array[Dictionary] = []
## Budget breaches found after a compaction: {tick, what, bytes, budget}.
var budget_breaches: Array[Dictionary] = []
var _evictors: Array[Callable] = []
var _refreshers: Array[Callable] = []
var _syncers: Array[Callable] = []
var _replaying: bool = false
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.RECORD


func order() -> int:
	return 35


func system_name() -> String:
	return "diff_log"


## Connects to the mine's commits and unloads. Called once every owner has bound, so a cell
## committed in stage 5 replays after the owners' own load hooks.
func bind(run: RunState) -> void:
	_run = run
	items.bind(run)
	if run.mine != null:
		run.mine.native.cell_loaded.connect(func(cell: Vector2i) -> void: replay(run, cell))
		run.mine.native.cell_unloading.connect(func(cell: Vector2i) -> void: evict(run, cell))


## An owner's handlers for `kind` (keys starting `prefix` when several owners share a kind).
func register(kind: Kind, replay_fn: Callable, advance_fn: Callable = Callable(), is_default_fn: Callable = Callable(),
		prefix: String = "") -> void:
	var h: Handler = Handler.new()
	h.prefix = prefix
	h.replay = replay_fn
	h.advance = advance_fn
	h.is_default = is_default_fn
	if not handlers.has(kind):
		handlers[kind] = []
	var list: Array = handlers[kind]
	list.append(h)


## (run, cell) before the cell unloads: the owner records what lies there and lets it go.
func on_evict(fn: Callable) -> void:
	_evictors.append(fn)


## (run) before a save or a compaction: the owner brings its records up to the present.
func on_refresh(fn: Callable) -> void:
	_refreshers.append(fn)


## (run) every tick at this stage: the owner records changes it does not hear about one by one.
func on_sync(fn: Callable) -> void:
	_syncers.append(fn)


func record(cell: Vector2i, kind: Kind, key: String, payload: Dictionary) -> void:
	store.put(cell, kind, key, _run.tick if _run != null else 0, encode(payload))


func erase(cell: Vector2i, kind: Kind, key: String) -> bool:
	return store.erase(cell, kind, key)


## The item `item_id` has left `cell` (into a belt, or to another cell): it travels with whoever
## holds it now, and its record here says taken, so generation never brings it back.
func taken(cell: Vector2i, item_id: String) -> void:
	record(cell, Kind.ITEM, item_id, {"where": TAKEN})


func payload_of(cell: Vector2i, kind: Kind, key: String) -> Dictionary:
	var r: Dictionary = store.get_record(cell, kind, key)
	if r.is_empty():
		return {}
	var bytes: PackedByteArray = r["payload"]
	return decode(bytes)


## The tick the record was last written, or -1.
func tick_of(cell: Vector2i, kind: Kind, key: String) -> int:
	var r: Dictionary = store.get_record(cell, kind, key)
	return int(Variants.number(r["tick"])) if not r.is_empty() else -1


## The cell's records in replay order: [{kind, key, tick, payload}]; its blood, if any, as one row of
## kind BLOOD, key "blood", payload {smears: [{tile, direction}]} (row-major).
func records(cell: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(store.decoded_records(cell, Kind.BLOOD))
	return out


## VIS-10, CRT-15: a smeared tile and its direction (0-7); the latest smear wins.
func mark_blood(tile: Vector2i, direction: int) -> void:
	if not _replaying:
		store.mark_blood(tile, direction)


## HAZ-03: a roof fall over a smear.
func erase_blood(tile: Vector2i) -> void:
	if not _replaying:
		store.erase_blood(tile)


func run_section(name: String) -> Section:
	var s: Section = Section.new()
	s.name = name
	s._store = store
	return s


## Applies the cell's records in replay order, each advanced from its tick to now.
func replay(run: RunState, cell: Vector2i) -> void:
	var started: int = Time.get_ticks_usec()  # determinism: allow (measures the replay budget, decides nothing)
	var rows: Array[Dictionary] = records(cell)
	_replaying = true
	for r: Dictionary in rows:
		var kind: int = int(Variants.number(r["kind"]))
		var key: String = str(r["key"])
		var h: Handler = _handler(kind, key)
		if h == null:
			unhandled.append({"tick": run.tick, "cell": cell, "kind": kind, "key": key})
			if OS.is_debug_build():
				push_error("DiffLog: no replay handler for kind %s, key %s (cell %s)" % [Kind.find_key(kind), key, cell])
			continue
		var payload: Dictionary = r["payload"]
		var at_tick: int = int(Variants.number(r["tick"]))
		if h.advance.is_valid() and at_tick >= 0 and at_tick < run.tick:
			var advanced: Dictionary = h.advance.call(payload, at_tick, run.tick)
			if advanced.is_empty():
				store.erase(cell, kind, key)
				continue
			# Advanced to now: the record says so, so the next replay starts from here. An advance
			# that changes nothing returns the payload itself.
			if not is_same(advanced, payload):
				store.put(cell, kind, key, run.tick, encode(advanced))
				payload = advanced
				at_tick = run.tick
		h.replay.call(run, cell, key, payload, at_tick)
	_replaying = false
	var took: int = Time.get_ticks_usec() - started  # determinism: allow (as above)
	replays.append({"tick": run.tick, "cell": cell, "records": rows.size(), "usec": took})
	if replays.size() > REPLAYS_KEPT:
		replays.pop_front()


func replaying() -> bool:
	return _replaying


## Before `cell` unloads: each owner records and lets go of what lies in it.
func evict(run: RunState, cell: Vector2i) -> void:
	for fn: Callable in _evictors:
		fn.call(run, cell)


## Every owner's records brought up to the present (a save, a compaction).
func refresh(run: RunState) -> void:
	for fn: Callable in _refreshers:
		fn.call(run)


func tick(run: RunState) -> void:
	_run = run
	for fn: Callable in _syncers:
		fn.call(run)
	var every: int = maxi(1, roundi(Tuning.f(&"net.snapshot_interval_s") * Tuning.f(&"net.tick_hz")))
	if run.tick > 0 and run.tick % every == 0:
		compact(run)


## Drops what generation recreates as it is; checks the budgets. Replayed state is unchanged.
func compact(run: RunState) -> int:
	refresh(run)
	var dropped: int = 0
	for raw_cell: Variant in store.cells():
		var cell: Vector2i = raw_cell
		for raw: Variant in store.records(cell):
			var r: Dictionary = raw
			var kind: int = int(Variants.number(r["kind"]))
			var key: String = str(r["key"])
			var h: Handler = _handler(kind, key)
			var bytes: PackedByteArray = r["payload"]
			if h != null and h.is_default.is_valid() and Variants.flag(h.is_default.call(cell, key, decode(bytes))):
				store.erase(cell, kind, key)
				dropped += 1
	compactions.append({"tick": run.tick, "dropped": dropped, "bytes": store.cells_bytes()})
	_check_budgets(run)
	return dropped


## Serialised sizes in bytes: the cells' log, the map table and the Pocket Books.
func sizes() -> Dictionary:
	return {"diff_log": store.cells_bytes(), "map_table": store.section_bytes(MAP_TABLE),
		"pocket_books": store.section_bytes(POCKET_BOOKS)}


func _check_budgets(run: RunState) -> void:
	var s: Dictionary = sizes()
	var budgets: Dictionary = {"diff_log": Tuning.f(&"mine.diff_log_save_budget_mb"),
		"map_table": Tuning.f(&"mine.map_table_save_budget_mb"), "pocket_books": Tuning.f(&"mine.pocket_books_save_budget_mb")}
	for what: String in ["diff_log", "map_table", "pocket_books"]:
		var budget: int = roundi(Variants.number(budgets[what]) * 1024.0 * 1024.0)
		var used: int = int(Variants.number(s[what]))
		if used > budget:
			budget_breaches.append({"tick": run.tick, "what": what, "bytes": used, "budget": budget})
			push_warning("DiffLog: %s is %d bytes, over its %d" % [what, used, budget])


## The whole log for NET-09's snapshot or a knock-off save, every record brought up to date.
func serialise(run: RunState) -> PackedByteArray:
	refresh(run)
	return store.serialise()


## A resume: the log replaced from a save. Cells committed afterwards replay from it.
func deserialise(bytes: PackedByteArray) -> bool:
	return store.deserialise(bytes)


func digest() -> int:
	return store.digest()


func _handler(kind: int, key: String) -> Handler:
	for raw: Variant in handlers.get(kind, []):
		var h: Handler = raw
		if key.begins_with(h.prefix):
			return h
	return null


## Canonical bytes: dictionaries with their keys in sorted order, all the way down, so equal
## payloads encode alike on every platform and in every insertion order (natively, LbDiffStore).
static func encode(payload: Dictionary) -> PackedByteArray:
	return LbDiffStore.encode(payload)


static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {}
	return Variants.dict(bytes_to_var(bytes))


## The same ordering in GDScript, for comparing states in tests and tools.
static func canonical(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		var keys: Array = d.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		var out: Dictionary = {}
		for k: Variant in keys:
			out[k] = canonical(d[k])
		return out
	if v is Array:
		var out_a: Array = []
		for x: Variant in v:
			out_a.append(canonical(x))
		return out_a
	return v


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(store.record_count())
	writer.put_i64(store.blood_count())
