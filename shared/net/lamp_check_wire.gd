class_name LampCheckWire
extends RefCounted
## RSC-06: Lamp Check's messages (Protocol.Msg.LAMP_CHECK, control lane). A kind byte, then:
## - OPEN, to every member as it opens: the run's uuid, the hooks in reading order (u16 lamp number,
##   u8 whether a check hangs), the remark (a FallCause name, "" for none), the card's text, flags
##   (bit 0: a wipe), this member's own outcome (none | escaped | dead | left_below) and how it ends
##   (u16 public_s: the pithead empties that long after it opens; 0: when everyone is ready).
##   Strings are a length (u8, or u16 for the card) and UTF-8 bytes.
## - END, to every member: why (time | ready).
## - READY, client to server: this player is ready to go.
## Lamp numbers, period names and a cause's name only: never an id of the server's, a Steam name or
## a lobby code.

const OPEN: String = "open"
const END: String = "end"
const READY: String = "ready"
const KINDS: Array[String] = [OPEN, END, READY]
## The own outcome's wire values; "" is none (no miner, or one the record leaves out).
const OUTCOMES: Array[String] = ["", "escaped", "dead", "left_below"]
const END_WHYS: Array[String] = ["time", "ready"]
const MAX_HOOKS: int = 16
const MAX_SHORT: int = 64
const MAX_CARD: int = 2048


static func open(hooks: Array, remark: String, card: String, wipe: bool, own: String, run_uuid: String, ends: Dictionary) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray([KINDS.find(OPEN)])
	_put_short(b, run_uuid)
	var count: int = mini(hooks.size(), MAX_HOOKS)
	b.append(count)
	for i: int in count:
		var h: Dictionary = Variants.dict(hooks[i])
		var at: int = b.size()
		b.resize(at + 3)
		b.encode_u16(at, clampi(int(Variants.number(h.get("lamp", 0))), 0, 0xFFFF))
		b[at + 2] = 1 if Variants.flag(h.get("hangs", false)) else 0
	_put_short(b, remark)
	var text: PackedByteArray = card.to_utf8_buffer()
	text = text.slice(0, mini(text.size(), MAX_CARD))
	var at_card: int = b.size()
	b.resize(at_card + 2)
	b.encode_u16(at_card, text.size())
	b.append_array(text)
	b.append(1 if wipe else 0)
	b.append(maxi(0, OUTCOMES.find(own)))
	var at_end: int = b.size()
	b.resize(at_end + 2)
	b.encode_u16(at_end, clampi(roundi(Variants.number(ends.get("public_s", 0.0))), 0, 0xFFFF))
	return b


static func end(why: String) -> PackedByteArray:
	return PackedByteArray([KINDS.find(END), maxi(0, END_WHYS.find(why))])


static func ready() -> PackedByteArray:
	return PackedByteArray([KINDS.find(READY)])


## OPEN: {kind, run_uuid, hooks: [{lamp, hangs}], remark, card, wipe, own, public_s}; END: {kind,
## why}; READY: {kind}; {} if malformed.
static func read(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes[0] >= KINDS.size():
		return {}
	match KINDS[bytes[0]]:
		READY:
			return {"kind": READY} if bytes.size() == 1 else {}
		END:
			if bytes.size() != 2 or bytes[1] >= END_WHYS.size():
				return {}
			return {"kind": END, "why": END_WHYS[bytes[1]]}
	var at: Array[int] = [1]
	var uuid: Variant = _take_short(bytes, at)
	if uuid == null or at[0] >= bytes.size():
		return {}
	var count: int = bytes[at[0]]
	at[0] += 1
	if count > MAX_HOOKS or at[0] + count * 3 > bytes.size():
		return {}
	var hooks: Array = []
	for i: int in count:
		if bytes[at[0] + 2] > 1:
			return {}
		hooks.append({"lamp": bytes.decode_u16(at[0]), "hangs": bytes[at[0] + 2] == 1})
		at[0] += 3
	var remark: Variant = _take_short(bytes, at)
	if remark == null or at[0] + 2 > bytes.size():
		return {}
	var n: int = bytes.decode_u16(at[0])
	at[0] += 2
	if n > MAX_CARD or at[0] + n + 4 != bytes.size():
		return {}
	var card: String = bytes.slice(at[0], at[0] + n).get_string_from_utf8()
	at[0] += n
	var wipe: int = bytes[at[0]]
	var own: int = bytes[at[0] + 1]
	if wipe > 1 or own >= OUTCOMES.size():
		return {}
	return {"kind": OPEN, "run_uuid": str(uuid), "hooks": hooks, "remark": str(remark), "card": card, "wipe": wipe == 1,
		"own": OUTCOMES[own], "public_s": float(bytes.decode_u16(at[0] + 2))}


static func _put_short(b: PackedByteArray, s: String) -> void:
	var bytes: PackedByteArray = s.to_utf8_buffer()
	bytes = bytes.slice(0, mini(bytes.size(), MAX_SHORT))
	b.append(bytes.size())
	b.append_array(bytes)


## The short string at at[0] (moving past it), or null if it runs off the end.
static func _take_short(bytes: PackedByteArray, at: Array[int]) -> Variant:
	if at[0] >= bytes.size():
		return null
	var n: int = bytes[at[0]]
	if n > MAX_SHORT or at[0] + 1 + n > bytes.size():
		return null
	var s: String = bytes.slice(at[0] + 1, at[0] + 1 + n).get_string_from_utf8()
	at[0] += 1 + n
	return s
