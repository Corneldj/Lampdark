class_name KnocksPlayer
extends Node
## SND-15 (Gameplay §6.8, §11.2, A.3): the client's knocks. Each KNOCKS message from the server (it
## carries nothing: no position, no name, no cause) plays voice.knock_count knocks
## voice.knock_interval_s apart, centred and unspatialised on the Knocks bus, which no option and no
## mask touches. A second fall's set queues after the first set ends, so two falls are two sets.
## While deafened they play the Deafened record's dip down, like the rest of game sound. `caption`
## raises UI-03's '[three knocks]' once per set, with no direction.

signal caption()
## Each knock as it plays (tests, and UI-03 if it wants them).
signal knocked()

var deafness: Deafness = null
## Sets waiting behind the one playing.
var queued: int = 0
var knocks_played: int = 0
var _left: int = 0
var _next_s: float = 0.0
var _clock_s: float = 0.0
var _stream: AudioStreamWAV = null


func _init(deaf: Deafness = null) -> void:
	deafness = deaf


## One KNOCKS message.
func enqueue() -> void:
	queued += 1
	if _left == 0:
		_next_s = maxf(_next_s, _clock_s)
		_start_set()


func playing() -> bool:
	return _left > 0


func _process(delta: float) -> void:
	advance(delta)


func advance(seconds: float) -> void:
	_clock_s += seconds
	while _left > 0 and _clock_s >= _next_s - 1e-9:
		_knock()
		_left -= 1
		_next_s += Tuning.f(&"voice.knock_interval_s")
		if _left == 0 and queued > 0:
			_start_set()


func _start_set() -> void:
	if queued <= 0:
		return
	queued -= 1
	_left = roundi(Tuning.f(&"voice.knock_count"))
	caption.emit()
	advance(0.0)


func _knock() -> void:
	knocks_played += 1
	knocked.emit()
	if not is_inside_tree():
		return
	if _stream == null:
		_stream = SampleBank.make("knock", 0.35, 151)
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = _stream
	player.bus = "Knocks"
	player.volume_db = -deafness.dip_db if deafness != null and deafness.deafened() else 0.0
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
