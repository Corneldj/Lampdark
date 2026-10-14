class_name VoicePackets
extends RefCounted
## SND-07: the voice packets on the wire, the GDScript mirror of native/src/core/voice/voice_wire.h.
## Both ride Protocol.Msg.VOICE on the voice lane (unreliable, sequenced). Upstream, client to
## server: u16 seq, u8 head (band in bits 0-2; END, PROBE), then one 20 ms Opus frame. Downstream,
## server to a listener: u16 stream, u16 seq, u8 head (band; END, PROBE, MUFFLED, TELEPHONE, DRY),
## i8 gain dB, u8 crackle, i32 x and y in 1/16 tiles (the apparent position), then the Opus frame.
## The stream id is new every utterance and per listener: nothing on the wire names a speaker.

const BAND_MASK: int = 0x07
const END: int = 0x08
const PROBE: int = 0x10
const MUFFLED: int = 0x20
const TELEPHONE: int = 0x40
const DRY: int = 0x80
const MAX_BAND: int = 4
const UP_HEADER: int = 3
const DOWN_HEADER: int = 15
const POS_SCALE: int = 16


static func up(seq: int, band: int, flags: int, opus: PackedByteArray) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray([seq & 0xFF, (seq >> 8) & 0xFF, (band & BAND_MASK) | (flags & (END | PROBE))])
	b.append_array(opus)
	return b


## The last packet of an utterance: band silent, END, no audio.
static func end(seq: int) -> PackedByteArray:
	return up(seq, 0, END, PackedByteArray())


## NET-12's marked frame: the sender's clock (usec) in place of audio; timed at the listener's
## playout, never decoded.
static func probe(seq: int, band: int, sent_usec: int) -> PackedByteArray:
	var t: PackedByteArray = PackedByteArray()
	t.resize(8)
	t.encode_s64(0, sent_usec)
	return up(seq, band, PROBE, t)


## A downstream packet's fields (tests and diagnostics).
static func read_down(p: PackedByteArray) -> Dictionary:
	if p.size() < DOWN_HEADER:
		return {}
	return {"stream": p.decode_u16(0), "seq": p.decode_u16(2), "band": p[4] & BAND_MASK, "end": (p[4] & END) != 0,
		"probe": (p[4] & PROBE) != 0, "muffled": (p[4] & MUFFLED) != 0, "telephone": (p[4] & TELEPHONE) != 0,
		"dry": (p[4] & DRY) != 0, "gain_db": p.decode_s8(5), "crackle": p[6],
		"position": Vector2(p.decode_s32(7), p.decode_s32(11)) / float(POS_SCALE), "opus": p.slice(DOWN_HEADER)}
