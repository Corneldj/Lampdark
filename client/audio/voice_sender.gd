class_name VoiceSender
extends RefCounted
## SND-07: the own voice, upstream (GDD §15.5 step 3). Each clean 20 ms frame SND-06 lets out
## (voice activation, or push-to-talk held) is Opus-encoded at voice.opus_bitrate_kbps and sent
## with its band and a sequence number; when the voice stops, one END packet closes the utterance,
## so a lost last run is never mistaken for a stall. Nothing else of the microphone leaves the PC.

var encoder: LbOpusEncoder = LbOpusEncoder.new()
## func(packet: PackedByteArray): the connection's send_voice.
var send: Callable = Callable()
var seq: int = 0
var sent: int = 0
var _was_sending: bool = false


func _init() -> void:
	encoder.setup(roundi(Tuning.f(&"voice.opus_bitrate_kbps") * 1000.0), true)


## One frame from SND-05, after SND-06 has measured it (`bands.push` first).
func on_frame(pcm: PackedFloat32Array, bands: VoiceBands) -> void:
	if not send.is_valid():
		return
	if bands.sending():
		var opus: PackedByteArray = encoder.encode(pcm)
		if opus.is_empty():
			return
		send.call(VoicePackets.up(seq, bands.band, 0, opus))
		_next()
		_was_sending = true
	elif _was_sending:
		send.call(VoicePackets.end(seq))
		_next()
		_was_sending = false


## The microphone closed mid-utterance: close it on the wire too.
func stop() -> void:
	if _was_sending and send.is_valid():
		send.call(VoicePackets.end(seq))
		_next()
	_was_sending = false


func _next() -> void:
	seq = (seq + 1) & 0xFFFF
	sent += 1
