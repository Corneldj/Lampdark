class_name TapperStrike
extends RefCounted
## CRT-09: the only Tapper code that reads the truth behind what it heard (SND-01's true source),
## as the design allows for the strike check and the Inquiry. It strikes only a conscious miner
## who is the true source of a heard event and within tapper.reach_tiles of a wall face where it
## waits; never on an apparent position alone. Lures and spoiled pulls are judged here too.

const VOICE_KINDS: Array[NoiseTypes.Type] = [NoiseTypes.Type.VOICE, NoiseTypes.Type.CALLOUT]


## The miner to strike, or 0: the true source of a heard event, conscious and not held by a
## grab, within reach of one of `faces`. Logs the strike's truth for the Inquiry.
static func target(run: RunState, t: Tapper, heard: Array[TapperHearing.HeardEvent], faces: Array[Vector2i]) -> int:
	var reach: float = Tuning.f(&"tapper.reach_tiles")
	for h: TapperHearing.HeardEvent in heard:
		var miner: int = int(Variants.number(t.hearing.truth_of(h).get("source", 0)))
		if not _conscious_miner(run, miner):
			continue
		var at: Vector2 = run.registry.get_entity(miner).position
		for face: Vector2i in faces:
			var d: float = square_distance(at, face)
			if d <= reach + 1e-9:
				t.system.log.add(run.tick, &"tapper_strike_check", {"miner": miner, "kind": h.kind, "level_np": h.level_np,
					"face": face, "distance": d})
				return miner
	return 0


## The hunt record (Proposed): on the true source of the sound that began it, if a miner; else 0.
static func hunt_target(t: Tapper, h: TapperHearing.HeardEvent) -> int:
	var miner: int = int(Variants.number(t.hearing.truth_of(h).get("source", 0)))
	return miner if t.system != null and miner != 0 and t.system.creature_of(miner) == null else 0


## A lure: a heard non-voice event of tapper.lure_np or more whose true source lies
## tapper.lure_min_tiles to _max_tiles by path from the pin. Returns {} or {miner} (0: nobody,
## as for a stone landing away from its thrower).
static func lure(run: RunState, t: Tapper, h: TapperHearing.HeardEvent, pin_tile: Vector2i) -> Dictionary:
	if VOICE_KINDS.has(h.kind) or h.level_np < Tuning.f(&"tapper.lure_np"):
		return {}
	var truth: Dictionary = t.hearing.truth_of(h)
	var where: Vector2i = truth.get("true_tile", pin_tile)
	var d: float = run.mine.path_distance(pin_tile, where, Tuning.f(&"tapper.lure_max_tiles") + 2.0).distance
	if d < Tuning.f(&"tapper.lure_min_tiles") - 1e-9 or d > Tuning.f(&"tapper.lure_max_tiles") + 1e-9 or d < 0.0:
		return {}
	var miner: int = int(Variants.number(truth.get("source", 0)))
	var reach_from: Vector2 = Vector2(where) + Vector2(0.5, 0.5)
	if not _conscious_miner(run, miner) or run.registry.get_entity(miner).position.distance_to(reach_from) > Tuning.f(&"tapper.reach_tiles"):
		miner = 0
	return {"miner": miner, "distance": d}


## Speech above a whisper (a voice or callout at talk band or louder) whose true source is within
## tapper.pull_spoil_radius_tiles by path of the pin: it spoils a silent pull.
static func spoils(run: RunState, t: Tapper, h: TapperHearing.HeardEvent, pin_tile: Vector2i) -> bool:
	if not VOICE_KINDS.has(h.kind) or h.level_np < Tuning.f(&"voice.talk_np") - 1e-9:
		return false
	var where: Vector2i = t.hearing.truth_of(h).get("true_tile", pin_tile)
	var d: float = run.mine.path_distance(pin_tile, where, Tuning.f(&"tapper.pull_spoil_radius_tiles") + 1.0).distance
	return d >= 0.0 and d <= Tuning.f(&"tapper.pull_spoil_radius_tiles") + 1e-9


static func square_distance(p: Vector2, tile: Vector2i) -> float:
	var cx: float = clampf(p.x, tile.x, tile.x + 1)
	var cy: float = clampf(p.y, tile.y, tile.y + 1)
	return p.distance_to(Vector2(cx, cy))


static func _conscious_miner(run: RunState, e: int) -> bool:
	if e == 0 or not run.registry.has(e) or run.registry.get_entity(e).kind != WorldIds.EntityKind.MINER:
		return false
	if run.miner_state == null or run.miner_state.miner(e) == null:
		return true
	var life: int = run.miner_state.life(e)
	return life == MinerTransitions.Life.UPRIGHT or life == MinerTransitions.Life.CAUGHT
