class_name CaptionLayer
extends CanvasLayer
## UI-03: the captions, their arcs and the subtitles, on CloseupManager.CAPTIONS_LAYER: above UI-02's
## close-ups (the sounds go on behind them) and below the menus. Fed by the client's sound players
## (wire()); UI-06 sets the options and the text size.

var system: CaptionSystem = CaptionSystem.new()
var captions: CaptionView = CaptionView.new()
var subtitles: SubtitleView = SubtitleView.new()


func _init() -> void:
	layer = CloseupManager.CAPTIONS_LAYER
	captions.system = system
	subtitles.system = system
	add_child(subtitles)
	add_child(captions)


## Every sound the client plays reaches the captions here, and nothing else does.
func wire(events: EventPlayer, voices: VoicePlayback, beds: AmbientBeds, deafness: Deafness, knocks: KnocksPlayer,
		listener: Callable) -> void:
	if events != null:
		events.played.connect(func(record: AudioRecord, direction: Variant) -> void: system.on_played(record, direction, _now()))
		events.sputter_started.connect(func(offset: Vector2) -> void: system.on_sputter(offset, _now()))
	if voices != null:
		voices.heard.connect(func(stream: int, kind: String, band: int, header: Dictionary) -> void:
			_on_voice(stream, kind, band, header, listener))
	if beds != null:
		beds.silence_caption.connect(func(l: StringName, start: bool) -> void: system.on_silence(l, start, _now()))
	if deafness != null:
		deafness.ringing.connect(func(start: bool) -> void: system.on_ringing(start, _now()))
	if knocks != null:
		knocks.caption.connect(func() -> void: system.on_knocks(_now()))


func _on_voice(stream: int, kind: String, band: int, header: Dictionary, listener: Callable) -> void:
	var at: Vector2 = listener.call()
	system.on_voice(stream, kind, band, header, at, _now())


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	subtitles.refresh(now)
	captions.bottom_offset = subtitles.used_height()
	captions.refresh(now)
