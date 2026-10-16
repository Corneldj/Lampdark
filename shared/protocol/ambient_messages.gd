class_name AmbientMessages
extends RefCounted
## SND-03: an ambient cue (Protocol.Msg AMBIENT, control lane, to one client): a bed layer the client
## cannot work out for itself starts or stops, with its fade. Layers: base camp's bed (its hum and the
## shaft's draught, while the miner is inside), DIR-02's cooling seam, MNR-11's silent canary, the
## drips. Each start and end also raises UI-03's silence-caption hook.


## Base camp's bed (its two layers), sent while the miner is inside.
const BASE_CAMP: StringName = &"base_camp"
## DIR-02: the seam ticks as it cools, through a relax, for a miner below.
const SEAM_COOLING: StringName = &"seam_cooling"


static func encode(layer: StringName, start: bool, fade_s: float) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	var raw: PackedByteArray = str(layer).to_utf8_buffer()
	b.put_u8(raw.size())
	b.put_data(raw)
	b.put_u8(1 if start else 0)
	b.put_u16(clampi(roundi(fade_s * 100.0), 0, 65535))
	return b.data_array


## {layer, start, fade_s}, or {} if malformed.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 4:
		return {}
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	var n: int = b.get_u8()
	if bytes.size() != 1 + n + 3:
		return {}
	var got: Array = b.get_data(n)
	var raw: PackedByteArray = got[1]
	return {"layer": StringName(raw.get_string_from_utf8()), "start": b.get_u8() == 1, "fade_s": b.get_u16() / 100.0}
