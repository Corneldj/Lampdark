class_name VisionSystem
extends SimSystem
## VIS-03's seen sets (stage 12, VISIBILITY): every tick, for every watched miner, exactly what
## that miner perceives, from the facing NET-03 stamped on its input. The frame is the only door
## to NET-04's encoder; frame_for(slot) reads it. The work is native (LbVision): line of sight
## cached per miner, the cone, light thresholds, tokens by size class, the detail region and
## the edge glow. Server-only.

## GEN-13: a trail tile smeared (direction 0-7) or wiped (-1); the diff log keeps it.
signal trail_changed(tile: Vector2i, direction: int)

const CLASSES: String = "res://data/world/perception_classes.json"
const SIZES: Dictionary = {"none": 0, "miner": 1, "large": 2, "small": 4}

var native: LbVision = LbVision.new()
## slot -> the frame computed this tick (LbVision.compute's dictionary).
var frames: Dictionary = {}
## NET-12: (slot) -> the client's round trip in ms (ServerSystems wires it to the transport).
var rtt_ms: Callable = func(_slot: int) -> float: return 0.0
## slot -> the miner's entity id; slot -> the last facing used.
var _watched: Dictionary = {}
var _facing: Dictionary = {}
## slot -> {reason: true}
var _blind_reasons: Dictionary = {}
## VIS-10: (run) -> [{position: Vector2, thin: bool}], every Stythe whose tell plays (CRT-14: Hunt,
## WindUp, Drag, Collect; CRT-17 flags the Thin). None until the Stythe lands.
var bite_sources: Callable = func(_r: RunState) -> Array: return []
## VIS-10: this tick's bitten tiles (BiteSystem, after light pass 2), the same for every observer.
var bite_now: Array[Vector2i] = []
## VIS-10: blood trails, tile -> direction 0-7 (0 east, clockwise with +y down); GEN-13 keeps them,
## HAZ-03 erases them under a roof fall.
var trails: Dictionary = {}
## MNR-10: chalk by floor tile: its five glyph bytes (NET-08's audit compares what is sent).
var chalk: Dictionary = {}
## Decal bits by tile, as handed to the native frames (blood and its direction; chalk later).
var _decals: Dictionary = {}
## Whether the last tick handed observers a bite (so an ended bite is cleared once).
var _bite_applied: bool = false


func _init(mine: Mine, light: LightSystem) -> void:
	native.attach(mine.native, light.grid)
	# VIS-10: a cell evicted and loaded again gets its trails back (the record outlives the cell).
	mine.native.cell_loaded.connect(_on_cell_loaded)
	native.set_params({
		"cone_deg": Tuning.f(&"vision.cone_deg"),
		"seen_min": Tuning.f(&"vision.seen_light_min"),
		"identity_min": Tuning.f(&"vision.identity_light_min"),
		"small_min": Tuning.f(&"vision.small_thing_light_min"),
		"trail_min": Tuning.f(&"vision.trail_light_min"),
		"range": Tuning.f(&"vision.los_range_tiles"),
		"view_w": Tuning.f(&"camera.view_tiles_wide"),
		"view_h": Tuning.f(&"camera.view_tiles_high"),
		"squint_lead": Tuning.f(&"camera.squint_lead_tiles"),
		"detail_widen": Tuning.f(&"vision.detail_widen_tiles"),
		"bucket_deg": Tuning.f(&"vision.edge_glow_bucket_deg"),
		"margin_geometry": Tuning.f(&"vision.margin_geometry_tiles"),
		"margin_entity": Tuning.f(&"vision.margin_entity_tiles"),
	})
	_load_classes()
	# VIS-09: the shadow tell (bodies of miner size and up, the Stythe never).
	native.set_shadow_params({"enabled": true, "min_light": Tuning.f(&"light.shadow_min_light"),
		"lit_min": Tuning.f(&"vision.seen_light_min"), "levels": Tuning.i(&"light.shadow_levels"),
		"width": Tuning.f(&"light.shadow_width_tiles"), "never_cast": [WorldIds.EntityKind.STYTHE]})
	mine.native.tiles_changed.connect(native.on_tiles_changed)


func stage() -> int:
	return StageTable.Stage.VISIBILITY


func order() -> int:
	return 0


func system_name() -> String:
	return "vision"


## A miner's client sees through this entity from now on (MNR-01 calls it at spawn).
func watch(slot: int, entity_id: int, facing: int = 0) -> void:
	_watched[slot] = entity_id
	_facing[slot] = facing


