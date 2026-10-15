class_name FlameSnuff
extends RefCounted
## MNR-09: the one way to snuff a flame by its VIS-02 source (CRT-13's Stythe, hazards): a gauze
## lamp goes out through MNR-06, a candle keeps its remaining time (Candles.snuff), and any source
## flagged FLAG_BEYOND_SNUFF (a flare, §7.4) is refused. Every call is logged in `calls` for tests
## and soaks: {tick, source, kind, done}. Server-only.

static var calls: Array[Dictionary] = []


static func snuff(run: RunState, source: int, cause: String) -> bool:
	if run.light == null or not run.light.grid.has_source(source):
		return false
	var info: Dictionary = run.light.grid.source_info(source)
	var kind: String = str(info.get("kind", ""))
	var done: bool = false
	if (int(Variants.number(info.get("flags", 0))) & LbLightGrid.FLAG_BEYOND_SNUFF) == 0:
		if kind == Candles.KIND and run.candles != null:
			var it: Item = run.candles.item_of_source(run, source)
			done = it != null and run.candles.snuff(run, it, cause)
		elif kind == LampSystem.KIND and run.lamps != null:
			for uid: int in run.lamps.sorted_uids():
				var l: GauzeLamp = run.lamps.lamps[uid]
				if l.source == source:
					done = run.lamps.snuff(run, l, cause)
	calls.append({"tick": run.tick, "source": source, "kind": kind, "done": done})
	return done
