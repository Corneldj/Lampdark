class_name MicMode
extends RefCounted
## SND-10: the player's microphone choice and what follows from it (Gameplay §6.3, GDD §15.6).
## USE, MUTE or SPEECH_IMPAIRMENT; voice is enabled only in USE with a device present, and every
## other case shows one crew-list label, 'Mute (callouts and taps only)', never anything about who
## is speaking. Until the player has chosen under the current notice version the mode is MUTE, so
## the microphone cannot open. Each choice appends {choice, notice version, UTC time, build} to
## an append-only log on this PC, and to a queue the backend takes once STM-10 exists. The client
## owns one (ClientMain.mic_mode); UI-05's options call set_mode().

signal label_changed(muted: bool)

enum Mode { USE, MUTE, SPEECH_IMPAIRMENT }

const MODE_NAMES: Array[String] = ["use", "mute", "speech_impairment"]
const LOG_PATH: String = "user://privacy/mic_consent.jsonl"
const QUEUE_PATH: String = "user://privacy/mic_consent_queue.jsonl"
const VERSION_PATH: String = "res://data/text/privacy/version.json"
const NOTICE_PATH: String = "res://data/text/privacy/mic_notice.%s.json"

var mode: Mode = Mode.MUTE
## From SND-05's capture: false while it has no input device.
var device_present: bool = true
var notice_version: int = 0
var log_path: String = LOG_PATH
var queue_path: String = QUEUE_PATH
var _chosen_version: int = -1
var _label: bool = true


func _init(log_file: String = LOG_PATH, queue_file: String = QUEUE_PATH, version_file: String = VERSION_PATH) -> void:
	log_path = log_file
	queue_path = queue_file
	notice_version = read_version(version_file)
	_load()
	_label = show_mute_label()


static func read_version(path: String) -> int:
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return int(Variants.number(doc.get("version", 0)))


## The notice text for `lang`, falling back to English.
static func notice(lang: String = "en") -> Dictionary:
	var path: String = NOTICE_PATH % lang
	if not FileAccess.file_exists(path):
		path = NOTICE_PATH % "en"
	return Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(path)))


## The last choice under the current notice decides the mode; none (or an older notice): MUTE.
func _load() -> void:
	mode = Mode.MUTE
	_chosen_version = -1
	for entry: Dictionary in entries():
		var name: String = str(entry.get("choice", ""))
		var version: int = int(Variants.number(entry.get("notice_version", -1)))
		if MODE_NAMES.has(name) and version == notice_version:
			mode = MODE_NAMES.find(name) as Mode
			_chosen_version = version
	if _chosen_version < 0:
		mode = Mode.MUTE


## The screen must be shown: no choice yet under this notice version (a revised notice asks again).
func needs_choice() -> bool:
	return _chosen_version != notice_version


## No choice was ever logged: the first launch (the comfort step comes first).
func first_launch() -> bool:
	return entries().is_empty()


func voice_enabled() -> bool:
	return mode == Mode.USE and device_present


## Mute, the speech-impairment option and no device all show the same label.
func show_mute_label() -> bool:
	return not voice_enabled()


## The player's choice, from the permission screen or UI-05's options: logged, then applied.
func set_mode(m: Mode) -> void:
	var entry: Dictionary = {"choice": MODE_NAMES[m], "notice_version": notice_version,
		"utc": Time.get_datetime_string_from_system(true) + "Z", "build": Protocol.build_id()}
	_append(log_path, entry)
	_append(queue_path, entry)
	mode = m
	_chosen_version = notice_version
	_update_label()


## From SND-05: whether an input device is present.
func set_device_present(present: bool) -> void:
	device_present = present
	_update_label()


func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(log_path):
		return out
	for line: String in FileAccess.get_file_as_string(log_path).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
	return out


func _update_label() -> void:
	var now: bool = show_mute_label()
	if now != _label:
		_label = now
		label_changed.emit(now)


## Append-only: entries are added, never rewritten or removed.
static func _append(path: String, entry: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		push_warning("MicMode: cannot write %s" % path)
		return
	f.seek_end()
	f.store_line(JSON.stringify(entry))
	f.close()
