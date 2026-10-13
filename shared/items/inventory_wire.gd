class_name InventoryWire
extends RefCounted
## MNR-04: a miner's own hands and belt as its owner's client receives them (Protocol.Msg
## INVENTORY, control lane, sent whenever they change and on every welcome). Only the owner ever
## receives this; other clients see only what is in a miner's hands, on its identity record
## (NET-04's held bits). Item kinds are ItemKinds wire values; no uid or item state rides here.
## Layout: lamp kind, lamp count, flags (bit 0 hooked, bit 1 chalk, bit 2 Pocket Book, bit 3 the
## lamp in hand shuttered, bits 4-5 its wick: MNR-06, so the client can follow a douse; bit 6 both
## hands full, a carry: MNR-13, so the client swaps in the job page), free kind,
## free count, selected slot, slot count, then kind and count per slot, the lamp check (u16), the
## number of found notes (u8) and, only while Check Lamp is held (MNR-07), the lamp's oil in 48ths
## of a fill (u8) and its notches (u8).


static func encode(d: Dictionary) -> PackedByteArray:
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	var lamp: Array = Variants.array(d["lamp"])
	var free: Array = Variants.array(d["free"])
	b.put_u8(int(Variants.number(lamp[0])))
	b.put_u8(int(Variants.number(lamp[1])))
	var flags: int = (1 if Variants.flag(d["hooked"]) else 0) | (2 if Variants.flag(d["chalk"]) else 0) \
		| (4 if Variants.flag(d["pocket_book"]) else 0) | (8 if Variants.flag(d.get("lamp_shut", false)) else 0) \
		| ((int(Variants.number(d.get("lamp_wick", 1))) & 3) << 4) | (64 if Variants.flag(d.get("two_handed", false)) else 0)
	b.put_u8(flags)
	b.put_u8(int(Variants.number(free[0])))
	b.put_u8(int(Variants.number(free[1])))
	b.put_u8(int(Variants.number(d["selected"])))
	var slots: Array = Variants.array(d["slots"])
	b.put_u8(slots.size())
	for raw: Variant in slots:
		var row: Array = Variants.array(raw)
		b.put_u8(int(Variants.number(row[0])))
		b.put_u8(int(Variants.number(row[1])))
	b.put_u16(int(Variants.number(d["lamp_check"])))
	b.put_u8(mini(int(Variants.number(d["notes"])), 255))
	# MNR-07: Check Lamp, only while it is held: the lamp's oil in 48ths and its notches.
	var check: Dictionary = Variants.dict(d.get("check", {}))
	if not check.is_empty():
		b.put_u8(clampi(int(Variants.number(check["oil48"])), 0, 48))
		b.put_u8(int(Variants.number(check["notches"])))
	return b.data_array


## The same dictionary back, or {} if the bytes are short or malformed.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 7:
		return {}
	var b: StreamPeerBuffer = StreamPeerBuffer.new()
	b.data_array = bytes
	var lamp: Array = [b.get_u8(), b.get_u8()]
	var flags: int = b.get_u8()
	var free: Array = [b.get_u8(), b.get_u8()]
	var selected: int = b.get_u8()
	var n: int = b.get_u8()
	var base_size: int = 7 + n * 2 + 3
	if bytes.size() != base_size and bytes.size() != base_size + 2:
		return {}
	var slots: Array = []
	for _i: int in n:
		slots.append([b.get_u8(), b.get_u8()])
	var out: Dictionary = {"lamp": lamp, "hooked": (flags & 1) != 0, "chalk": (flags & 2) != 0, "pocket_book": (flags & 4) != 0,
		"lamp_shut": (flags & 8) != 0, "lamp_wick": (flags >> 4) & 3, "two_handed": (flags & 64) != 0,
		"free": free, "selected": selected, "slots": slots, "lamp_check": b.get_u16(), "notes": b.get_u8()}
	if bytes.size() == base_size + 2:
		out["check"] = {"oil48": b.get_u8(), "notches": b.get_u8()}
	return out
