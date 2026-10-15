class_name ActionRecord
extends RefCounted
## A one-shot action (NET-03): resent in every input packet until the server acknowledges it,
## and applied exactly once. Intent only: a revolver trigger carries its tick and aim, never a
## hit.

## TAP_ROCK: MNR-15's tap on the rock (T, or LB tapped with the stick centred; SND-12 uses it).
## CLOSE_UP: UI-02's request to open the Pocket Book, close a close-up or stay seated (CloseupKind.Ask).
## WATCH: RSC-04's watch chooser in the Dark: 1 the next teammate, 2 the one before, 0 stop.
## THROW: MNR-09's stone, thrown on Use's release: arg the distance in hundredths of a tile (the cursor's
## distance or the stick's deflection; the server clamps it to 2-8 tiles), aim the facing.
enum Kind { CALLOUT = 0, LAMP_SIGNAL = 1, CHALK = 2, RING_CHOICE = 3, TRIGGER = 4, TAP_ROCK = 5, CLOSE_UP = 6, WATCH = 7, THROW = 8 }

const SIZE: int = 11

## u16, wrapping, one per action.
var action_seq: int = 0
var kind: Kind = Kind.CALLOUT
## Which callout, signal, glyph or ring option (u16).
var arg: int = 0
## The shown tick it was issued at (u32).
var tick: int = 0
## Aim for a trigger, 0-65535 over 360 degrees.
var aim: int = 0


func pack(out: StreamPeerBuffer) -> void:
	out.put_u16(action_seq & 0xFFFF)
	out.put_u8(kind)
	out.put_u16(arg & 0xFFFF)
	out.put_u32(tick & 0xFFFFFFFF)
	out.put_u16(aim & 0xFFFF)


static func unpack(from: StreamPeerBuffer) -> ActionRecord:
	var a: ActionRecord = ActionRecord.new()
	a.action_seq = from.get_u16()
	a.kind = from.get_u8() as Kind
	a.arg = from.get_u16()
	a.tick = from.get_u32()
	a.aim = from.get_u16()
	return a


## True when the kind is known (always checked on the server).
func is_valid() -> bool:
	return kind >= Kind.CALLOUT and kind <= Kind.THROW
