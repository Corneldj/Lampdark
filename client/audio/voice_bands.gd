class_name VoiceBands
extends RefCounted
## SND-06: the own voice's loudness band, frame by frame (GDD §15.5 step 2): silent, whisper, talk,
## shout or scream, read from SND-05's clean frames by the native band meter against this device's
## calibrated thresholds (defaults until the roll call). Voice activation opens at whisper;
## push-to-talk, when chosen, gates sending only: the band is still measured, so the breath-cloud
## shows silent while it is released. The band (0-4) is SND-07's 3-bit field.

signal band_changed(band: int)

enum Band { SILENT, WHISPER, TALK, SHOUT, SCREAM }

var meter: LbBandMeter = LbBandMeter.new()
var band: int = Band.SILENT
## The push-to-talk option (default off: voice activation).
var push_to_talk: bool = false
## Push-to-talk held this tick (ClientMain, from the input router).
var ptt_held: bool = false


func _init(thresholds: PackedFloat32Array = PackedFloat32Array()) -> void:
	var frame_ms: float = Tuning.f(&"voice.frame_ms")
	meter.configure(Tuning.f(&"voice.speech_band_low_hz"), Tuning.f(&"voice.speech_band_high_hz"),
		maxi(1, roundi(Tuning.f(&"voice.band_median_ms") / frame_ms)),
		maxi(1, roundi(Tuning.f(&"voice.band_hysteresis_s") * 1000.0 / frame_ms)),
		thresholds if thresholds.size() == 4 else defaults())


## The design's default thresholds, whisper to scream (Gameplay A.3).
static func defaults() -> PackedFloat32Array:
	return PackedFloat32Array([Tuning.f(&"voice.threshold_whisper_dbfs"), Tuning.f(&"voice.threshold_talk_dbfs"),
		Tuning.f(&"voice.threshold_shout_dbfs"), Tuning.f(&"voice.threshold_scream_dbfs")])


## A device's thresholds (a calibration, or the defaults for a new device).
func set_thresholds(thresholds: PackedFloat32Array) -> void:
	meter.set_thresholds(thresholds)


## One 20 ms frame from SND-05; returns the band.
func push(pcm: PackedFloat32Array) -> int:
	var b: int = int(meter.push(pcm))
	if b != band:
		band = b
		band_changed.emit(b)
	return b


## Whether this frame goes out (SND-07): above silent, and push-to-talk held when it is chosen.
func sending() -> bool:
	return band >= Band.WHISPER and (not push_to_talk or ptt_held)


## The microphone closed or went away: silent.
func reset() -> void:
	meter.reset()
	if band != Band.SILENT:
		band = Band.SILENT
		band_changed.emit(band)
