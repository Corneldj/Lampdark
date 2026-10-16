class_name SheetKind
extends RefCounted
## LFT-14 and LFT-03: the sheets the crew draws on, each one of LFT-14's sheets kept at its own
## close-up, with the same tools, caps, sync and public rules: the map table's survey sheet and the
## Manual's pencil layer (LFT-15's map pages to come). A SHEET message names its sheet with a SELECT
## op before the ops for it; with none, its ops are the map table's.

enum Kind { MAP_TABLE = 0, MANUAL = 1 }

## Each sheet's close-up: only its readers draw on it and see its strokes as made.
const CLOSE_UPS: Dictionary = {Kind.MAP_TABLE: CloseupKind.Kind.MAP_TABLE, Kind.MANUAL: CloseupKind.Kind.MANUAL}
## Each sheet's run-level section in GEN-13's diff log.
const SECTIONS: Dictionary = {Kind.MAP_TABLE: "map_table", Kind.MANUAL: "manual"}
const COUNT: int = 2


static func close_up(kind: int) -> CloseupKind.Kind:
	var c: int = int(Variants.number(CLOSE_UPS.get(kind, CloseupKind.Kind.NONE)))
	return c as CloseupKind.Kind


static func is_valid(kind: int) -> bool:
	return kind >= 0 and kind < COUNT