func unwatch(slot: int) -> void:
	_watched.erase(slot)
	_facing.erase(slot)
	frames.erase(slot)
	native.remove_observer(slot)


## A client's view goes black while any reason holds (RSC-01's fall, UI-02's close-up): its seen
## set empties, so NET-04 sends only the own miner. Each reason is set and cleared on its own.
func set_blind(slot: int, reason: StringName, on: bool) -> void:
	var reasons: Dictionary = _blind_reasons.get(slot, {})
	if on:
		reasons[reason] = true
	else:
		reasons.erase(reason)
	_blind_reasons[slot] = reasons
	native.set_blinded(slot, not reasons.is_empty())


func is_blind(slot: int, reason: StringName = &"") -> bool:
	var reasons: Dictionary = _blind_reasons.get(slot, {})
	return reasons.has(reason) if reason != &"" else not reasons.is_empty()


func watched_entity(slot: int) -> int:
	return int(Variants.number(_watched.get(slot, 0)))


## Every watched miner's slot: entity -> slot (DIR-01 reads each one's seen set by it).
func slots_by_entity() -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in _watched.keys():
		out[int(Variants.number(_watched[raw]))] = int(Variants.number(raw))
	return out


## The slot watching `entity`, or -1.
func slot_of(entity: int) -> int:
	for raw: Variant in _watched.keys():
		if int(Variants.number(_watched[raw])) == entity:
			return int(Variants.number(raw))
	return -1


func tick(run: RunState) -> void:
	var slots: Array = _watched.keys()
	slots.sort()
	if not slots.is_empty():
		native.update_shadows()
	for raw: Variant in slots:
		var slot: int = int(Variants.number(raw))
		var entity: SimEntity = run.registry.get_entity(int(Variants.number(_watched[raw])))
		if entity == null:
			unwatch(slot)
			continue
		if run.movement != null and run.movement.miner(slot) != null:
			# MNR-01's authoritative facing: the input's, unless locked (the stretcher).
			_facing[slot] = run.movement.facing_of(slot)
		else:
			var consumed: InputBuffer.Consumed = run.input_for(slot)
			if consumed != null:
				_facing[slot] = consumed.record.facing
		native.set_observer(slot, entity.id, entity.position, int(Variants.number(_facing[slot])))
		# Only while there is a bite, or one to clear (tests may plant one straight into the native).
		if not bite_now.is_empty() or _bite_applied:
			native.set_bite_tiles(slot, bite_now)
		native.set_turn_band(slot, turn_band_deg(float(Variants.number(rtt_ms.call(slot)))))
		frames[slot] = native.compute(slot)
	_bite_applied = not bite_now.is_empty()


## NET-12's turn band for a client with this round trip: how far its miner can turn (at
## movement.turn_rate_deg_s) before a frame computed now reaches it: the round trip, the input
## buffer, a tick and vision.turn_band_extra_s; at most vision.turn_band_max_deg each side.
static func turn_band_deg(rtt: float) -> float:
	var hz: float = Tuning.f(&"net.tick_hz")
	var lag_s: float = rtt / 1000.0 + Tuning.f(&"net.input_buffer_target_ticks") / hz + 1.0 / hz + Tuning.f(&"vision.turn_band_extra_s")
	return minf(Tuning.f(&"movement.turn_rate_deg_s") * lag_s, Tuning.f(&"vision.turn_band_max_deg"))


## VIS-10: the bite round every Stythe whose tell plays: its floor tiles within
## vision.bite_range_tiles lit below vision.bite_below_light (the Thin: _thin).
func compute_bite(run: RunState) -> void:
	var tiles: Dictionary = {}
	for raw: Variant in Variants.array(bite_sources.call(run)):
		var src: Dictionary = Variants.dict(raw)
		var below: float = Tuning.f(&"vision.bite_below_light_thin") if Variants.flag(src.get("thin", false)) else Tuning.f(&"vision.bite_below_light")
		var at: Vector2 = src["position"]
		for t: Vector2i in native.bite_tiles(at, roundi(Tuning.f(&"vision.bite_range_tiles")), below):
			tiles[t] = true
	var keys: Array = tiles.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	bite_now.clear()
	for t: Vector2i in keys:
		bite_now.append(t)


## VIS-10, for DIR-01: the last frame of `miner`'s slot left out a bitten tile it would have seen.
func bite_seen_by(miner: int) -> bool:
	for raw: Variant in _watched.keys():
		if int(Variants.number(_watched[raw])) == miner:
			return native.bite_seen(int(Variants.number(raw)))
	return false


