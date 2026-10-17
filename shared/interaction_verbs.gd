class_name InteractionVerbs
extends RefCounted
## UI-01 and MNR-04: what interacting with a thing does, by what a client may know of it (its
## SeenKind and, for a miner, its cues). The client's interaction glyph and the server's feel answers
## (VIS-07) read the same table, so a glyph and a felt verb always agree. "" is nothing to do: a token,
## a coat heap, a creature or a trap shows no glyph. A fixture's verb is its kind's (never felt).


## `item_kind`: an item's or fixture's kind, as its record's held field shows it (MNR-14's loads are
## taken, not picked up; a fixture's verb is its kind's).
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
		SeenKind.Kind.FIXTURE:
			# LFT-06's tank, LFT-08's engine, LFT-10's cord, LFT-05's substation: the fixture's kind rides in the held field.
			match FixtureKinds.kind_of(item_kind):
				FixtureKinds.Kind.TANK_GLASS:
					return "verb.pour"
				FixtureKinds.Kind.ENGINE_PRIME:
					return "verb.prime"
				FixtureKinds.Kind.ENGINE_CRANK:
					return "verb.crank"
				FixtureKinds.Kind.ENGINE_THROTTLE:
					return "verb.throttle"
				FixtureKinds.Kind.CAGE_CORD:
					return "verb.pull_cord"
				# LFT-05's substation: the board's next step, the trip, the switch until closed.
				FixtureKinds.Kind.FUSE_BOARD:
					var board: Dictionary = FixtureKinds.read_fuse_board(item_kind)
					if not Variants.flag(board["cleared"]):
						return "verb.clear_links"
					return "" if Variants.flag(board["full"]) else "verb.fit_fuse"
				FixtureKinds.Kind.TRIP_LEVER:
					return "verb.hold_trip"
				FixtureKinds.Kind.MAIN_SWITCH:
					return "" if FixtureKinds.flag_of(item_kind) else "verb.throw"
		SeenKind.Kind.LEVER:
			return "verb.lever"
	return ""
