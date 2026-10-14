class_name Calibration
extends RefCounted
## SND-06: the roll call's calibration (GDD §15.5; MOD-04 drives it). Three takes of 'Lamp <n>,
## all right', normal, whispered and called: each frame's speech-band level above the floor
## (voice.calibration_floor_dbfs) counts, and a take's median sets its register. Talk lands
## voice.calibration_talk_fraction of the way from the whispered median to the normal one, shout
## midway between normal and called, scream voice.calibration_scream_offset_db above called;
## whisper keeps its default. Each stays within voice.calibration_clamp_db of its default. Two
## warnings: output to speakers (the option, or SND-05's echo canceller hearing the game) and
## automatic gain (called less than voice.agc_warning_margin_db above normal). Only thresholds, the
## date and the warnings are kept, on this PC, per input device: calibration audio is never stored
## or sent.

enum Kind { NORMAL, WHISPER, CALLED }
enum Result { PASS, RETRY, CLAMPED }

const PATH: String = "user://voice/calibration.json"
const WARN_SPEAKERS: String = "speakers"
const WARN_AGC: String = "automatic_gain"

var path: String = PATH
## The output option is speakers (SND-04's AudioOptions), set by the client.
var speakers_setting: bool = false
## Kind -> median dBFS of the takes that passed.
var medians: Dictionary = {}
var echo_heard: bool = false
var _meter: LbBandMeter = LbBandMeter.new()
var _taking: int = -1
var _levels: Array[float] = []


func _init(store_path: String = PATH) -> void:
	path = store_path
	var t: PackedFloat32Array = VoiceBands.defaults()
	_meter.configure(Tuning.f(&"voice.speech_band_low_hz"), Tuning.f(&"voice.speech_band_high_hz"), 1, 1, t)


## Starts collecting one register.
func capture_register(kind: Kind) -> void:
	_taking = kind
	_levels.clear()
	_meter.reset()


## One clean 20 ms frame while the player speaks; `echo_return_loss_db` from SND-05's capture stats.
func feed(pcm: PackedFloat32Array, echo_return_loss_db: float = -1.0) -> void:
	if _taking < 0:
		return
	_meter.push(pcm)
	var level: float = _meter.level_dbfs()
	if level > Tuning.f(&"voice.calibration_floor_dbfs"):
		_levels.append(level)
	if echo_return_loss_db >= 0.0 and echo_return_loss_db < Tuning.f(&"voice.speaker_warning_erl_db"):
		echo_heard = true


## Ends the take: {result: PASS or RETRY, median_dbfs}. RETRY for too little speech, or a median out
## of order with the takes already passed (whispered >= normal, or normal >= called).
func end_register() -> Dictionary:
	var kind: int = _taking
	_taking = -1
	var speech_s: float = _levels.size() * Tuning.f(&"voice.frame_ms") / 1000.0
	if kind < 0 or speech_s < Tuning.f(&"voice.calibration_min_speech_s"):
		return {"result": Result.RETRY, "median_dbfs": NAN}
	var sorted: Array[float] = _levels.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	var trial: Dictionary = medians.duplicate()
	trial[kind] = median
	if not in_order(trial):
		return {"result": Result.RETRY, "median_dbfs": median}
	medians = trial
	return {"result": Result.PASS, "median_dbfs": median}


static func in_order(m: Dictionary) -> bool:
	if m.has(Kind.WHISPER) and m.has(Kind.NORMAL) and float(Variants.number(m[Kind.WHISPER])) >= float(Variants.number(m[Kind.NORMAL])):
		return false
	if m.has(Kind.NORMAL) and m.has(Kind.CALLED) and float(Variants.number(m[Kind.NORMAL])) >= float(Variants.number(m[Kind.CALLED])):
		return false
	if m.has(Kind.WHISPER) and m.has(Kind.CALLED) and float(Variants.number(m[Kind.WHISPER])) >= float(Variants.number(m[Kind.CALLED])):
		return false
	return true


## The thresholds from three medians (whispered, normal, called), before clamping.
static func formula(whispered: float, normal: float, called: float) -> PackedFloat32Array:
	return PackedFloat32Array([Tuning.f(&"voice.threshold_whisper_dbfs"),
		whispered + Tuning.f(&"voice.calibration_talk_fraction") * (normal - whispered),
		(normal + called) / 2.0,
		called + Tuning.f(&"voice.calibration_scream_offset_db")])


## All three takes passed: computes, clamps, warns and stores for `device_id`. {result: PASS or
## CLAMPED (or RETRY if a take is missing), thresholds, clamped: [bool x4], warnings}.
func finish(device_id: String) -> Dictionary:
	for k: int in [Kind.WHISPER, Kind.NORMAL, Kind.CALLED]:
		if not medians.has(k):
			return {"result": Result.RETRY, "thresholds": VoiceBands.defaults(), "clamped": [], "warnings": []}
	var normal: float = float(Variants.number(medians[Kind.NORMAL]))
	var called: float = float(Variants.number(medians[Kind.CALLED]))
	var raw: PackedFloat32Array = formula(float(Variants.number(medians[Kind.WHISPER])), normal, called)
	var defaults: PackedFloat32Array = VoiceBands.defaults()
	var clamp_db: float = Tuning.f(&"voice.calibration_clamp_db")
	var out: PackedFloat32Array = PackedFloat32Array()
	var clamped: Array[bool] = []
	for i: int in 4:
		var v: float = clampf(raw[i], defaults[i] - clamp_db, defaults[i] + clamp_db)
		clamped.append(not is_equal_approx(v, raw[i]))
		out.append(v)
	var warnings: Array[String] = []
	if speakers_setting or echo_heard:
		warnings.append(WARN_SPEAKERS)
	if called - normal < Tuning.f(&"voice.agc_warning_margin_db"):
		warnings.append(WARN_AGC)
	store(device_id, out, warnings)
	return {"result": Result.CLAMPED if clamped.has(true) else Result.PASS, "thresholds": out, "clamped": clamped,
		"warnings": warnings}


## Thresholds, the date and the warnings for one device, and nothing else.
func store(device_id: String, thresholds: PackedFloat32Array, warnings: Array[String]) -> void:
	var all: Dictionary = _read(path)
	all[device_id] = {"thresholds": Array(thresholds), "date": Time.get_date_string_from_system(true), "warnings": warnings}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Calibration: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(all, "\t"))
	f.close()


static func is_calibrated(device_id: String, store_path: String = PATH) -> bool:
	return _read(store_path).has(device_id)


## A calibrated device's thresholds, or the defaults for a new one.
static func thresholds_for(device_id: String, store_path: String = PATH) -> PackedFloat32Array:
	var entry: Dictionary = Variants.dict(_read(store_path).get(device_id, {}))
	var t: Array = Variants.array(entry.get("thresholds", []))
	if t.size() != 4:
		return VoiceBands.defaults()
	return PackedFloat32Array(t)


static func _read(store_path: String) -> Dictionary:
	if not FileAccess.file_exists(store_path):
		return {}
	return Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(store_path)))
