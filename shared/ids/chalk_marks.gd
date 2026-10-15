class_name ChalkMarks
extends RefCounted
## MNR-10: the chalk marks (Gameplay §4.5): an arrow, an X, a '!' and the digits 0-9 (13 kinds, in
## the wheel's order), and the surfaces a mark goes on. A mark is kept on the floor tile it was made
## from: the floor itself, or the rib face bordering it to the north, east, south or west. On the
## wire (TileBits.DECAL_CHALK) each surface is one glyph byte: PRESENT | kind (bits 0-3) | an
## arrow's direction (bits 4-6: 0 east, clockwise with +y down, as VIS-10's trails); 0 is none.
## Shared by the server, the client and NET-08's audit.

enum Kind {
	ARROW = 0,
	CROSS = 1,
	BANG = 2,
	DIGIT_0 = 3,
	DIGIT_1 = 4,
	DIGIT_2 = 5,
	DIGIT_3 = 6,
	DIGIT_4 = 7,
	DIGIT_5 = 8,
	DIGIT_6 = 9,
	DIGIT_7 = 10,
	DIGIT_8 = 11,
	DIGIT_9 = 12,
}

enum Surface {
	FLOOR = 0,
	NORTH = 1,
	EAST = 2,
	SOUTH = 3,
	WEST = 4,
}

const COUNT: int = 13
const SURFACES: int = 5
const PRESENT: int = 0x80
## A face's wall, from its floor tile.
const FACE_STEP: Dictionary = {Surface.NORTH: Vector2i(0, -1), Surface.EAST: Vector2i(1, 0), Surface.SOUTH: Vector2i(0, 1),
	Surface.WEST: Vector2i(-1, 0)}
const SURFACE_KEYS: Array[String] = ["f", "n", "e", "s", "w"]


static func glyph(kind: int, direction: int = 0) -> int:
	return PRESENT | (kind & 15) | ((posmod(direction, 8) & 7) << 4)


static func kind_of(g: int) -> int:
	return g & 15


static func direction_of(g: int) -> int:
	return (g >> 4) & 7


## The five glyph bytes packed as LbVision.set_chalk takes them (byte i for surface i).
static func pack(glyphs: PackedByteArray) -> int:
	var out: int = 0
	for s: int in mini(glyphs.size(), SURFACES):
		out |= (glyphs[s] & 0xFF) << (8 * s)
	return out


## A wheel slice (0-12) is the kind of the same index.
static func of_slice(index: int) -> int:
	return index if index >= 0 and index < COUNT else -1
