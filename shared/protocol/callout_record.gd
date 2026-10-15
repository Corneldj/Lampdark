class_name CalloutRecord
extends RefCounted
## SND-11 (GDD §15.5): one callout as one listener hears it: which line, in which character voice, at
## which band, from where it seems to come, how loud, how muffled or crackling, whether it came down
## a phone line or a dry channel, and which of its 20 ms frames arrived (SND-08's drop mask). The
## client plays SND-13's recorded frames under that mask. No speaker field: nothing names who called.
## CRT-10's illusions and CRT-12's echoes build this same type, so none can be told apart.
## Control lane, to one client (Protocol.Msg.CALLOUT).

const FLAG_MUFFLED: int = 1
const FLAG_TELEPHONE: int = 2
const FLAG_DRY: int = 4
const FLAG_CRACKLE: int = 8
## The fields, exactly (the parity test compares a real record's and an illusion's).
const FIELDS: Array[String] = ["voice", "line", "band", "apparent", "gain_db", "muffle", "flags", "mask"]

## SND-13's wire ids: VoiceManifest.wire_voice and wire_line.
var voice: int = 0
var line: int = 0
## 1 whisper, 2 talk, 3 shout.
var band: int = 2
## Absolute tiles; meaningless with FLAG_TELEPHONE or FLAG_DRY.
var apparent: Vector2 = Vector2.ZERO
var gain_db: int = 0
## 0-1, SND-08's distance muffle (1 through the rock).
var muffle: float = 0.0
var flags: int = 0
## One byte a frame: 1 kept, 0 dropped.
var mask: PackedByteArray = PackedByteArray()


func encode() -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.put_u8(voice)
	b.put_u8(line)
	b.put_u8(band)
	b.put_float(apparent.x)
	b.put_float(apparent.y)
	b.put_8(clampi(gain_db, -128, 127))
	b.put_u8(clampi(roundi(muffle * 255.0), 0, 255))
	b.put_u8(flags & 15)
	b.put_u16(mask.size())
	var bits: PackedByteArray = PackedByteArray()
	bits.resize(ceili(mask.size() / 8.0))
	for i: int in mask.size():
		if mask[i] != 0:
			bits[i >> 3] |= 1 << (i & 7)
	b.put_data(bits)
	return b.data_array


## Null when malformed.
static func decode(bytes: PackedByteArray) -> CalloutRecord:
	if bytes.size() < 16:
		return null
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	var r: CalloutRecord = CalloutRecord.new()
	r.voice = b.get_u8()
	r.line = b.get_u8()
	r.band = b.get_u8()
	r.apparent = Vector2(b.get_float(), b.get_float())
	r.gain_db = b.get_8()
	r.muffle = b.get_u8() / 255.0
	r.flags = b.get_u8()
	var n: int = b.get_u16()
	if bytes.size() != 16 + ceili(n / 8.0) or r.band < CalloutLines.WHISPER or r.band > CalloutLines.SHOUT or r.flags > 15:
		return null
	r.mask.resize(n)
	for i: int in n:
		r.mask[i] = (bytes[16 + (i >> 3)] >> (i & 7)) & 1
	return r


func kept_share() -> float:
	if mask.is_empty():
		return 0.0
	var kept: int = 0
	for m: int in mask:
		kept += 1 if m != 0 else 0
	return float(kept) / mask.size()


func to_dict() -> Dictionary:
	return {"voice": voice, "line": line, "band": band, "apparent": apparent, "gain_db": gain_db, "muffle": muffle, "flags": flags,
		"mask": mask}
