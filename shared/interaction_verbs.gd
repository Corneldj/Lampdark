class_name InteractionVerbs
extends RefCounted
## UI-01 and MNR-04: what interacting with a thing does, by what a client may know of it (its
## SeenKind and, for a miner, its cues). The client's interaction glyph and the server's feel answers
## (VIS-07) read the same table, so a glyph and a felt verb always agree. "" is nothing to do: a token,
## a coat heap, a creature, a trap or a fixture shows no glyph.


static func for_seen(kind: int, cues: int = 0) -> String:
	match kind:
		SeenKind.Kind.ITEM:
			return "verb.pick_up"
		SeenKind.Kind.MINER:
			return "verb.lift" if (cues & (MinerCues.LYING_BREATHING | MinerCues.LYING_STILL)) != 0 else "verb.ring"
		SeenKind.Kind.PHONE:
			return "verb.crank"
	return ""
