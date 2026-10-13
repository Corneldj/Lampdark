class_name FlameFlags
extends RefCounted
## VIS-08: a flame's states (Gameplay §5.7), as bits on the wire: on an identity record (the flame a
## miner carries, or a lamp lying or hanging) and in the owner's own block. Each is a distinct moving
## shape on the client (FlameStateView), never only colour; guttering also plays the sputter.

const TREMBLE: int = 1   ## an awake or stirring Moth within its tell reach (20 tiles)
const GUTTER: int = 2    ## the Stythe's tell within 10 tiles: radius x0.7 and the sputter
const CAP: int = 4       ## a gauze flame inside firedamp: the pale blue cap
const SHRINK: int = 8    ## inside blackdamp: 10% of R a second, out after 10 s
const FLARE_UP: int = 16 ## a naked flame entering firedamp's edge: tall and blue for 1 s
const ALL: int = 31

const NAMES: Dictionary = {TREMBLE: "tremble", GUTTER: "gutter", CAP: "cap", SHRINK: "shrink", FLARE_UP: "flare_up"}


static func names(bits: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for raw: Variant in NAMES.keys():
		if (bits & int(Variants.number(raw))) != 0:
			out.append(str(NAMES[raw]))
	return out
