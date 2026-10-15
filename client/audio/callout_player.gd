class_name CalloutPlayer
extends RefCounted
## SND-11: plays each callout record the server sent (GDD §15.5): SND-13's recorded frames for the
## line, voice and band, each kept frame decoded and each dropped one concealed, as SND-07 does for
## live voice, then placed at the record's apparent position on the Callouts group (dry or on a phone
## line: unplaced). The breath-cloud is not shown for others. UI-03 captions it from the same record:
## its words (a word that lost too many frames shows as a gap), band and voice, and its direction.

## The client's mixer (SND-04), or null (headless: nothing plays, the captions still come).
var mixer: SpatialMixer = null
## (record, text_key, word_shares, direction or null, duration_s) for UI-03.
var on_caption: Callable = Callable()
var played: int = 0


## Drains the connection's records; `listener` is where the ears are (tiles).
func tick(connection: ClientConnection, listener: Vector2) -> void:
	if connection == null:
		return
	while not connection.callouts.is_empty():
		var r: CalloutRecord = connection.callouts.pop_front()
		play(r, listener)


func play(r: CalloutRecord, listener: Vector2) -> void:
	var voice_id: String = voice_id_of(r.voice)
	var line: String = VoiceManifest.line_of_wire(r.line)
	if voice_id.is_empty() or line.is_empty():
		return
	var flat: bool = (r.flags & (CalloutRecord.FLAG_DRY | CalloutRecord.FLAG_TELEPHONE)) != 0
	if mixer != null:
		var pcm: PackedFloat32Array = decode(VoiceBank.callout(voice_id, line, CalloutLines.form_of(line, r.band)), r.mask)
		if not pcm.is_empty():
			var bus: String = "Muffled" if (r.flags & CalloutRecord.FLAG_MUFFLED) != 0 else "Callouts"
			mixer.add(pcm, 48000.0, r.apparent, float(r.gain_db), bus, false, not flat)
	played += 1
	if on_caption.is_valid():
		var key: String = CalloutLines.text_key(line)
		var words: int = UiText.text(key).split(" ", false).size()
		var direction: Variant = null if flat else r.apparent - listener
		on_caption.call(r, key, CalloutLines.word_shares(r.mask, words), direction, r.mask.size() * VoicePackets.FRAME_S)


## The line's PCM under a mask: kept frames decoded, dropped ones concealed (Opus's own concealment).
static func decode(file: PackedByteArray, mask: PackedByteArray) -> PackedFloat32Array:
	var parsed: Dictionary = VoiceBank.parse(file)
	if parsed.is_empty():
		return PackedFloat32Array()
	var frames: Array[PackedByteArray] = []
	frames.assign(Variants.array(parsed["frames"]))
	var dec: LbOpusDecoder = LbOpusDecoder.new()
	var out: PackedFloat32Array = PackedFloat32Array()
	for i: int in frames.size():
		var kept: bool = i >= mask.size() or mask[i] != 0
		out.append_array(dec.decode(frames[i]) if kept else dec.conceal())
	var skip: int = int(Variants.number(parsed.get("pre_skip", 0)))
	return out.slice(mini(skip, out.size()))


static func voice_id_of(wire: int) -> String:
	var ids: PackedStringArray = VoiceManifest.voice_ids()
	return ids[wire] if wire >= 0 and wire < ids.size() else ""
