class_name HeardTracker
extends SimSystem
## SND-09: being heard (Gameplay §6.4, A.3; GDD §15.4, §15.5). Each miner carries a hidden unheard
## timer, reset only when their voice, a callout, a rock tap or their phone call truly reaches a
## conscious teammate. An utterance (onset to END, split every voice.utterance_split_s) counts when
## at least voice.heard_min_fraction of its frames were forwarded to one eligible listener: a human
## Upright (Hurt or not), Caught or Grabbed, not deafened and not a Hired Hand. The unconscious and
## the dead never count, and voice through a shut door or gate has no route, so it is never
## forwarded. Delivery results alone decide it: no listener's client setting (mute, volume) is
## ever read. Predicates (RSC-09's lone human with a Hand, MOD-07's Bess) may also count an
## utterance or callout. SND-11, SND-12 and LFT-12 call mark_heard() for callouts, taps and live
## calls; nothing else resets the timer (gasps, coughs, the breath-hold, the Aside and the Echo's
## repeats never call it). Voice arrives between ticks: an utterance heard becomes a voice fact,
## marked on the next tick (VoiceFacts). The timer starts at run start and restarts on a revive. Server-only:
## no query reaches a client, and NET-04 has no field for it.

## Emitted when `slot` is heard (cause: one of CAUSES).
signal heard(slot: int, cause: StringName)

## What may count as being heard.
const CAUSES: Array[StringName] = [&"voice", &"callout", &"tap", &"call"]

## MOD-08: (slot) -> bool, true for a Hired Hand. Stub: none.
var is_hand: Callable = func(_slot: int) -> bool: return false
## NET-07's run record: {tick, slot, cause}, every time a miner is heard (the Inquiry's
## "Last heard", "Unheard for").
var heard_log: Array[Dictionary] = []
## NET-07 and STM-08: slot -> PackedFloat64Array of seconds received per band (index 1-4).
var band_seconds: Dictionary = {}
## QA-04's telemetry: utterances evaluated, and those never heard.
var utterances: int = 0
var utterances_unheard: int = 0
## slot -> the tick its timer counts from (absent: run start, tick 0).
var _since: Dictionary = {}
## name -> Callable(speaker slot, kind (&"voice" or &"callout"), band) -> bool
var _predicates: Dictionary = {}
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.ROAD_GRAPH


func order() -> int:
	return 40


func system_name() -> String:
	return "heard"


func bind(run: RunState) -> void:
	_run = run
	if run.voice != null:
		run.voice.band_heard.connect(_on_band)
		run.voice.utterance_closed.connect(on_utterance)
	if run.miner_state != null:
		run.miner_state.state_changed.connect(_on_state_changed)


## RSC-09 and MOD-07: an extra way to be heard (a lone human within 4 tiles of a Hand; Bess).
func register_heard_predicate(predicate_name: String, fn: Callable) -> void:
	_predicates[predicate_name] = fn


## A callout, tap or live call (both ends) that truly reached a conscious teammate; or voice.
## False, and nothing changes, for anything else (a gasp, a cough, the Aside never count).
func mark_heard(slot: int, cause: StringName) -> bool:
	if not CAUSES.has(cause):
		return false
	var now: int = _now()
	_since[slot] = now
	heard_log.append({"tick": now, "slot": slot, "cause": cause})
	heard.emit(slot, cause)
	return true


## SND-11: whether a callout counts: its mask kept at least half of it for an eligible listener,
## or a predicate holds.
func callout_counts(speaker: int, kept_by_listener: Dictionary, band: int) -> bool:
	return _counts(speaker, &"callout", kept_by_listener, 1, band)


## The voice evaluation: VoiceSystem's utterance windows.
func on_utterance(slot: int, frames: int, delivered: Dictionary, band: int, _ended: bool) -> void:
	if frames <= 0:
		return
	utterances += 1
	if _counts(slot, &"voice", delivered, frames, band):
		_run.voice_facts.add(VoiceFacts.HEARD, slot, 0)  # marked on the next tick, and logged
	else:
		utterances_unheard += 1


## Seconds since `slot` was last heard (or since run start, or its revive).
func unheard_seconds(slot: int) -> float:
	return (_now() - int(Variants.number(_since.get(slot, 0)))) / Tuning.f(&"net.tick_hz")


## Past the unheard mark: voice.unheard_mark_s, or voice.unheard_mark_deep_s from
## voice.unheard_mark_deep_ring down, by the ring of the miner's own tile (CRT-13 adds "unlit" and
## "in hunting range").
func past_unheard_mark(slot: int) -> bool:
	var limit: float = Tuning.f(&"voice.unheard_mark_s")
	var m: MovementSystem.Miner = _run.movement.miner(slot) if _run != null and _run.movement != null else null
	if m != null and _run.registry.has(m.entity_id):
		var ring: int = WorldCoords.ring_of_point(_run.registry.get_entity(m.entity_id).position)
		if ring >= roundi(Tuning.f(&"voice.unheard_mark_deep_ring")):
			limit = Tuning.f(&"voice.unheard_mark_deep_s")
	return unheard_seconds(slot) > limit


## A conscious human teammate: Upright (Hurt or not), Caught or Grabbed; not deafened, not a Hand.
func eligible_listener(slot: int) -> bool:
	if _run == null or _run.movement == null:
		return false
	var m: MovementSystem.Miner = _run.movement.miner(slot)
	if m == null or Variants.flag(is_hand.call(slot)):
		return false
	if _run.deafen != null and _run.deafen.is_deafened(slot):
		return false
	if _run.miner_state == null:
		return true
	var life: int = _run.miner_state.life(m.entity_id)
	return life == MinerTransitions.Life.UPRIGHT or life == MinerTransitions.Life.CAUGHT or life == MinerTransitions.Life.GRABBED


func _counts(speaker: int, kind: StringName, delivered: Dictionary, total: int, band: int) -> bool:
	var need: float = Tuning.f(&"voice.heard_min_fraction")
	for raw: Variant in delivered.keys():
		var listener: int = int(Variants.number(raw))
		if listener == speaker or not eligible_listener(listener):
			continue
		if float(Variants.number(delivered[raw])) >= need * total - 1e-9:
			return true
	var names: Array = _predicates.keys()
	names.sort()
	for name: Variant in names:
		var fn: Callable = _predicates[name]
		if Variants.flag(fn.call(speaker, kind, band)):
			return true
	return false


func _on_band(slot: int, band: int) -> void:
	if band <= 0 or band > VoicePackets.MAX_BAND:
		return
	var secs: PackedFloat64Array = band_seconds.get(slot, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	secs[band] += VoicePackets.FRAME_S
	band_seconds[slot] = secs


## A revive (Unconscious to Upright) restarts the timer; it is not being heard.
func _on_state_changed(entity: int, old: int, new: int, _cause: String) -> void:
	if old != MinerTransitions.Life.UNCONSCIOUS or new != MinerTransitions.Life.UPRIGHT or _run.movement == null:
		return
	for slot: int in _run.movement.miner_slots():
		if _run.movement.miner(slot).entity_id == entity:
			_since[slot] = _now()


func _now() -> int:
	return _run.tick if _run != null else 0


func write_state(writer: SimStateWriter) -> void:
	var slots: Array = _since.keys()
	slots.sort()
	writer.put_i64(slots.size())
	for raw: Variant in slots:
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(int(Variants.number(_since[raw])))


func read_state(reader: SimStateReader) -> void:
	_since.clear()
	for _i: int in reader.get_i64():
		var slot: int = reader.get_i64()
		_since[slot] = reader.get_i64()
