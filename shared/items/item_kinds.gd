class_name ItemKinds
extends RefCounted
## MNR-04's item registry (Gameplay §4.3, §4.5-4.7, A.9): every kind of item a miner can find,
## with where it rides (hand class), its stack size (read from tuning) and its text key. Every
## item is a small thing (VIS-03): seen only at vision.small_thing_light_min, never a token.
## Behaviour lives in each owning ticket (MNR-06 to MNR-12, MNR-16, RSC-02). Wire values: append
## only. Stretchers and the drum gear are loads (MNR-14), not items; the lamp check, chalk and the
## Pocket Book need no slot and are not items at all (HandsAndBelt keeps them).

enum Kind {
	NONE = 0,
	GAUZE_LAMP = 1,
	ELECTRIC_LAMP = 2,
	CANDLE = 3,
	FLARE = 4,
	STONE = 5,
	OIL_FLASK = 6,
	PARAFFIN_CAN = 7,
	HEALING_KIT = 8,
	SPANNER = 9,
	HAMMER = 10,
	CROWBAR = 11,
	WIRE_CUTTERS = 12,
	FUSE = 13,
	ROPE_CLAMP = 14,
	MAGNETO = 15,
	DRIVE_BELT = 16,
	BRAKE_SHOE = 17,
	REVOLVER = 18,
	ROUNDS = 19,
	CANARY = 20,
	NOTE = 21,
}

## Where a kind rides: a lamp (the lamp hand, else a slot), a belt slot, the free hand only (the
## paraffin can), or the Pocket Book (found notes).
enum HandClass { LAMP = 0, BELT = 1, FREE_ONLY = 2, BOOK = 3 }

## kind -> [hand class, stack tuning key or "" for items.stack_default]
const TABLE: Dictionary = {
	Kind.GAUZE_LAMP: [HandClass.LAMP, ""],
	Kind.ELECTRIC_LAMP: [HandClass.LAMP, ""],
	Kind.CANDLE: [HandClass.BELT, "items.stack_candles"],
	Kind.FLARE: [HandClass.BELT, ""],
	Kind.STONE: [HandClass.BELT, "items.stack_stones"],
	Kind.OIL_FLASK: [HandClass.BELT, ""],
	Kind.PARAFFIN_CAN: [HandClass.FREE_ONLY, ""],
	Kind.HEALING_KIT: [HandClass.BELT, ""],
	Kind.SPANNER: [HandClass.BELT, ""],
	Kind.HAMMER: [HandClass.BELT, ""],
	Kind.CROWBAR: [HandClass.BELT, ""],
	Kind.WIRE_CUTTERS: [HandClass.BELT, ""],
	Kind.FUSE: [HandClass.BELT, "items.stack_fuses"],
	Kind.ROPE_CLAMP: [HandClass.BELT, "items.stack_rope_clamps"],
	Kind.MAGNETO: [HandClass.BELT, ""],
	Kind.DRIVE_BELT: [HandClass.BELT, ""],
	Kind.BRAKE_SHOE: [HandClass.BELT, ""],
	Kind.REVOLVER: [HandClass.BELT, ""],
	Kind.ROUNDS: [HandClass.BELT, "items.stack_rounds"],
	Kind.CANARY: [HandClass.BELT, ""],
	Kind.NOTE: [HandClass.BOOK, ""],
}

## Not an item: NET-04's held bits show it filling both hands (MNR-13's fireman's carry).
const LOAD_BODY: int = 255
## VIS-06: NET-04's held bits, low byte: bit 6 set while that lamp's flame shows (lit and open).
const LAMP_LIT_BIT: int = 0x40

## Held in the free hand, these block every free-hand action but feeling, levers and phones
## (§4.7 for the drawn revolver; Proposed for a can and a lit flare).
const FREE_HAND_BLOCKERS: Array[Kind] = [Kind.REVOLVER, Kind.PARAFFIN_CAN, Kind.FLARE]
## The free-hand actions a blocker still allows.
const BLOCKER_EXCEPTIONS: Array[StringName] = [&"feel", &"lever", &"phone"]


static func is_kind(kind: int) -> bool:
	return TABLE.has(kind)


static func hand_class(kind: int) -> HandClass:
	return int(Variants.number(Variants.array(TABLE[kind])[0])) as HandClass


static func is_lamp(kind: int) -> bool:
	return kind == Kind.GAUZE_LAMP or kind == Kind.ELECTRIC_LAMP


## How many of a kind share one slot.
static func stack_size(kind: int) -> int:
	var key: String = str(Variants.array(TABLE[kind])[1])
	return Tuning.i(StringName(key) if not key.is_empty() else &"items.stack_default")


static func text_key(kind: int) -> String:
	return "item." + str(Kind.find_key(kind)).to_lower()
