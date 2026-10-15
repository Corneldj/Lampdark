class_name TileBits
extends RefCounted
## VIS-03 and VIS-10: the bits a seen tile's record carries on the wire, shared by the server, the
## client and NET-08's audit (none of which may name another's classes). Decal byte: blood 1, chalk 2 (MNR-10: its glyphs follow it, ChalkMarks),
## line number 4, a blood trail's direction (0 east, clockwise with +y down) in bits 3-5, VIS-09's
## shading in bits 6-7. Colour byte: the light's colour class, and the egg-glow hatch tell in bit 7.
## The native vision (seen_set.h) uses the same values.

const DECAL_BLOOD: int = 1
const DECAL_CHALK: int = 2
const DECAL_LINE_NUMBER: int = 4
const DECAL_DIR_SHIFT: int = 3
const DECAL_DIR_MASK: int = 0x38
const COLOUR_HATCH_BIT: int = 0x80
