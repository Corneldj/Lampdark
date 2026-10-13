class_name VoiceAssignment
extends RefCounted
## SND-13 (Proposed): which character voice speaks for each miner in a run. A roster miner brings the
## voice chosen when hired (MOD-01; by default a hash of the name, changeable at the Pithead). At run
## start voices are made unique: in join order, a clash gives the later joiner the first free voice,
## as lamp numbers do; Hired Hands then take free voices. Deterministic for the same roster and join
## order. Server-only: clients learn a voice only inside a record (a callout, a vocal sound), never as
## a miner-to-voice table.

const VOICES: int = 8


## The default voice for a name: FNV-1a over its UTF-8 bytes, mod 8 (stable across platforms).
static func default_for(miner_name: String) -> int:
	var h: int = 0x811C9DC5
	for b: int in miner_name.to_utf8_buffer():
		h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
	return h % VOICES


## `roster`: [{miner: id, voice: 0-7 or -1, name}] in join order; `hands`: how many Hired Hands.
## {miners: {id: voice}, hands: [voice per hand]}. With more than eight speakers, voices repeat from
## the first (never more than five miners and three Hands in practice).
static func assign(roster: Array[Dictionary], hands: int) -> Dictionary:
	var used: Array[int] = []
	var miners: Dictionary = {}
	for m: Dictionary in roster:
		var want: int = int(Variants.number(m.get("voice", -1)))
		if want < 0 or want >= VOICES:
			want = default_for(str(m.get("name", "")))
		var v: int = want if not used.has(want) else _first_free(used)
		used.append(v)
		miners[m["miner"]] = v
	var out_hands: Array[int] = []
	for _i: int in hands:
		var v: int = _first_free(used)
		used.append(v)
		out_hands.append(v)
	return {"miners": miners, "hands": out_hands}


static func _first_free(used: Array[int]) -> int:
	for v: int in VOICES:
		if not used.has(v):
			return v
	return used.size() % VOICES
