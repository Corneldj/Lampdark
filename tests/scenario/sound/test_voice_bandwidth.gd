extends "res://tests/scenario/kit/scenario_test.gd"
## SND-07 and GDD §15.3: with four speakers in range, a listener's downstream stays under 64 kbps
## plus 24 per voice, and a speaker's upstream under 16 plus 24 while transmitting, on emulated
## 40 and 250 ms links with 2% loss. The speakers send real Opus frames (24 kbps, speech-like
## audio) every 20 ms, as a client does; lane bytes count each message's framing.

const SPEAKERS: int = 4


func before_all() -> void:
	assert_true(Tuning.load_server())


## A second of speech-like audio, encoded: 50 real Opus frames to cycle through.
static func opus_frames() -> Array[PackedByteArray]:
	var enc: LbOpusEncoder = LbOpusEncoder.new()
	enc.setup(roundi(Tuning.f(&"voice.opus_bitrate_kbps") * 1000.0), true)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var out: Array[PackedByteArray] = []
	var lp: float = 0.0
	for f: int in 50:
		var pcm: PackedFloat32Array = PackedFloat32Array()
		pcm.resize(960)
		for i: int in 960:
			var t: float = float(f * 960 + i) / 48000.0
			lp += 0.25 * (rng.randf_range(-1.0, 1.0) - lp)
			pcm[i] = 0.4 * lp * maxf(0.0, sin(TAU * 5.0 * t))
		out.append(enc.encode(pcm))
	return out


func _kbps(after: Dictionary, before: Dictionary, lanes: Array, seconds: float) -> float:
	var bytes: int = 0
	for lane: int in lanes:
		bytes += int(Variants.number(after.get(lane, 0))) - int(Variants.number(before.get(lane, 0)))
	return bytes * 8.0 / 1000.0 / seconds


func test_four_voices_fit_the_budget() -> void:
	var frames: Array[PackedByteArray] = opus_frames()
	var bytes_per_frame: float = 0.0
	for f: PackedByteArray in frames:
		bytes_per_frame += f.size()
	gut.p("Opus at %.0f kbps: %.1f bytes a frame on average" % [Tuning.f(&"voice.opus_bitrate_kbps"), bytes_per_frame / frames.size()])
	var game_lanes: Array = [Lane.Id.CONTROL, Lane.Id.FRAMES, Lane.Id.INPUTS, Lane.Id.BULK]
	for rtt: int in [40, 250]:
		var rows: PackedStringArray = PackedStringArray(["#".repeat(14)])
		for y: int in 5:
			rows.append("#" + ".".repeat(12) + "#")
		rows.append("#".repeat(14))
		var s: Scenario = make({"seed": 90 + rtt, "fixture": FixtureMap.from_ascii(rows)})
		var listener: MinerHandle = s.add_miner("lis", Vector2i(6, 3))
		listener.link(rtt, 2.0)
		var speakers: Array[MinerHandle] = []
		for i: int in SPEAKERS:
			var h: MinerHandle = s.add_miner("sp%d" % i, Vector2i(2 + i * 3, 1))
			h.link(rtt, 2.0)
			speakers.append(h)
		s.step(10)
		var state: Dictionary = {"next": 0, "seq": 0}
		s.on_poll = func(_sc: Scenario) -> void:
			var now: int = Transport.now_usec()
			if now < int(Variants.number(state["next"])):
				return
			var seq: int = int(Variants.number(state["seq"]))
			for h: MinerHandle in speakers:
				h.connection.send_voice(VoicePackets.up(seq & 0xFFFF, 2, 0, frames[seq % frames.size()]))
			state["seq"] = seq + 1
			state["next"] = now + 20000
		s.step(10)  # under way
		var down0: Dictionary = listener.connection.bytes_in.duplicate()
		var up0: Dictionary = speakers[0].connection.bytes_out.duplicate()
		var t0: int = Transport.now_usec()
		s.step(200)  # 10 s
		var seconds: float = (Transport.now_usec() - t0) / 1000000.0
		var down_voice: float = _kbps(listener.connection.bytes_in, down0, [Lane.Id.VOICE], seconds)
		var down_game: float = _kbps(listener.connection.bytes_in, down0, game_lanes, seconds)
		var up_voice: float = _kbps(speakers[0].connection.bytes_out, up0, [Lane.Id.VOICE], seconds)
		var up_game: float = _kbps(speakers[0].connection.bytes_out, up0, game_lanes, seconds)
		s.on_poll = Callable()
		gut.p("%d ms: down %.1f kbps game + %.1f voice (%d voices); up %.1f game + %.1f voice" % [rtt, down_game, down_voice,
			SPEAKERS, up_game, up_voice])
		assert_lt(down_game + down_voice, 64.0 + 24.0 * SPEAKERS, "%d ms: downstream under 64 + 24 per voice" % rtt)
		assert_lt(up_game + up_voice, 16.0 + 24.0, "%d ms: upstream under 16 + 24 while transmitting" % rtt)
		assert_gt(down_voice, 60.0, "the four voices really arrived")
		listener.connection.voice_in.clear()
