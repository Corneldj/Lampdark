class_name LampSignalKind
extends RefCounted
## SND-12 (Gameplay §6.6): the five lamp signals, in the wheel's slice order. A signal under way
## rides in its maker's flame byte (VIS-08's identity record, bits 5-7), so a watcher's client knows
## it only while it sees the maker with identity.

enum Kind { NONE = 0, STOP = 1, COME = 2, OK = 3, HELP = 4, POINT = 5 }

## The wheel's slices, clockwise from the top.
const WHEEL: Array[Kind] = [Kind.STOP, Kind.COME, Kind.OK, Kind.HELP, Kind.POINT]
const FLAME_SHIFT: int = 5
const FLAME_MASK: int = 0xE0
const TEXT_KEYS: Array[String] = ["", "wheel.signal.stop", "wheel.signal.come", "wheel.signal.ok", "wheel.signal.help",
	"wheel.signal.point"]


static func of_flame(bits: int) -> Kind:
	return ((bits & FLAME_MASK) >> FLAME_SHIFT) as Kind


static func to_flame(kind: Kind) -> int:
	return (kind << FLAME_SHIFT) & FLAME_MASK
