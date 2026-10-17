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
## in the dark), its signal cord, and the open shaft it leaves. LFT-05's substation: the fuse board
## (bit 4 the burnt links cleared, bits 5-6 the fuses in, bit 7 every fuse way filled), the trip
## lever (bit 4 held) and the main switch (bit 4 closed). LFT-13's switchboard, as anyone in base
## camp sees it (bit 4 awake, bits 5-11 how many real flaps are down: never which, and never a drop
## only the operator is shown).

enum Kind { NONE = 0, TANK_GLASS = 1, ENGINE_PRIME = 2, ENGINE_CRANK = 3, ENGINE_THROTTLE = 4, CAGE = 5, CAGE_CORD = 6, OPEN_SHAFT = 7,
	FUSE_BOARD = 8, TRIP_LEVER = 9, MAIN_SWITCH = 10, SWITCHBOARD = 11 }
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


## LFT-05's fuse board: its links cleared, how many fuses are in (0-3), and every way filled.
static func fuse_board(cleared: bool, fuses: int, full: bool) -> int:
	return Kind.FUSE_BOARD | ((1 if cleared else 0) << 4) | (clampi(fuses, 0, 3) << 5) | ((1 if full else 0) << 7)


## LFT-13's board: awake, and how many of its flaps are really down (0-99).
static func switchboard(awake: bool, down: int) -> int:
	return Kind.SWITCHBOARD | ((1 if awake else 0) << 4) | (clampi(down, 0, 127) << 5)


## {awake, down} of the board's bits.
static func read_switchboard(bits: int) -> Dictionary:
	return {"awake": ((bits >> 4) & 1) == 1, "down": (bits >> 5) & 0x7F}


## {cleared, fuses, full} of a fuse board's bits.
static func read_fuse_board(bits: int) -> Dictionary:
	return {"cleared": ((bits >> 4) & 1) == 1, "fuses": (bits >> 5) & 0x3, "full": ((bits >> 7) & 1) == 1}


## LFT-05's trip lever, held or not.
static func trip_lever(held: bool) -> int:
	return Kind.TRIP_LEVER | ((1 if held else 0) << 4)


## LFT-05's main switch, closed or not.
static func main_switch(closed: bool) -> int:
	return Kind.MAIN_SWITCH | ((1 if closed else 0) << 4)


## Bit 4: the trip held, the switch closed.
static func flag_of(bits: int) -> bool:
	return ((bits >> 4) & 1) == 1
