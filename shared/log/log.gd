class_name Log
## A small levelled logger with one sink per role (FND-03).
##
## The server writes to stdout and, with --log, to a file. The client writes to
## user://logs/client.log (and stdout in dev and QA). Boot configures it once.
## Release builds never log a seed or hidden state: use Log.dev() for those, which writes
## nothing in release.

enum Level { DEBUG, INFO, WARN, ERROR }

const LEVEL_NAMES: Dictionary = {
	"debug": Level.DEBUG, "info": Level.INFO, "warn": Level.WARN, "error": Level.ERROR,
}
const CLIENT_LOG_DIR: String = "user://logs"

static var _level: Level = Level.INFO
static var _stdout: bool = true
static var _file: FileAccess = null
static var _release: bool = false
static var _role: String = "boot"


static func configure(role: String, level_name: String, to_stdout: bool, file_path: String,
		release: bool) -> void:
	_role = role
	_level = LEVEL_NAMES.get(level_name, Level.INFO)
	_stdout = to_stdout
	_release = release
	close()
	if not file_path.is_empty():
		DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
		_file = FileAccess.open(file_path, FileAccess.WRITE)
		if _file == null:
			_emit(Level.WARN, "could not open log file %s" % file_path)


static func close() -> void:
	if _file != null:
		_file.flush()
		_file = null


static func debug(message: String) -> void:
	_emit(Level.DEBUG, message)


static func info(message: String) -> void:
	_emit(Level.INFO, message)


static func warn(message: String) -> void:
	_emit(Level.WARN, message)


static func error(message: String) -> void:
	_emit(Level.ERROR, message)


## Hidden state (seeds, truth): written in dev and QA only, never in release.
static func dev(message: String) -> void:
	if not _release:
		_emit(Level.DEBUG, message)


static func _emit(level: Level, message: String) -> void:
	if level < _level:
		return
	var tag: String = ["DEBUG", "INFO", "WARN", "ERROR"][level]
	var line: String = "%s [%s] %s: %s" % [Time.get_time_string_from_system(), tag, _role, message]
	if _stdout:
		if level >= Level.WARN:
			printerr(line)
		else:
			print(line)
	if _file != null:
		# Flushed per line, so a killed or crashed process keeps its log.
		_file.store_line(line)
		_file.flush()
