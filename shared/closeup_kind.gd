class_name CloseupKind
extends RefCounted
## UI-02: the close-ups (Gameplay §14.3) and their wire form. The server holds which one a miner
## reads and tells that miner's client alone (Protocol.Msg.CLOSE_UP, control lane): the kind, and
## the board's seat (sitting down or standing up, 2 s each). The client asks with an
## ActionRecord.Kind.CLOSE_UP: CLOSE (Esc or B; at the board, stand up), OPEN_POCKET_BOOK (M, or
## View tapped) or STAY_SEATED (the board's stand cancelled). The table, the Manual and the board
## open from an interact at their fixture. Nothing here says what a close-up shows.

enum Kind { NONE = 0, MAP_TABLE = 1, POCKET_BOOK = 2, MANUAL = 3, SWITCHBOARD = 4 }
## The board's seat: getting into it, or out of it.
enum Seat { NONE = 0, SITTING = 1, STANDING = 2 }
## ActionRecord.Kind.CLOSE_UP's argument.
enum Ask { CLOSE = 0, OPEN_POCKET_BOOK = 1, STAY_SEATED = 2 }

const NAMES: Array[String] = ["none", "map_table", "pocket_book", "manual", "switchboard"]


static func name_of(kind: int) -> String:
	return NAMES[kind] if kind >= 0 and kind < NAMES.size() else "none"


## Two bytes: the kind and the seat.
static func encode(kind: Kind, seat: Seat) -> PackedByteArray:
	return PackedByteArray([kind, seat])


## {kind, seat}, or {} when malformed.
static func decode(payload: PackedByteArray) -> Dictionary:
	if payload.size() != 2 or payload[0] >= NAMES.size() or payload[1] > Seat.STANDING:
		return {}
	return {"kind": payload[0], "seat": payload[1]}