## DIR-01: how far, in tiles, from `miner` to the nearest such bitten tile; -1 if none.
func bite_seen_at(miner: int) -> float:
	var slot: int = slot_of(miner)
	return native.bite_seen_at(slot) if slot >= 0 else -1.0


## MNR-10: a floor tile's chalk (ChalkMarks' five glyph bytes; all zero clears it). Sent only with
## the chalk bit, at the small-thing threshold (0.30), never as a token.
func set_chalk(tile: Vector2i, glyphs: PackedByteArray) -> void:
	var packed: int = ChalkMarks.pack(glyphs)
	native.set_chalk(tile, packed)
	var bits: int = int(Variants.number(_decals.get(tile, 0))) & ~TileBits.DECAL_CHALK
	_set_decal_bits(tile, bits | (TileBits.DECAL_CHALK if packed != 0 else 0))
	if packed != 0:
		chalk[tile] = glyphs
	else:
		chalk.erase(tile)


## VIS-10: a blood trail on `tile`, heading `direction` (0-7); where trails cross, the latest wins.
func mark_trail(tile: Vector2i, direction: int) -> void:
	trails[tile] = posmod(direction, 8)
	trail_changed.emit(tile, posmod(direction, 8))
	var bits: int = int(Variants.number(_decals.get(tile, 0))) & ~(TileBits.DECAL_BLOOD | TileBits.DECAL_DIR_MASK)
	_set_decal_bits(tile, bits | TileBits.DECAL_BLOOD | (posmod(direction, 8) << TileBits.DECAL_DIR_SHIFT))


## HAZ-03: a roof fall erases a trail.
func erase_trail(tile: Vector2i) -> void:
	trails.erase(tile)
	trail_changed.emit(tile, -1)
	_set_decal_bits(tile, int(Variants.number(_decals.get(tile, 0))) & ~(TileBits.DECAL_BLOOD | TileBits.DECAL_DIR_MASK))


## The trail direction (0-7) of a move from `from` to `to`: the octant of the heading, decided by
## comparisons only (tan 22.5 degrees), so every platform agrees.
static func trail_direction(from: Vector2, to: Vector2) -> int:
	var d: Vector2 = to - from
	var ax: float = absf(d.x)
	var ay: float = absf(d.y)
	const TAN_22_5: float = 0.41421356
	if ay <= ax * TAN_22_5:
		return 0 if d.x >= 0.0 else 4
	if ax <= ay * TAN_22_5:
		return 2 if d.y >= 0.0 else 6
	if d.x >= 0.0:
		return 1 if d.y >= 0.0 else 7
	return 3 if d.y >= 0.0 else 5


func _on_cell_loaded(cell: Vector2i) -> void:
	for raw: Variant in _decals.keys():
		var t: Vector2i = raw
		if WorldCoords.cell_of(t) == cell:
			native.set_decals(t, int(Variants.number(_decals[raw])))


## Decal bits by tile as the frames get them (NET-08's audit compares against these).
func decal_bits() -> Dictionary:
	return _decals


func _set_decal_bits(tile: Vector2i, bits: int) -> void:
	if bits == 0:
		_decals.erase(tile)
	else:
		_decals[tile] = bits
	native.set_decals(tile, bits)


## This tick's frame for a slot, or {} if it has none.
func frame_for(slot: int) -> Dictionary:
	return Variants.dict(frames.get(slot, {}))


func _load_classes() -> void:
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(CLASSES)))
	native.set_motionless_flag(int(Variants.number(Variants.dict(doc.get("flags", {})).get("motionless", 1))))
	var classes: Dictionary = Variants.dict(doc.get("classes", {}))
	for raw: Variant in classes.keys():
		var name: String = str(raw)
		if not WorldIds.EntityKind.has(name):
			push_error("VisionSystem: %s names no entity kind" % name)
			continue
		var c: Dictionary = Variants.dict(classes[raw])
		var size: String = str(c.get("size", "none"))
		if not SIZES.has(size):
			push_error("VisionSystem: %s has an unknown size '%s'" % [name, size])
			continue
		native.set_perception_class(int(Variants.number(WorldIds.EntityKind[name])), int(Variants.number(SIZES[size])),
			int(Variants.number(c.get("footprint", 1))), float(Variants.number(c.get("identity_min", -1.0))),
			Variants.flag(c.get("motionless", false)))
