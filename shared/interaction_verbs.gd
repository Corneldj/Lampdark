class_name InteractionVerbs
extends RefCounted
## UI-01 and MNR-04: what interacting with a thing does, by what a client may know of it (its
## SeenKind and, for a miner, its cues). The client's interaction glyph and the server's feel answers
## (VIS-07) read the same table, so a glyph and a felt verb always agree. "" is nothing to do: a token,
## a coat heap, a creature, a trap or a fixture shows no glyph.


## `item_kind`: an item's kind, as its record's held field shows it (MNR-14's loads are taken, not
## picked up).
static func for_seen(kind: int, cues: int = 0, item_kind: int = 0) -> String:
	match kind:
		SeenKind.Kind.ITEM:
			if item_kind == ItemKinds.Kind.TUB:
				return "verb.take_hold"
			if item_kind == ItemKinds.Kind.STRETCHER or item_kind == ItemKinds.Kind.DRUM_GEAR:
				return "verb.take_end"
			return "verb.pick_up"
		SeenKind.Kind.MINER:
			return "verb.lift" if (cues & (MinerCues.LYING_BREATHING | MinerCues.LYING_STILL)) != 0 else "verb.ring"
		SeenKind.Kind.PHONE:
			return "verb.crank"
		SeenKind.Kind.LEVER:
			return "verb.lever"
	return ""
