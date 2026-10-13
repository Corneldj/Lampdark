extends Node
## The tuning autoload `Tuning` (FND-05): every tunable number, read by key.
##
## The server loads the domain files under data/tuning/, then layers a test profile, NET-14's
## data bundle and dev overrides over them. The client loads only data/tuning/_client.json,
## so a server-only key is unknown to it. Accessors report an error for an unknown key or a
## wrong type and never fall back to a silent default.
##
## Hot reload (dev, and QA with --tuning-hot-reload; never release): the files are polled
## every second. A valid edit is staged and swapped in at the next tick boundary, emitting
## tuning_changed once. An invalid edit is logged and every value stays as it was.

signal tuning_changed(keys: PackedStringArray)

const OVERRIDES_PATH: String = "user://tuning_overrides.json"
const POLL_SECONDS: float = 1.0

## Where the base files live; tests point this at fixtures.
var data_dir: String = TuningSet.DATA_DIR
var overrides_path: String = OVERRIDES_PATH
## Every domain must have a file; tests turn this off to load small fixtures.
var require_all_domains: bool = true
var current: TuningSet = TuningSet.new()
var profile: String = ""
var last_errors: Array[String] = []

var _bundle: Dictionary = {}
var _dev_overrides: Dictionary = {}
var _pending: TuningSet = null
var _poll_timer: Timer = null
var _stamps: Dictionary = {}


#region Loading

## Loads the server's full table. Returns false (and fills last_errors) if it is invalid.
func load_server(profile_name: String = "") -> bool:
	profile = profile_name
	var built: TuningSet = _build_server_set()
	if built == null:
		return false
	current = built
	_stamps = _file_stamps()
	_push_native()
	return true


## Loads the client table only.
func load_client(path: String = TuningSet.CLIENT_TABLE) -> bool:
	var built: TuningSet = TuningSet.new()
	last_errors = built.load_client_table(path)
	if not last_errors.is_empty():
		_report_errors()
		return false
	current = built
	return true


## NET-14's server data bundle: an overlay applied above the profile.
func set_bundle(overlay: Dictionary) -> Array[String]:
	var previous: Dictionary = _bundle
	_bundle = overlay
	var built: TuningSet = _build_server_set()
	if built == null:
		_bundle = previous
		return last_errors
	_swap(built)
	return [] as Array[String]


## A dev override (FND-08's console). Takes effect immediately.
func set_dev_override(key: String, value: Variant) -> Array[String]:
	var previous: Dictionary = _dev_overrides.duplicate()
	_dev_overrides[key] = {"value": value}
	var built: TuningSet = _build_server_set()
	if built == null:
		_dev_overrides = previous
		return last_errors
	_swap(built)
	return [] as Array[String]


## FND-08's `tuning reload`: rebuilds from the files now and swaps it in; the errors, if refused.
func reload_now() -> Array[String]:
	var built: TuningSet = _build_server_set()
	if built == null:
		return last_errors
	_stamps = _file_stamps()
	_swap(built)
	return [] as Array[String]


## Drops every dev override set through set_dev_override() and rebuilds.
func clear_dev_overrides() -> void:
	_dev_overrides.clear()
	var built: TuningSet = _build_server_set()
	if built != null:
		_swap(built)


func _build_server_set() -> TuningSet:
	var built: TuningSet = TuningSet.new()
	last_errors = built.load_directory(data_dir, require_all_domains)
	if last_errors.is_empty() and not profile.is_empty():
		last_errors = built.apply_profile_directory(TuningSet.PROFILES_DIR.path_join(profile))
	if last_errors.is_empty() and not _bundle.is_empty():
		last_errors = built.apply_overlay(_bundle, "bundle")
	if last_errors.is_empty():
		var file_overrides: Dictionary = _read_overrides_file()
		file_overrides.merge(_dev_overrides, true)
		if not file_overrides.is_empty():
			last_errors = built.apply_overlay(file_overrides, "dev")
	if not last_errors.is_empty():
		_report_errors()
		return null
	return built


