class_name VoiceBank
extends RefCounted
## SND-13: the character voices' files, loaded once each. The callout wheel (SND-11), the tapper's
## illusions (CRT-10), a muted roll call (MOD-04) and the fall's scream (SND-15) all come through
## `line`, so a false 'Here!' from the rock is the very file a teammate's wheel plays. Each file is
## .lbv: 20 ms Opus packets that SND-07's decoder and concealment play like live voice (`parse`).
## Never the lampman: his bank lives above ground only (client/pithead/).

static var _cache: Dictionary = {}
static var _decoded: Dictionary = {}


## The file's bytes; empty if it does not exist.
static func line(voice_id: String, line_id: String, form: String) -> PackedByteArray:
	var path: String = VoiceManifest.path_of(voice_id, line_id, form)
	if _cache.has(path):
		var cached: PackedByteArray = _cache[path]
		return cached
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if not bytes.is_empty():
		_cache[path] = bytes
	return bytes


## SND-11's wheel: a callout at its band (whisper, talk or shout).
static func callout(voice_id: String, line_id: String, band: String) -> PackedByteArray:
	return line(voice_id, line_id, band)


## CRT-10: a copied line in a teammate's voice (or the target's own with no other human below).
static func illusion(voice_id: String, line_id: String, form: String) -> PackedByteArray:
	return line(voice_id, line_id, form)


## MOD-04's muted roll call: 'Lamp one-one-four, all right', file by file.
static func roll_call(voice_id: String, lamp_number: String) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = [line(voice_id, "roll_lamp", "talk")]
	for d: Dictionary in VoiceManifest.stitch_digits(lamp_number):
		out.append(line(voice_id, str(d["line_id"]), str(d["form"])))
	out.append(line(voice_id, "roll_all_right", "talk"))
	return out


## A lamp number in a voice (an illusion's 'One... one... four', or the roll call's digits).
static func digits(voice_id: String, lamp_number: String) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for d: Dictionary in VoiceManifest.stitch_digits(lamp_number):
		out.append(line(voice_id, str(d["line_id"]), str(d["form"])))
	return out


## A line decoded to 48 kHz mono (libopus, LbOpusDecoder), cached; what the mixer plays until SND-07
## streams lines through the voice decoder and its concealment. Empty if missing or malformed.
static func pcm(voice_id: String, line_id: String, form: String) -> PackedFloat32Array:
	var path: String = VoiceManifest.path_of(voice_id, line_id, form)
	if _decoded.has(path):
		var cached: PackedFloat32Array = _decoded[path]
		return cached
	var out: PackedFloat32Array = LbOpusDecoder.new().decode_lbv(line(voice_id, line_id, form))
	if not out.is_empty():
		_decoded[path] = out
	return out


## {pre_skip, samples, frames: Array[PackedByteArray]} from an .lbv file; {} if malformed.
static func parse(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 14 or bytes.slice(0, 4).get_string_from_ascii() != "LBV1":
		return {}
	var pre_skip: int = bytes.decode_u16(4)
	var samples: int = bytes.decode_u32(6)
	var count: int = bytes.decode_u32(10)
	var frames: Array[PackedByteArray] = []
	var pos: int = 14
	for _i: int in count:
		if pos + 2 > bytes.size():
			return {}
		var n: int = bytes.decode_u16(pos)
		pos += 2
		if pos + n > bytes.size():
			return {}
		frames.append(bytes.slice(pos, pos + n))
		pos += n
	if pos != bytes.size():
		return {}
	return {"pre_skip": pre_skip, "samples": samples, "frames": frames}
