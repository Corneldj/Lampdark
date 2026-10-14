class_name InputLog
extends RefCounted
## Every input a run applied, by tick and slot (FND-09): the replay format. Servers write it
## with --record-inputs; the scenario kit keeps one for every scenario. With the run's seed,
## map and tuning, it reproduces the run in-process, network-free, to the same state hash.
##
## JSON lines: a header, one line per applied input, then an end line with the final hash.
##   {"format": "lampblack-input-log", "version": 1, "seed": "<u64>", "mode": "...", "map": "...",
##    "tuning_hash": "...", "build": "..."}
##   {"t": tick, "s": slot, "f": flags, "st": shown_tick, "r": "<record hex>", "a": ["<action hex>", ...],
##    "c": [[cue_id, shown_tick, fraction], ...] (NET-06, only when present), "k": acked frame (NET-06, -1 omitted)}
##   {"t": tick, "op": {...}}  a scenario-kit setup step applied before that tick (add_miner, set_gate,
##                              script_rolls), so a kit run replays too
##   {"t": tick, "v": [[kind, slot, arg], ...]}  SND-09's voice facts applied that tick (VoiceFacts):
##                              live voice arrives between ticks, so its effects ride the log as inputs
##   {"end": ticks run, "hash": "<state hash>"}

const FORMAT: String = "lampblack-input-log"
const VERSION: int = 2
const FLAG_REAL: int = 1
const FLAG_STARVED: int = 2
const FLAG_STARVED_NOW: int = 4
const FLAG_RESUMED_NOW: int = 8
## Lines written between flushes, so a crash loses little.
const FLUSH_EVERY: int = 200

var run_seed: int = 0
var mode: String = "friends"
var map_name: String = ""
var tuning_profile: String = ""
var tuning_hash: String = ""
var build: String = ""
## tick -> Array of [slot, InputBuffer.Consumed], in the order applied.
var by_tick: Dictionary = {}
## tick -> Array of op dictionaries, in the order applied.
var ops_by_tick: Dictionary = {}
## tick -> Array of voice facts ([kind, slot, arg]), in the order applied.
var voice_by_tick: Dictionary = {}
var end_tick: int = -1
var end_hash: String = ""
var _file: FileAccess = null
var _unflushed: int = 0


