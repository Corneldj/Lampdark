class_name VoicePlayback
extends RefCounted
## SND-07: other miners' voices, played (GDD §15.5 step 5, §14.2). Each stream (one speaker's
## utterance, as the server addressed it to this client) gets its own LbVoicePlayout: a jitter
## buffer, Opus decoding, concealment or a room-tone smear for lost frames, and the band cap. Its
## samples go to one mixer stream at the header's apparent position and gain: the Muffled bus when
## muffled; dry and telephone streams unspatialised on the Voice bus. A new stream starts from the
## jitter measured on the last ones. NET-12's marked probe frames are timed, never heard. With no
## mixer (headless bots, tests) the timing still runs and nothing plays.

signal probe_heard(latency_usec: int)

## The client's mixer (SND-04), or null.
var mixer: SpatialMixer = null
## stream id -> {playout, source (mixer id or -1)}
var streams: Dictionary = {}
var jitter_ms: float = 0.0
var frames_played: int = 0
var frames_concealed: int = 0
var frames_smeared: int = 0


## One downstream packet as it arrived.
func push(packet: PackedByteArray, now_usec: int) -> void:
	var sid: int = int(LbVoicePlayout.stream_of(packet))
	var st: Dictionary = Variants.dict(streams.get(sid, {}))
	if st.is_empty():
		st = {"playout": _new_playout(), "source": -1}
		streams[sid] = st
	var p: LbVoicePlayout = st["playout"]
	p.push(packet, now_usec)


## Drains the connection's queue, then plays every frame whose time has come.
func tick(connection: ClientConnection, now_usec: int) -> void:
	if connection != null:
		while not connection.voice_in.is_empty():
			var item: Array = connection.voice_in.pop_front()
			var packet: PackedByteArray = item[0]
			push(packet, int(Variants.number(item[1])))
	for raw: Variant in streams.keys():
		var st: Dictionary = streams[raw]
		var p: LbVoicePlayout = st["playout"]
		for o: Variant in p.pop(now_usec):
			_play(st, Variants.dict(o), now_usec)
		if p.done():
			jitter_ms = p.jitter_ms()
			if mixer != null and int(Variants.number(st["source"])) >= 0:
				mixer.close_stream(int(Variants.number(st["source"])))
			streams.erase(raw)


func _play(st: Dictionary, o: Dictionary, now_usec: int) -> void:
	var kind: String = str(o["kind"])
	if kind == "end":
		return
	var t0: int = int(Variants.number(o.get("probe_t0_usec", -1)))
	if t0 >= 0:
		probe_heard.emit(now_usec - t0)
		return
	match kind:
		"frame":
			frames_played += 1
		"conceal":
			frames_concealed += 1
		"smear":
			frames_smeared += 1
	if mixer == null:
		return
	var p: LbVoicePlayout = st["playout"]
	var h: Dictionary = p.header()
	var source: int = int(Variants.number(st["source"]))
	var at: Vector2 = h["position"]
	var gain: float = float(Variants.number(h["gain_db"]))
	if source < 0:
		var flat: bool = Variants.flag(h["dry"]) or Variants.flag(h["telephone"])
		source = mixer.open_stream(at, gain, "Muffled" if Variants.flag(h["muffled"]) else "Voice", not flat)
		st["source"] = source
	else:
		mixer.move(source, at)
		mixer.set_gain(source, gain)
	var pcm: PackedFloat32Array = o["pcm"]
	mixer.append(source, pcm)


func _new_playout() -> LbVoicePlayout:
	var p: LbVoicePlayout = LbVoicePlayout.new()
	var frame_ms: float = Tuning.f(&"voice.frame_ms")
	var lo: float = Tuning.f(&"voice.jitter_buffer_min_ms")
	var hi: float = Tuning.f(&"voice.jitter_buffer_max_ms")
	var start: float = Tuning.f(&"voice.jitter_buffer_ms") if jitter_ms <= 0.0 \
		else float(LbVoicePlayout.suggest_ms(jitter_ms, roundi(lo), roundi(hi), roundi(frame_ms)))
	p.configure({"frame_ms": roundi(frame_ms), "min_ms": roundi(lo), "max_ms": roundi(hi), "start_ms": roundi(start),
		"speech_low_hz": Tuning.f(&"voice.speech_band_low_hz"), "speech_high_hz": Tuning.f(&"voice.speech_band_high_hz"),
		"cap_dbfs": caps(), "smear_dbfs": Tuning.f(&"voice.smear_level_dbfs"), "hiss_dbfs": Tuning.f(&"voice.telephone_hiss_dbfs")})
	return p


## Each band's playback ceiling: the next band's default threshold plus voice.band_cap_headroom_db
## (whisper -34, talk -16, shout -6), and voice.scream_cap_dbfs for a scream.
static func caps() -> PackedFloat32Array:
	var t: PackedFloat32Array = VoiceBands.defaults()
	var head: float = Tuning.f(&"voice.band_cap_headroom_db")
	return PackedFloat32Array([t[1] + head, t[2] + head, t[3] + head, Tuning.f(&"voice.scream_cap_dbfs")])
