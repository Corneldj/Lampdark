class_name TapperHearing
extends RefCounted
## CRT-08: the Tapper's one sense, hearing through the Road Graph (SND-01) as a creature listener
## at the open tile nearest it, with its own tile's ring multiplier: it hears what reaches that
## wall face with noise.tapper_threshold (4 np) left, within (np - door losses - 4) x multiplier
## tiles of path. It learns each event's apparent position, with the players' error, and never
## an identity. Deaf to light, the knocks, other creatures and illusions (none of which reaches
## it as a Tapper event), and in a Fan surge to anything under noise.fan_creature_min_np.
## Deliveries carry SND-01's server-only true_source; this sense drops it: only CRT-09's strike
## check and the Inquiry log may read it, never movement or targeting.

## One heard event: no entity, no true source.
class HeardEvent:
	extends RefCounted
	var tick: int = 0
	var apparent: Vector2 = Vector2.ZERO
	var energy_np: float = 0.0
	var kind: NoiseTypes.Type = NoiseTypes.Type.NONE
	var duration_s: float = 0.5
	var path_tiles: float = 0.0
	## The level it was made at (a lure is 14 np or more at its source).
	var level_np: float = 0.0

## How far from the Tapper its listening tile (the nearest open floor) is looked for: deep in a
## rich mass the nearest road can be well over 10 tiles off.
const OPEN_SEARCH_TILES: int = 32

## SND-16's Fan surge: () -> bool. Default: none.
var fan_surge: Callable = func() -> bool: return false
var sense: HearingSense
## What it heard since the last take(), as HeardEvents.
var heard: Array[HeardEvent] = []
## HeardEvent -> {source, true_tile}: the truth behind each, for CRT-09's strike check alone
## (tapper_strike.gd) and the Inquiry. Movement and targeting never read it.
var _truth: Dictionary = {}
var _run: RunState


func _init(run: RunState, listener_id: int) -> void:
	_run = run
	sense = HearingSense.new(run, listener_id)
	if run.noise != null:
		run.noise.creature_hooks.append(_on_delivery)


## Moves the listening point to the open tile nearest the Tapper, with the multiplier of the
## ring its own tile is in.
func listen_from(tapper_position: Vector2) -> void:
	if _run.mine == null:
		return
	var found: Dictionary = _run.mine.native.nearest_open_tile(tapper_position, [], OPEN_SEARCH_TILES)
	var open: Vector2i = found["tile"] if Variants.flag(found.get("found", false)) else Vector2i(floori(tapper_position.x), floori(tapper_position.y))
	sense.listen_at(open, CreatureTables.tapper_hearing_mult(WorldCoords.ring_of_point(tapper_position)))


func take() -> Array[HeardEvent]:
	var out: Array[HeardEvent] = heard
	heard = []
	# The truth of older events is dropped as each tick's events are taken.
	var keep: Dictionary = {}
	for h: HeardEvent in out:
		if _truth.has(h):
			keep[h] = _truth[h]
	_truth = keep
	return out


## TapperStrike only: {source (entity, 0 for none), true_tile} of a heard event.
func truth_of(h: HeardEvent) -> Dictionary:
	return Variants.dict(_truth.get(h, {}))


func _on_delivery(event: NoiseSystem.Event, delivery: Dictionary) -> void:
	if int(Variants.number(delivery.get("listener", -1))) != sense.listener_id:
		return
	if _is_creature(event.source_entity):
		return
	if Variants.flag(fan_surge.call()) and event.level_np < Tuning.f(&"noise.fan_creature_min_np"):
		return
	var h: HeardEvent = HeardEvent.new()
	h.tick = event.tick
	h.apparent = delivery.get("apparent", Vector2.ZERO)
	h.energy_np = Variants.number(delivery.get("remaining_np", 0.0))
	h.kind = event.type
	h.duration_s = event.duration_s
	h.path_tiles = Variants.number(delivery.get("path_tiles", 0.0))
	h.level_np = event.level_np
	heard.append(h)
	_truth[h] = {"source": event.source_entity, "true_tile": delivery.get("true_source", Vector2i.ZERO)}


func _is_creature(entity: int) -> bool:
	if entity == 0:
		return false
	var e: SimEntity = _run.registry.get_entity(entity)
	return e != null and CreatureSystem.DOMAINS.has(e.kind)
