class_name ItemKinds
extends RefCounted
## MNR-04's item registry (Gameplay §4.3, §4.5-4.7, A.9): every kind of item a miner can find,
## with where it rides (hand class), its stack size (read from tuning) and its text key. Every
## item is a small thing (VIS-03): seen only at vision.small_thing_light_min, never a token.
## Behaviour lives in each owning ticket (MNR-06 to MNR-12, MNR-16, RSC-02). Wire values: append
## only. The stretcher, the drum gear and the tub are loads (MNR-14): ITEM entities of the LOAD
## class, never in a hand or a slot, moved only by Loads and Tubs. The lamp check, chalk and the
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
	STRETCHER = 22,
	DRUM_GEAR = 23,
	TUB = 24,
}

## Where a kind rides: a lamp (the lamp hand, else a slot), a belt slot, the free hand only (the
## paraffin can), the Pocket Book (found notes), or nowhere: a load lies where it is set down.
enum HandClass { LAMP = 0, BELT = 1, FREE_ONLY = 2, BOOK = 3, LOAD = 4 }

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
	Kind.STRETCHER: [HandClass.LOAD, ""],
	Kind.DRUM_GEAR: [HandClass.LOAD, ""],
	Kind.TUB: [HandClass.LOAD, ""],
}

## Not an item: NET-04's held bits show it filling both hands (MNR-13's fireman's carry).
const LOAD_BODY: int = 255
## MNR-14's held bits for both hands on a load: an end of a stretcher or the drum gear (the load
## shows as its own entity), and hold of a tub.
const LOAD_END: int = 254
const LOAD_TUB: int = 253
## MNR-14: a tub's lying record carries the cans in it in the high byte of its held bits.
const TUB_CANS_SHIFT: int = 8
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


## A load (MNR-14): never picked up, carried or pushed by Loads and Tubs.
static func is_load(kind: int) -> bool:
	return TABLE.has(kind) and hand_class(kind) == HandClass.LOAD


static func is_lamp(kind: int) -> bool:
	return kind == Kind.GAUZE_LAMP or kind == Kind.ELECTRIC_LAMP


## How many of a kind share one slot.
static func stack_size(kind: int) -> int:
	var key: String = str(Variants.array(TABLE[kind])[1])
	return Tuning.i(StringName(key) if not key.is_empty() else &"items.stack_default")


static func text_key(kind: int) -> String:
	return "item." + str(Kind.find_key(kind)).to_lower()
