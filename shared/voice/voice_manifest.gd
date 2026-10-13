class_name VoiceManifest
extends RefCounted
## SND-13 (Gameplay §6.7, §7.3, §13.2; GDD §14.2): every recorded line, read from
## data/voices/manifest.json, with each character file's frames and duration from the generated
## data/voices/voice_index.json. Shared: the server reads only these two files (its build carries no
## voice audio); the client loads the files themselves through VoiceBank. Records name a line by its
## wire number (`wire_line`), and only character lines have one: no illusion or callout record can
## name a lampman line, and the lampman is not a voice (`wire_voice`).

const MANIFEST: String = "res://data/voices/manifest.json"
const INDEX: String = "res://data/voices/voice_index.json"
const VOICES_DIR: String = "res://client/audio/voices"
## The five lines CRT-10's illusions copy (Gameplay §6.7).
const COPYABLE: Array[String] = ["here", "help", "is_that_you", "count_off", "douse"]

static var _manifest: Dictionary = {}
static var _index: Dictionary = {}
static var _lines: Dictionary = {}
static var _wire: Array[String] = []


static func _ensure() -> void:
	if not _manifest.is_empty():
		return
	_manifest = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)))
	_index = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(INDEX)))
	for raw: Variant in Variants.array(_manifest.get("lines", [])):
		var info: Dictionary = Variants.dict(raw)
		_lines[str(info["line_id"])] = info
		_wire.append(str(info["line_id"]))


## The eight character voices, in wire order.
static func voice_ids() -> PackedStringArray:
	_ensure()
	var out: PackedStringArray = PackedStringArray()
	for raw: Variant in Variants.array(_manifest.get("voices", [])):
		out.append(str(Variants.dict(raw)["voice_id"]))
	return out


static func line_ids() -> PackedStringArray:
	_ensure()
	return PackedStringArray(_wire)


static func line_info(line_id: String) -> Dictionary:
	_ensure()
	return Variants.dict(_lines.get(line_id, {}))


static func forms_of(line_id: String) -> PackedStringArray:
	return PackedStringArray(Variants.array(line_info(line_id).get("forms", [])))


static func lampman_lines() -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for raw: Variant in Variants.array(Variants.dict(_manifest.get("lampman", {})).get("lines", [])):
		out.append(Variants.dict(raw))
	return out


## A character line's number in records (callouts, illusions, vocal sounds); -1 for anything else,
## the lampman's lines included.
static func wire_line(line_id: String) -> int:
	_ensure()
	return _wire.find(line_id)


static func line_of_wire(n: int) -> String:
	_ensure()
	return _wire[n] if n >= 0 and n < _wire.size() else ""


## A voice's number in records, 0-7; -1 for anything else (the lampman is not a voice).
static func wire_voice(voice_id: String) -> int:
	return Array(voice_ids()).find(voice_id)


## The index entry of one character file: {frames, samples, duration_s, band, lufs, ...}.
static func entry(voice_id: String, line_id: String, form: String) -> Dictionary:
	_ensure()
	return Variants.dict(Variants.dict(Variants.dict(_index.get("voices", {})).get(voice_id, {})).get("%s.%s" % [line_id, form], {}))


static func frames_of(voice_id: String, line_id: String, form: String) -> int:
	return int(Variants.number(entry(voice_id, line_id, form).get("frames", 0)))


static func duration_s(voice_id: String, line_id: String, form: String) -> float:
	return float(Variants.number(entry(voice_id, line_id, form).get("duration_s", 0.0)))


## One file per (voice, line, form): every system that speaks the line plays this path.
static func path_of(voice_id: String, line_id: String, form: String) -> String:
	return "%s/%s/%s.%s.lbv" % [VOICES_DIR, voice_id, line_id, form]


## A lamp number spoken digit by digit (§13.2): each digit continuing, the last with the final fall.
## [{line_id, form}] in order; empty if `digits` holds anything but 0-9.
static func stitch_digits(digits: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in digits.length():
		var c: String = digits[i]
		if not c.is_valid_int():
			return [] as Array[Dictionary]
		out.append({"line_id": "digit_" + c, "form": "final" if i == digits.length() - 1 else "continuing"})
	return out
