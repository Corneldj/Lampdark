class_name BoardWire
extends RefCounted
## LFT-13: the switchboard as its operator sees it (Protocol.Msg.BOARD, control lane, to the seated
## operator alone): whether it is awake (Power, never Dead Lines), the line the cord is in (0: none)
## and every drop's flap, 1 to 99 (Gameplay §6.6, §4.10). The board shows a calling line's flap down,
## a cut line's dark, a held call's mark; it never shows where a phone is, who is calling, or why a
## line went dark, and a number no phone has is a flap like any idle one. The operator's asks go up
## as ActionRecord.Kind.BOARD: `arg` = (verb << 8) | number.

enum Flap { UP = 0, DOWN = 1, DARK = 2, HELD = 3 }
enum Verb { NONE = 0, PLUG = 1, PULL = 2, HOLD = 3, RING = 4 }

## Drops on the board (LFT-12's pool, phones.line_number_max, Proposed: fixed at 99).
const DROPS: int = 99
const SIZE: int = 2 + (DROPS * 2 + 7) / 8


## `flaps`: DROPS entries, Flap values (index 0 is line 1).
static func encode(awake: bool, cord: int, flaps: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(SIZE)
	out[0] = 1 if awake else 0
	out[1] = clampi(cord, 0, DROPS)
	for i: int in DROPS:
		var f: int = (flaps[i] if i < flaps.size() else Flap.UP) & 0x3
		out[2 + (i * 2) / 8] |= f << ((i * 2) % 8)
	return out


## {awake, cord, flaps: PackedByteArray of DROPS}, or {} when malformed.
static func decode(payload: PackedByteArray) -> Dictionary:
	if payload.size() != SIZE or payload[0] > 1 or payload[1] > DROPS:
		return {}
	var flaps: PackedByteArray = PackedByteArray()
	flaps.resize(DROPS)
	for i: int in DROPS:
		flaps[i] = (payload[2 + (i * 2) / 8] >> ((i * 2) % 8)) & 0x3
	return {"awake": payload[0] == 1, "cord": payload[1], "flaps": flaps}


static func ask(verb: Verb, number: int) -> int:
	return (verb << 8) | clampi(number, 0, DROPS)


static func verb_of(arg: int) -> Verb:
	var v: int = (arg >> 8) & 0xFF
	return (v as Verb) if v <= Verb.RING else Verb.NONE


static func number_of(arg: int) -> int:
	return arg & 0xFF
