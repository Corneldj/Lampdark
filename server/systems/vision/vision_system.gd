class_name VisionSystem
extends SimSystem
## VIS-03's seen sets (stage 12, VISIBILITY): every tick, for every watched miner, exactly what
## that miner perceives, from the facing NET-03 stamped on its input. The frame is the only door
## to NET-04's encoder; frame_for(slot) reads it. The work is native (LbVision): line of sight
## cached per miner, the cone, light thresholds, tokens by size class, the detail region and
## the edge glow. Server-only.

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


func _init(mine: Mine, light: LightSystem) -> void:
	native.attach(mine.native, light.grid)
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


func watched_entity(slot: int) -> int:
	return int(Variants.number(_watched.get(slot, 0)))


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
		native.set_turn_band(slot, turn_band_deg(float(Variants.number(rtt_ms.call(slot)))))
		frames[slot] = native.compute(slot)


## NET-12's turn band for a client with this round trip: how far its miner can turn (at
## movement.turn_rate_deg_s) before a frame computed now reaches it: the round trip, the input
## buffer, a tick and vision.turn_band_extra_s; at most vision.turn_band_max_deg each side.
static func turn_band_deg(rtt: float) -> float:
	var hz: float = Tuning.f(&"net.tick_hz")
	var lag_s: float = rtt / 1000.0 + Tuning.f(&"net.input_buffer_target_ticks") / hz + 1.0 / hz + Tuning.f(&"vision.turn_band_extra_s")
	return minf(Tuning.f(&"movement.turn_rate_deg_s") * lag_s, Tuning.f(&"vision.turn_band_max_deg"))


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
