class_name CaptionSystem
extends RefCounted
## UI-03 (Gameplay §14.3, §9.2; GDD §14.5): the captions, built only from what the client played,
## so they never show what the player could not hear. Each played record (SND-03's
## EventPlayer.played, after every mask and loss) makes one line or freshens an identical one. Each
## voice stream (SND-07's VoicePlayback.heard) makes one line per utterance: '[voice]', or
## '[voice, broken]' once a frame is concealed, with the loudest band and the direction, never a
## word of speech. Bed layers (AmbientBeds) caption their start and end, deafness '[ringing]', the
## knocks and a guttering flame theirs. SND-11 hands in its callouts (words, band, voice). Recorded
## speech goes to the subtitles, which show with captions off.
##
## Nothing here reads the world or a server flag, so an illusion (the same record a real sound
## would be) captions exactly as the sound it copies. A line carries a text key, a band, a voice
## descriptor and a bearing: never a distance. Lines linger noise.caption_linger_s after their
## sound, the newest lowest, at most noise.caption_max_lines.

## One caption line. `bearing` is degrees clockwise from east on the screen, or null for none.
class Line:
	extends RefCounted
	var key: String = ""
	var text: String = ""
	var band: int = -1
	var voice_id: String = ""
	var bearing: Variant = null
	var kind: CaptionTable.Kind = CaptionTable.Kind.POSITIONAL
	var stream: int = -1
	var broken: bool = false
	var started_s: float = 0.0
	var ends_s: float = 0.0

	## The words shown: the caption, then its band and voice in brackets.
	func shown() -> String:
		var extra: PackedStringArray = PackedStringArray()
		if band >= 1:
			extra.append(UiText.text("caption.band.%d" % band))
		if not voice_id.is_empty():
			extra.append(UiText.text("caption.voice_of." + voice_id))
		var parts: PackedStringArray = PackedStringArray()
		for e: String in extra:
			if not e.is_empty():
				parts.append(e)
		return text if parts.is_empty() else "%s (%s)" % [text, ", ".join(parts)]

	## An identical repeat: the same words, and directed or not alike.
	func same_as(other: Line) -> bool:
		return shown() == other.shown() and kind == other.kind and (bearing == null) == (other.bearing == null)


## UI-06's options: captions (text), mono (direction-only arcs stay with text off) and subtitles.
var captions_on: bool = true
var arcs_only: bool = false
var subtitles_on: bool = true
var lines: Array[Line] = []
var subtitles: Array[Line] = []
## Every line added or freshened, for tests: {text (shown), bearing, key}.
var history: Array[Dictionary] = []


## SND-03: one record played, `direction` its apparent position from the listener (null: diffuse).
func on_played(record: AudioRecord, direction: Variant, now_s: float) -> void:
	if VisualEvents.is_visual(record.type):
		return
	var line: Line = Line.new()
	line.kind = CaptionTable.kind_of(record.type, record.flags)
	line.key = CaptionTable.key_of(record.type, record.flags)
	line.text = UiText.text(line.key)
	if line.text.is_empty():
		return
	if record.voice >= 0:
		line.voice_id = _voice_id(record.voice)
	if line.kind != CaptionTable.Kind.DIFFUSE and direction is Vector2:
		var d: Vector2 = direction
		line.bearing = bearing_of(d)
	_add(line, now_s, maxf(record.duration_s, 0.0))


## SND-07: one voice frame out of a stream's playout: kind "frame", "conceal", "smear" or "end";
## `header` LbVoicePlayout.header() (position, telephone, dry).
func on_voice(stream: int, kind: String, band: int, header: Dictionary, listener: Vector2, now_s: float) -> void:
	var line: Line = null
	for l: Line in lines:
		if l.stream == stream:
			line = l
	if kind == "end":
		if line != null:
			line.stream = -1
			line.ends_s = now_s + _linger()
		return
	if line == null:
		line = Line.new()
		line.kind = CaptionTable.Kind.VOICE
		line.stream = stream
		var on_line: bool = Variants.flag(header.get("telephone", false))
		line.key = "caption.voice.line" if on_line else "caption.voice"
		line.text = UiText.text(line.key)
		_push(line, now_s)
	line.band = maxi(line.band, band)
	if kind != "frame" and not line.broken and line.key == "caption.voice":
		line.broken = true
		line.key = "caption.voice.broken"
		line.text = UiText.text(line.key)
	var flat: bool = Variants.flag(header.get("telephone", false)) or Variants.flag(header.get("dry", false))
	var at: Variant = header.get("position", null)
	line.bearing = null
	if not flat and at is Vector2:
		var p: Vector2 = at
		line.bearing = bearing_of(p - listener)
	line.ends_s = now_s + _linger()


## SND-11: a callout heard. `text_key` its line (data/text/callouts), `word_shares` the share of each
## word's frames that arrived (voice.caption_word_min_frames or less shows as a gap), `band` 1-4,
## `voice_id` the character voice (SND-13's), `direction` from the listener or null (a phone line).
func on_callout(text_key: String, word_shares: PackedFloat32Array, band: int, voice_id: String, direction: Variant,
		duration_s: float, now_s: float) -> void:
	var line: Line = Line.new()
	line.kind = CaptionTable.Kind.CALLOUT
	line.key = text_key
	line.text = callout_words(UiText.text(text_key), word_shares)
	if line.text.is_empty():
		return
	line.band = band
	line.voice_id = voice_id
	if direction is Vector2:
		var d: Vector2 = direction
		line.bearing = bearing_of(d)
	_add(line, now_s, duration_s)