func _read_overrides_file() -> Dictionary:
	if overrides_path.is_empty() or not FileAccess.file_exists(overrides_path):
		return {}
	var errors: Array[String] = []
	var parsed: Variant = TuningSet.read_json(overrides_path, errors)
	if parsed is Dictionary:
		var overrides: Dictionary = parsed
		return Variants.dict(overrides.get("keys", overrides))
	last_errors.append_array(errors)
	return {}


func _report_errors() -> void:
	for error: String in last_errors:
		push_error("Tuning: " + error)

#endregion

#region Hot reload

## Starts polling the tuning files. Callers pass allowed = false in release builds, and the
## poller is then never created.
func enable_hot_reload(allowed: bool) -> void:
	if not allowed or _poll_timer != null:
		return
	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_SECONDS
	_poll_timer.timeout.connect(poll_files)
	add_child(_poll_timer)
	_poll_timer.start()


func is_polling() -> bool:
	return _poll_timer != null


## Checks the files' contents (by MD5: file times only have one-second resolution).
## A valid change is staged for the next tick boundary.
func poll_files() -> void:
	var stamps: Dictionary = _file_stamps()
	if stamps == _stamps:
		return
	_stamps = stamps
	var built: TuningSet = _build_server_set()
	if built == null:
		Log.warn("tuning reload rejected; keeping the current values")
		return
	_pending = built


func has_pending() -> bool:
	return _pending != null


## Called by the simulation at each tick boundary (NET-01). Swaps in a staged reload.
func on_tick_boundary() -> void:
	if _pending == null:
		return
	var staged: TuningSet = _pending
	_pending = null
	_swap(staged)


func _swap(built: TuningSet) -> void:
	var changed: PackedStringArray = built.changed_keys(current)
	current = built
	_push_native()
	if not changed.is_empty():
		Log.info("tuning changed: %s" % ", ".join(changed))
		tuning_changed.emit(changed)


func _file_stamps() -> Dictionary:
	var stamps: Dictionary = {}
	var dirs: Array[String] = [data_dir]
	if not profile.is_empty():
		dirs.append(TuningSet.PROFILES_DIR.path_join(profile))
	for dir: String in dirs:
		for file: String in DirAccess.get_files_at(dir):
			if file.get_extension() == "json":
				var path: String = dir.path_join(file)
				stamps[path] = FileAccess.get_md5(path)
	if FileAccess.file_exists(overrides_path):
		stamps[overrides_path] = FileAccess.get_md5(overrides_path)
	return stamps

#endregion

#region Native mirror

## Pushes the effective table to the native core (LbTuning, FND-02), which reads by key and
## never opens files. Skipped until the extension provides LbTuning.
func _push_native() -> void:
	if not ClassDB.class_exists(&"LbTuning"):
		return
	var values: Dictionary = {}
	for key: Variant in current.entries.keys():
		values[key] = Variants.dict(current.entries[key])["value"]
	var mirrored: bool = ClassDB.class_call_static(&"LbTuning", &"set_values", values)
	if not mirrored:
		push_error("Tuning: the native mirror rejected the table")

#endregion

#region Typed access (see TuningSet)

func f(key: StringName) -> float:
	return current.f(key)


func i(key: StringName) -> int:
	return current.i(key)


func b(key: StringName) -> bool:
	return current.b(key)


func s(key: StringName) -> String:
	return current.s(key)


func list_f(key: StringName) -> Array[float]:
	return current.list_f(key)


func list_i(key: StringName) -> Array[int]:
	return current.list_i(key)


func list_s(key: StringName) -> Array[String]:
	return current.list_s(key)


func range_f(key: StringName) -> Vector2:
	return current.range_f(key)


func by_ring(key: StringName, ring: int) -> float:
	return current.by_ring(key, ring)


func by_crew(key: StringName, crew_count: int) -> float:
	return current.by_crew(key, crew_count)


func table(key: StringName) -> Dictionary:
	return current.table(key)


func ppm(key: StringName) -> int:
	return current.ppm(key)


func ticks(key: StringName) -> int:
	return current.ticks(key)


func content_hash(visibility: String = "") -> String:
	return current.content_hash(visibility)


## The layer a key's effective value came from: base, profile, bundle or dev.
func layer_of(key: StringName) -> String:
	return str(current.layer_of.get(String(key), ""))

#endregion
