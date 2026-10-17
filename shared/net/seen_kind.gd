class_name SeenKind
extends RefCounted
## NET-04: what an identified entity is, as far as a client may know (identity needs 0.30 of
## light, VIS-03). Wire values: append only. The server maps its own entity kinds onto these.

enum Kind { UNKNOWN = 0, MINER = 1, STYTHE = 2, MOTH = 3, BESS = 4, TAPPER = 5, ITEM = 6, TRAP = 7, PHONE = 8, FIXTURE = 9, COAT_HEAP = 10, LEVER = 11,
	COLLAPSE_POINT = 12 }

## LFT-12: a phone's identity record carries its painted number (to 127) and what anyone beside it
## can tell: its bell ringing, or someone on it. Never its road home or a cut.
const PHONE_NUMBER_MASK: int = 0x7F
const PHONE_RINGING: int = 0x80
const PHONE_BUSY: int = 0x100

## The size classes of anonymous fringe tokens (VIS-03's): a token never says more than this.
enum Size { NONE = 0, MINER = 1, LARGE = 2, LARGE_MOTIONLESS = 3, SMALL = 4 }
