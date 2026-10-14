extends GutTest
## SND-07's client half: the upstream packet, the sender (frames while SND-06 lets them out, one END
## when the voice stops), and playback (a stream per utterance, closed at its end; probe frames
## timed, never heard; the band caps for each band).


func before_all() -> void:
	Tuning.load_client()


func test_the_upstream_packet() -> void:
	var p: PackedByteArray = VoicePackets.up(0x1234, 3, 0, PackedByteArray([7, 8, 9]))
	assert_eq(p.size(), VoicePackets.UP_HEADER + 3)
	assert_eq(p.decode_u16(0), 0x1234)
	assert_eq(p[2] & VoicePackets.BAND_MASK, 3)
	var e: PackedByteArray = VoicePackets.end(5)
	assert_eq(e.size(), VoicePackets.UP_HEADER, "an END carries no audio")
	assert_ne(e[2] & VoicePackets.END, 0)
	var head: Dictionary = LbVoiceForwarder.parse(VoicePackets.probe(1, 2, 123456789))
	assert_true(Variants.flag(head["valid"]))
	assert_true(Variants.flag(head["probe"]))


func test_the_sender_sends_while_the_band_lets_it_and_closes_the_utterance() -> void:
	var sent: Array[PackedByteArray] = []
	var sender: VoiceSender = VoiceSender.new()
	sender.send = func(packet: PackedByteArray) -> void: sent.append(packet)
	var bands: VoiceBands = VoiceBands.new()
	var talk: PackedFloat32Array = PackedFloat32Array()
	talk.resize(960)
	for i: int in 960:
		talk[i] = 0.05 * sin(TAU * 1000.0 * i / 48000.0)  # about -29 dBFS: talk
	var quiet: PackedFloat32Array = PackedFloat32Array()
	quiet.resize(960)
	for f: int in 10:
		bands.push(talk)
		sender.on_frame(talk, bands)
	var talking: int = sent.size()
	assert_gt(talking, 5, "frames go out while talking")
	for f: int in 30:
		bands.push(quiet)
		sender.on_frame(quiet, bands)
	var ends: int = 0
	for p: PackedByteArray in sent:
		if (p[2] & VoicePackets.END) != 0:
			ends += 1
	assert_eq(ends, 1, "one END when the band falls silent")
	var last: PackedByteArray = sent.back()
	assert_ne(last[2] & VoicePackets.END, 0, "and nothing after it")
	var seqs: Array[int] = []
	for p: PackedByteArray in sent:
		seqs.append(p.decode_u16(0))
	for i: int in range(1, seqs.size()):
		assert_eq(seqs[i], (seqs[i - 1] + 1) & 0xFFFF, "sequence numbers run on")


func test_push_to_talk_released_sends_nothing() -> void:
	var sent: Array = []
	var sender: VoiceSender = VoiceSender.new()
	sender.send = func(packet: PackedByteArray) -> void: sent.append(packet)
	var bands: VoiceBands = VoiceBands.new()
	bands.push_to_talk = true
	var talk: PackedFloat32Array = PackedFloat32Array()
	talk.resize(960)
	for i: int in 960:
		talk[i] = 0.05 * sin(TAU * 1000.0 * i / 48000.0)
	for f: int in 10:
		bands.push(talk)
		sender.on_frame(talk, bands)
	assert_eq(sent.size(), 0, "released: nothing is sent and the mine hears nothing")


## A downstream packet as the server would send it.
static func _down(stream: int, seq: int, band: int, flags: int, payload: PackedByteArray) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.resize(VoicePackets.DOWN_HEADER)
	b.encode_u16(0, stream)
	b.encode_u16(2, seq)
	b[4] = band | flags
	b.encode_s8(5, -3)
	b[6] = 0
	b.encode_s32(7, 10 * VoicePackets.POS_SCALE)
	b.encode_s32(11, 4 * VoicePackets.POS_SCALE)
	b.append_array(payload)
	return b


func test_playback_runs_a_stream_per_utterance_and_closes_it_at_the_end() -> void:
	var vp: VoicePlayback = VoicePlayback.new()
	var enc: LbOpusEncoder = LbOpusEncoder.new()
	enc.setup(24000, true)
	var pcm: PackedFloat32Array = PackedFloat32Array()
	pcm.resize(960)
	var now: int = 1000000
	for k: int in 5:
		vp.push(_down(41, k, 2, 0, enc.encode(pcm)), now)
		now += 20000
		vp.tick(null, now)
	vp.push(_down(41, 5, 0, VoicePackets.END, PackedByteArray()), now)
	vp.push(_down(42, 0, 1, 0, enc.encode(pcm)), now)
	assert_eq(vp.streams.size(), 2, "two utterances, two streams")
	vp.tick(null, now + 500000)
	assert_false(vp.streams.has(41), "the ended stream is closed")
	assert_eq(vp.frames_played, 5 + 1)


func test_probe_frames_are_timed_not_heard() -> void:
	var vp: VoicePlayback = VoicePlayback.new()
	var heard: Array[int] = []
	vp.probe_heard.connect(func(latency: int) -> void: heard.append(latency))
	var t: PackedByteArray = PackedByteArray()
	t.resize(8)
	t.encode_s64(0, 900000)
	vp.push(_down(7, 0, 2, VoicePackets.PROBE, t), 1000000)
	vp.tick(null, 1000000 + int(Tuning.f(&"voice.jitter_buffer_ms") * 1000.0))
	assert_eq(heard.size(), 1)
	assert_eq(heard[0], 100000 + int(Tuning.f(&"voice.jitter_buffer_ms") * 1000.0), "sent at 0.9 s, played after the buffer")
	assert_eq(vp.frames_played, 0, "never played")


func test_band_caps() -> void:
	var c: PackedFloat32Array = VoicePlayback.caps()
	assert_eq(c, PackedFloat32Array([-34.0, -16.0, -6.0, -1.0]), "whisper -34, talk -16, shout -6, scream -1 dBFS")