## A callout's words as heard: each word whose share of frames fell short shows as the gap mark.
static func callout_words(text: String, word_shares: PackedFloat32Array) -> String:
	var words: PackedStringArray = text.split(" ", false)
	var floor_share: float = Tuning.f(&"voice.caption_word_min_frames")
	var out: PackedStringArray = PackedStringArray()
	for i: int in words.size():
		var share: float = word_shares[i] if i < word_shares.size() else 1.0
		var shown: String = words[i] if share >= floor_share else UiText.text("caption.word_gap")
		if out.is_empty() or shown != out[out.size() - 1] or shown != UiText.text("caption.word_gap"):
			out.append(shown)
	return " ".join(out)


## SND-03's ambient beds: a layer started or stopped.
func on_silence(layer: StringName, start: bool, now_s: float) -> void:
	var line: Line = Line.new()
	line.kind = CaptionTable.Kind.SILENCE
	line.key = "caption.silence.%s.%s" % [layer, "start" if start else "stop"]
	line.text = UiText.text(line.key)
	if not line.text.is_empty():
		_add(line, now_s, 0.0)


## SND-04: the ringing, from its start until it fades.
func on_ringing(start: bool, now_s: float) -> void:
	for l: Line in lines:
		if l.key == "caption.ringing":
			l.ends_s = INF if start else now_s + _linger()
			return
	if start:
		var line: Line = Line.new()
		line.key = "caption.ringing"
		line.text = UiText.text(line.key)
		line.kind = CaptionTable.Kind.DIFFUSE
		_push(line, now_s)
		line.ends_s = INF


## SND-15: a fall's three knocks, from nowhere in particular.
func on_knocks(now_s: float) -> void:
	_simple("caption.knocks", null, now_s, 1.5)


## VIS-08: a flame began to gutter where the client hears it (the own lamp at the listener: no arc).
func on_sputter(offset: Vector2, now_s: float) -> void:
	_simple("caption.sputter", bearing_of(offset) if offset.length() > 0.5 else null, now_s, 0.5)


## Recorded speech (the lampman, the cold open, the roll call): its line, for `duration_s`.
func subtitle(text_key: String, duration_s: float, now_s: float) -> void:
	var line: Line = Line.new()
	line.key = text_key
	line.text = UiText.text(text_key)
	if line.text.is_empty():
		return
	line.started_s = now_s
	line.ends_s = now_s + duration_s + _linger()
	subtitles.append(line)


func tick(now_s: float) -> void:
	lines = lines.filter(func(l: Line) -> bool: return l.stream >= 0 or l.ends_s > now_s)
	subtitles = subtitles.filter(func(l: Line) -> bool: return l.ends_s > now_s)


## What the view draws now, oldest first: {text ("" in arc-only mode), bearing (or null)}.
func visible_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Line in lines:
		if captions_on:
			out.append({"text": l.shown(), "bearing": l.bearing})
		elif arcs_only and l.bearing != null:
			out.append({"text": "", "bearing": l.bearing})
	return out


func visible_subtitles() -> Array[String]:
	var out: Array[String] = []
	if subtitles_on:
		for l: Line in subtitles:
			out.append(l.text)
	return out


## The bearing of an offset, degrees clockwise from east on the north-up screen (y down).
static func bearing_of(offset: Vector2) -> float:
	return fposmod(rad_to_deg(offset.angle()), 360.0)


func _simple(key: String, bearing: Variant, now_s: float, duration_s: float) -> void:
	var line: Line = Line.new()
	line.key = key
	line.text = UiText.text(key)
	line.bearing = bearing
	if not line.text.is_empty():
		_add(line, now_s, duration_s)


## A new line, or a freshened identical one (its direction updated to the newest sound's).
func _add(line: Line, now_s: float, duration_s: float) -> void:
	line.ends_s = now_s + duration_s + _linger()
	for l: Line in lines:
		if l.stream < 0 and l.same_as(line):
			l.ends_s = maxf(l.ends_s, line.ends_s)
			l.bearing = line.bearing
			_note(line)
			return
	_push(line, now_s)


func _push(line: Line, now_s: float) -> void:
	line.started_s = now_s
	lines.append(line)
	var cap: int = maxi(1, Tuning.i(&"noise.caption_max_lines"))
	while lines.size() > cap:
		lines.pop_front()
	_note(line)


func _note(line: Line) -> void:
	history.append({"text": line.shown(), "bearing": line.bearing, "key": line.key})


func _linger() -> float:
	return Tuning.f(&"noise.caption_linger_s")


static func _voice_id(wire: int) -> String:
	var ids: PackedStringArray = VoiceManifest.voice_ids()
	return ids[wire] if wire >= 0 and wire < ids.size() else ""
