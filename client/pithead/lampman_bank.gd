class_name LampmanBank
extends RefCounted
## SND-13 (Gameplay §9.2, GDD §14.2, §14.4): the lampman's recordings: the digits 0-9 (continuing and
## final), one remark per cause (RSC-06's texts) and the first-run line. He is heard only above
## ground: only the Pithead and Lamp Check (client/pithead/) may load this bank, never a mine scene
## or the illusion stage (test_lampman_isolation), and no record can name his lines
## (VoiceManifest.wire_line). Dry Ogg Vorbis, never masked.

const DIR: String = "res://client/audio/lampman"


static func stream(line_id: String, form: String = "one") -> AudioStream:
	var path: String = "%s/%s.%s.ogg" % [DIR, line_id, form]
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	return s


## The lampman reading a lamp number at Lamp Check (RSC-06): one stream per digit.
static func number(lamp_number: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for d: Dictionary in VoiceManifest.stitch_digits(lamp_number):
		out.append(stream(str(d["line_id"]), str(d["form"])))
	return out


static func remark(cause_id: String) -> AudioStream:
	return stream("remark_" + cause_id)


static func first_run() -> AudioStream:
	return stream("first_run")