## Starts a log for a run; with a path, lines also stream to that file as they happen.
static func begin(run: RunState, map: String, path: String = "", profile: String = "") -> InputLog:
	var log: InputLog = InputLog.new()
	log.tuning_profile = profile
	log.run_seed = run.header.run_seed
	log.mode = str(ServerConfig.Mode.keys()[run.header.mode]).to_lower()
	log.map_name = map
	log.tuning_hash = run.header.tuning_hash
	log.build = Protocol.build_id()
	if not path.is_empty():
		log._file = FileAccess.open(path, FileAccess.WRITE)
		if log._file == null:
			push_error("InputLog: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		else:
			log._file.store_line(JSON.stringify(log._header()))
	return log


func append(tick: int, slot: int, consumed: InputBuffer.Consumed) -> void:
	var list: Array = by_tick.get(tick, [])
	list.append([slot, consumed])
	by_tick[tick] = list
	if _file != null:
		_file.store_line(JSON.stringify(_entry(tick, slot, consumed)))
		_unflushed += 1
		if _unflushed >= FLUSH_EVERY:
			_file.flush()
			_unflushed = 0


## A kit setup step applied before `tick` runs.
func append_op(tick: int, op: Dictionary) -> void:
	var list: Array = ops_by_tick.get(tick, [])
	list.append(op)
	ops_by_tick[tick] = list
	if _file != null:
		_file.store_line(JSON.stringify({"t": tick, "op": op}))


## SND-09: the voice facts a tick applied.
func append_voice(tick: int, facts: Array) -> void:
	voice_by_tick[tick] = facts.duplicate(true)
	if _file != null:
		_file.store_line(JSON.stringify({"t": tick, "v": facts}))


## Records the run's end and closes the file.
func finish(ticks_run: int, state_hash: String) -> void:
	end_tick = ticks_run
	end_hash = state_hash
	if _file != null:
		_file.store_line(JSON.stringify({"end": ticks_run, "hash": state_hash}))
		_file.close()
		_file = null


## Writes the whole log (the kit's save_replay).
func save(path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_line(JSON.stringify(_header()))
	var tick_set: Dictionary = {}
	for tick: Variant in by_tick.keys():
		tick_set[tick] = true
	for tick: Variant in ops_by_tick.keys():
		tick_set[tick] = true
	for tick: Variant in voice_by_tick.keys():
		tick_set[tick] = true
	var ticks: Array = tick_set.keys()
	ticks.sort()
	for tick: Variant in ticks:
		for op: Variant in Variants.array(ops_by_tick.get(tick, [])):
			file.store_line(JSON.stringify({"t": tick, "op": op}))
		for raw: Variant in Variants.array(by_tick.get(tick, [])):
			var item: Array = Variants.array(raw)
			var consumed: InputBuffer.Consumed = item[1]
			file.store_line(JSON.stringify(_entry(int(Variants.number(tick)), int(Variants.number(item[0])), consumed)))
		if voice_by_tick.has(tick):
			file.store_line(JSON.stringify({"t": tick, "v": voice_by_tick[tick]}))
	if end_tick >= 0:
		file.store_line(JSON.stringify({"end": end_tick, "hash": end_hash}))
	file.close()
	return OK


## Reads a log; null (with an error) if it is not one.
static func load_file(path: String) -> InputLog:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("InputLog: cannot read %s" % path)
		return null
	var log: InputLog = InputLog.new()
	var header: Dictionary = Variants.dict(JSON.parse_string(file.get_line()))
	if str(header.get("format", "")) != FORMAT or int(Variants.number(header.get("version", 0))) != VERSION:
		push_error("InputLog: %s is not a version %d input log" % [path, VERSION])
		return null
	var parsed: Array = LaunchArgs.parse_u64(str(header.get("seed", "")))
	log.run_seed = parsed[1]
	log.mode = str(header.get("mode", "friends"))
	log.map_name = str(header.get("map", ""))
	log.tuning_profile = str(header.get("profile", ""))
	log.tuning_hash = str(header.get("tuning_hash", ""))
	log.build = str(header.get("build", ""))
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.is_empty():
			continue
		var entry: Dictionary = Variants.dict(JSON.parse_string(line))
		if entry.has("end"):
			log.end_tick = int(Variants.number(entry["end"]))
			log.end_hash = str(entry.get("hash", ""))
			continue
		var tick: int = int(Variants.number(entry.get("t", -1)))
		if entry.has("op"):
			var ops: Array = log.ops_by_tick.get(tick, [])
			ops.append(Variants.dict(entry["op"]))
			log.ops_by_tick[tick] = ops
			continue
		if entry.has("v"):
			log.voice_by_tick[tick] = Variants.array(entry["v"])
			continue
		var list: Array = log.by_tick.get(tick, [])
		list.append([int(Variants.number(entry.get("s", 0))), _consumed(entry)])
		log.by_tick[tick] = list
	return log


func _header() -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "seed": LaunchArgs.u64_to_string(run_seed), "mode": mode,
		"map": map_name, "profile": tuning_profile, "tuning_hash": tuning_hash, "build": build}


static func flags_of(c: InputBuffer.Consumed) -> int:
	return (FLAG_REAL if c.real else 0) | (FLAG_STARVED if c.starved else 0) \
		| (FLAG_STARVED_NOW if c.starved_now else 0) | (FLAG_RESUMED_NOW if c.resumed_now else 0)


static func _entry(tick: int, slot: int, c: InputBuffer.Consumed) -> Dictionary:
	var flags: int = flags_of(c)
	var record: StreamPeerBuffer = StreamPeerBuffer.new()
	c.record.pack(record)
	var actions: Array[String] = []
	for a: ActionRecord in c.actions:
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		a.pack(b)
		actions.append(b.data_array.hex_encode())
	var entry: Dictionary = {"t": tick, "s": slot, "f": flags, "st": c.shown_tick, "r": record.data_array.hex_encode(), "a": actions}
	if not c.cue_reports.is_empty():
		var cues: Array = []
		for r: PackedInt64Array in c.cue_reports:
			cues.append([r[0], r[1], r[2]])
		entry["c"] = cues
	if c.acked_frame >= 0:
		entry["k"] = c.acked_frame
	return entry


static func _consumed(entry: Dictionary) -> InputBuffer.Consumed:
	var c: InputBuffer.Consumed = InputBuffer.Consumed.new()
	var flags: int = int(Variants.number(entry.get("f", 0)))
	c.real = (flags & FLAG_REAL) != 0
	c.starved = (flags & FLAG_STARVED) != 0
	c.starved_now = (flags & FLAG_STARVED_NOW) != 0
	c.resumed_now = (flags & FLAG_RESUMED_NOW) != 0
	c.shown_tick = int(Variants.number(entry.get("st", 0)))
	var record: StreamPeerBuffer = StreamPeerBuffer.new()
	record.data_array = str(entry.get("r", "")).hex_decode()
	c.record = InputRecord.unpack(record) if record.data_array.size() == InputRecord.SIZE else InputRecord.new()
	for raw: Variant in Variants.array(entry.get("a", [])):
		var b: StreamPeerBuffer = StreamPeerBuffer.new()
		b.data_array = str(raw).hex_decode()
		if b.data_array.size() == ActionRecord.SIZE:
			c.actions.append(ActionRecord.unpack(b))
	for raw: Variant in Variants.array(entry.get("c", [])):
		var r: Array = Variants.array(raw)
		c.cue_reports.append(PackedInt64Array([int(Variants.number(r[0])), int(Variants.number(r[1])), int(Variants.number(r[2]))]))
	c.acked_frame = int(Variants.number(entry.get("k", -1)))
	return c
