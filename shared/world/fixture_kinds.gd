class_name FixtureKinds
extends RefCounted
## What a FIXTURE entity is and shows, in its identity record's held field (NET-04: identity only,
## so only a client that sees it lit to 0.30 knows): the kind in the low 4 bits, the rest the
## kind's own. Wire values: append only.
##
## LFT-06's sight glass on the winder's paraffin tank (Proposed): one mark per can of capacity and
## the paraffin's line in lamp fills. A glass to look at, never a number or a meter on screen.
## LFT-08's engine: its prime, its crank (bits 4-5 the winder's look: cold, shuddering, running)
## and its throttle. LFT-10's cage (bits 4-5 its look: standing askew, wedged fast, riding, stopped
## in the dark), its signal cord, and the open shaft it leaves.

enum Kind { NONE = 0, TANK_GLASS = 1, ENGINE_PRIME = 2, ENGINE_CRANK = 3, ENGINE_THROTTLE = 4, CAGE = 5, CAGE_CORD = 6, OPEN_SHAFT = 7 }
enum Look { COLD = 0, SHUDDER = 1, RUNNING = 2 }
enum CageLook { STANDING = 0, WEDGED = 1, RIDING = 2, STOPPED = 3 }

const KIND_MASK: int = 0xF


static func kind_of(bits: int) -> Kind:
	return (bits & KIND_MASK) as Kind


## The tank's glass: capacity in cans (0-15), level in lamp fills (0-127; four to a can).
static func tank_glass(capacity_cans: int, level_fills: int) -> int:
	return Kind.TANK_GLASS | (clampi(capacity_cans, 0, 15) << 4) | (clampi(level_fills, 0, 127) << 8)


## {cans, fills} of a tank glass's bits.
static func read_tank_glass(bits: int) -> Dictionary:
	return {"cans": (bits >> 4) & 0xF, "fills": (bits >> 8) & 0x7F}


## The engine's crank with the winder's look.
static func engine(look: int) -> int:
	return Kind.ENGINE_CRANK | (clampi(look, 0, 3) << 4)


static func look_of(bits: int) -> Look:
	return ((bits >> 4) & 0x3) as Look


## The cage with its look (CageLook).
static func cage(look: int) -> int:
	return Kind.CAGE | (clampi(look, 0, 3) << 4)
