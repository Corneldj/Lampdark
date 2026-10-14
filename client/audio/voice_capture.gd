class_name VoiceCapture
extends RefCounted
## SND-05: when the microphone may be open, and the clean frames it gives (GDD §15.5 step 1, §15.6).
## The device opens only while the mic mode allows it (Use; SND-10's choice), voice is live (a
## lobby, a run, the Pithead and Lamp Check channel) and a device is present; leaving any of these
## closes it on the same tick. A device that vanishes reads as silent (no frames) and as the
## no-device state, and the client looks again every voice.device_poll_s; the first device to appear
## opens, flagging needs_calibration when it is not the one calibrated (SND-06, MOD-04). While open,
## the game's final mix is tapped from the Master bus as the echo canceller's far end. The backend is
## voice.apm_backend, falling back WebRTC -> SpeexDSP -> none; none forces Mute (GDD §15.13).
## Nothing here keeps, logs or writes audio: frames leave only by frame_ready.

## One 20 ms frame of 48 kHz mono, stamped on Time.get_ticks_usec().
signal frame_ready(pcm: PackedFloat32Array, ticks_usec: int)
signal state_changed(state: int)

enum State { CLOSED, OPEN, NO_DEVICE }

const BACKENDS: Array[String] = ["webrtc", "speex", "none"]

var native: LbVoiceCapture = LbVoiceCapture.new()
## The player's mode; the client points this at its MicMode (SND-10). Unset: Mute.
var mic_mode: Callable = func() -> int: return MicMode.Mode.MUTE
## Set by the client: in a lobby, a run, or the Pithead and Lamp Check channel.
var voice_live: bool = false
## The backend running after the fallback chain ("none" when neither processor starts).
var backend: String = ""
var state: State = State.CLOSED
var needs_calibration: bool = false
## The device the last calibration line was taken on (SND-06 sets it after the roll call).
var calibrated_device: String = ""
## Off in tests that have no audio server worth tapping.
var tap_far_end: bool = true
var _next_poll_usec: int = 0
var _tap: AudioEffectCapture = null


## `driver`: "device" (real microphones), "null" or, in debug builds, "fake" (tests).
func _init(driver: String = "device") -> void:
	native.use_driver(driver)
	backend = _configure()


func _configure() -> String:
	var wanted: String = Tuning.s(&"voice.apm_backend")
	var start: int = maxi(0, BACKENDS.find(wanted))
	for i: int in range(start, BACKENDS.size()):
		var name: String = BACKENDS[i]
		if native.configure(name, Tuning.s(&"voice.noise_suppression_level"), Tuning.f(&"voice.speex_echo_tail_ms"),
				PackedFloat32Array(Tuning.current.list_f(&"voice.speex_noise_suppress_db"))):
			if name != wanted:
				Log.warn("voice: the %s backend failed; using %s" % [wanted, name])
			return name
	return "none"


## The mode in force: backend none forces Mute on this platform.
func effective_mode() -> int:
	if backend == "none":
		return MicMode.Mode.MUTE
	return int(Variants.number(mic_mode.call()))


func may_open() -> bool:
	return voice_live and effective_mode() == MicMode.Mode.USE


## SND-10's label: no device (as Mute and speech-impairment show the same).
func no_device() -> bool:
	return state == State.NO_DEVICE


## Once a frame: applies the open and close rules, feeds the far end and hands out the frames.
func tick(now_usec: int) -> void:
	if not may_open():
		if state != State.CLOSED:
			_close()
			_set_state(State.CLOSED)
		return
	if state == State.OPEN and native.is_lost():
		_close()
		_set_state(State.NO_DEVICE)
		_next_poll_usec = now_usec + _poll_usec()
		return
	if state != State.OPEN:
		if state == State.CLOSED or now_usec >= _next_poll_usec:
			_next_poll_usec = now_usec + _poll_usec()
			_try_open()
		return
	_feed_far_end()
	for raw: Variant in native.pop_frames():
		var item: Array = raw
		frame_ready.emit(item[0], int(Variants.number(item[1])))


## SND-06, after a roll call: this device is the calibrated one.
func mark_calibrated() -> void:
	calibrated_device = native.device_id()
	needs_calibration = false


func close() -> void:
	voice_live = false
	if state != State.CLOSED:
		_close()
		_set_state(State.CLOSED)


func _try_open() -> void:
	if native.devices().is_empty() or not native.open(""):
		_set_state(State.NO_DEVICE)
		return
	var device: String = native.device_id()
	if not calibrated_device.is_empty() and device != calibrated_device:
		needs_calibration = true
	_start_tap()
	_set_state(State.OPEN)


func _close() -> void:
	native.close()
	_stop_tap()


func _set_state(s: State) -> void:
	if s != state:
		state = s
		state_changed.emit(s)


func _poll_usec() -> int:
	return int(Tuning.f(&"voice.device_poll_s") * 1000000.0)


## The final mix, after the Master limiter: what leaves the speakers.
func _start_tap() -> void:
	if not tap_far_end or _tap != null:
		return
	_tap = AudioEffectCapture.new()
	_tap.buffer_length = Tuning.f(&"voice.far_end_buffer_s")
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), _tap)


func _stop_tap() -> void:
	if _tap == null:
		return
	var master: int = AudioServer.get_bus_index("Master")
	for i: int in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) == _tap:
			AudioServer.remove_bus_effect(master, i)
			break
	_tap.clear_buffer()
	_tap = null


func _feed_far_end() -> void:
	if _tap == null:
		return
	var n: int = _tap.get_frames_available()
	if n > 0:
		native.push_far_end(_tap.get_buffer(n), int(AudioServer.get_mix_rate()))
