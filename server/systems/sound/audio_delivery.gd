class_name AudioDelivery
extends RefCounted
## SND-03's server delivery stage. Every player delivery SND-02 makes (and every diffuse creature
## tell, and every local emitter) becomes one AudioRecord for that listener's client, which then
## runs the per-listener masks in registration order: each returns null (DROP: no record, no
## caption) or a change ({gain_db, flags}). Survivors go to NET-04's audio channel (`sink`). Masks
## register by name: SND-04's deafen, SND-16's fan, RSC-04's unconscious. Local emitters never touch
## SND-01's propagation, creatures or the collapse hook. A dev and QA delivery log (tick, client,
## event id, path tiles, via) feeds NET-08's audit. Server-only.

## Ambient layers.
const BASE_CAMP: StringName = AmbientMessages.BASE_CAMP
## The delivery log keeps this many entries (a ring).
const LOG_MAX: int = 4096

## (slot, AudioRecord) -> void: NET-04's channel (Replication.queue_audio); tests listen here too.
var sink: Callable = Callable()
## [name, Callable(run, slot, AudioRecord) -> Variant]
var masks: Array[Array] = []
## {tick, client, event_id, path_tiles, via}
var deliveries: Array[Dictionary] = []
## [slot, bytes] ambient cues for Replication to send on the control lane.
var outbox: Array[Array] = []
var _run: RunState = null


func bind(run: RunState) -> void:
	_run = run
	if run.noise != null:
		run.noise.player_hooks.append(_on_player_delivery)
	if run.creatures != null:
		run.creatures.tell_cue.connect(_on_tell_cue)


func register_mask(mask_name: String, fn: Callable) -> void:
	for m: Array in masks:
		if str(m[0]) == mask_name:
			m[1] = fn
			return
	masks.append([mask_name, fn])


## Runs the masks and hands a survivor to the sink; false if a mask dropped it.
func deliver(slot: int, record: AudioRecord, event_id: int = -1, path_tiles: float = 0.0, via: int = -1) -> bool:
	for m: Array in masks:
		var fn: Callable = m[1]
		var change: Variant = fn.call(_run, slot, record)
		if change == null:
			return false
		var c: Dictionary = Variants.dict(change)
		record.gain_db += int(Variants.number(c.get("gain_db", 0)))
		record.flags |= int(Variants.number(c.get("flags", 0)))
	deliveries.append({"tick": record.start_tick, "client": slot, "event_id": event_id, "path_tiles": path_tiles, "via": via})
	if deliveries.size() > LOG_MAX:
		deliveries.remove_at(0)
	if sink.is_valid():
		sink.call(slot, record)
	return true


## A local emitter (the firedamp hiss, the hatch's ticking): records only for the players within
## `radius_tiles` of `tile` (straight-line, or by walkable path with `by_path`), at the emitter's
## level, flagged LOCAL. No Road Graph event, no creature delivery, no collapse check.
func local(run: RunState, type: int, tile: Vector2i, radius_tiles: float, level_np: float, duration_s: float, by_path: bool = false) -> int:
	if run.movement == null:
		return 0
	var sent: int = 0
	var at: Vector2 = Vector2(tile) + Vector2(0.5, 0.5)
	for slot: int in run.movement.miner_slots():
		var m: MovementSystem.Miner = run.movement.miner(slot)
		var p: Vector2 = Vector2(m.state.x, m.state.y)
		var d: float = p.distance_to(at)
		if by_path and run.mine != null:
			var answer: Mine.PathAnswer = run.mine.path_distance(Vector2i(floori(p.x), floori(p.y)), tile, radius_tiles + 0.5)
			d = answer.distance if answer.distance >= 0.0 else INF
		if d > radius_tiles + 1e-9:
			continue
		var r: AudioRecord = AudioRecord.new()
		r.type = type
		r.start_tick = run.tick
		r.apparent = at
		r.level_np = level_np
		r.remaining_np = level_np
		r.duration_s = duration_s
		r.flags = AudioRecord.LOCAL
		if deliver(slot, r):
			sent += 1
	return sent


## An ambient bed layer starts or stops for one client (base camp's bed, DIR-02's cooling seam,
## MNR-11's silent canary).
func ambient(slot: int, layer: StringName, start: bool, fade_s: float = 1.0) -> void:
	outbox.append([slot, AmbientMessages.encode(layer, start, fade_s)])


## Base camp's bed follows its miners in and out (LFT-01's signals).
func follow_base_camp(run: RunState, camp: BaseCampState) -> void:
	camp.entered.connect(func(entity: int) -> void:
		var slot: int = _slot_of(run, entity)
		if slot >= 0:
			ambient(slot, BASE_CAMP, true))
	camp.left.connect(func(entity: int) -> void:
		var slot: int = _slot_of(run, entity)
		if slot >= 0:
			ambient(slot, BASE_CAMP, false))


func _on_player_delivery(listener: int, d: Dictionary, audit: Dictionary = {}) -> void:
	deliver(listener, AudioRecord.from_delivery(d), int(Variants.number(d.get("event_id", -1))),
		float(Variants.number(audit.get("path_tiles", 0.0))), int(Variants.number(audit.get("via", -1))))


## A diffuse tell (CRT-01): played from its wall points near the listener, never from the creature.
func _on_tell_cue(slot: int, cue: Dictionary) -> void:
	var kind: StringName = StringName(str(cue.get("tell", "")))
	var type: int = int(Variants.number(LocalSounds.TELLS.get(kind, LocalSounds.Type.NONE)))
	if type == LocalSounds.Type.NONE or _run == null:
		return
	var r: AudioRecord = AudioRecord.new()
	r.type = type
	r.start_tick = _run.tick
	r.flags = AudioRecord.DIFFUSE
	r.duration_s = Tuning.f(&"moth.stir_tell_s") if kind == &"moth_stir" else Tuning.f(&"noise.event_duration_s")
	# A tell is not a Road Graph sound: it arrives at full delivered level (0 / 0: no edge
	# attenuation on the client); the Tells bus and the tell volume option set its loudness.
	r.level_np = 0.0
	r.remaining_np = 0.0
	var pts: Array = Variants.array(cue.get("points", []))
	var sum: Vector2 = Vector2.ZERO
	for raw: Variant in pts:
		var t: Vector2i = raw
		var p: Vector2 = Vector2(t) + Vector2(0.5, 0.5)
		r.points.append(p)
		sum += p
	r.apparent = sum / maxf(1.0, pts.size()) if not pts.is_empty() else Vector2.ZERO
	deliver(slot, r)


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1
