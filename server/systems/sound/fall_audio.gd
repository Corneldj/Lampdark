class_name FallAudio
extends SimSystem
## SND-15: the fall is heard, then the line is cut (Gameplay §6.8, §11.2, A.3; GDD §15.5). On RSC-01's
## `fell` (or MNR-03's state_changed from a conscious state straight to Dead):
## - The scream (FallCause.Scream FULL): the fallen's voice goes out on the FALL_SCREAM route for
##   voice.fall_scream_s, at shout range whatever the band and exempt from loss. With no voice on
##   the mic (Mute, push-to-talk up, silence: VoiceSystem.mic_live) their character's scream line
##   is also sent, as a FALL_SCREAM record in their voice, to the listeners a shout reaches. A drag
##   victim (MUFFLED_WHISPER) screams muffled at whisper range (FALL_MUFFLED). The rock hears one
##   voice.scream_np event at the fall tile. A revolver hit or a Hired Hand (NONE) has no scream.
## - The cut: the route becomes CUT when the scream ends (at once without one): the fallen's voice
##   reaches no living listener, phone lines included, and makes no band events. A revive lifts it;
##   RSC-04 opens coming-round windows.
## - The knocks: voice.knock_delay_s after every fall (screaming or not, so their timing tells no
##   cause), one field-free KNOCKS message to every conscious human miner but the fallen, wherever
##   they are: no Road Graph event, no creature, no mask. `fall_heard` fires per hearer (DIR-01's
##   +15) and `fall_sounded` once (STM-11's Timeline marker). An unconscious miner shot dead makes
##   no second set.

## A conscious miner heard the knocks of `fall_id` (DIR-01).
signal fall_heard(miner: int, fall_id: int)
## A fall's knocks were sent (STM-11).
signal fall_sounded(fall_id: int)

const SCREAM_END: int = 0
const KNOCKS: int = 1

## SND-13 and MOD-01: a slot's character voice (0-7). Stub: the default for the player's identity.
var voice_of: Callable = Callable()
## Slots owed a KNOCKS message this tick (Replication sends them).
var outbox: Array[int] = []
## Telemetry and tests: knocks messages queued, falls sounded.
var knocks_sent: int = 0
var falls_sounded: int = 0
## [due tick, kind, miner entity, slot, fall id], in the order scheduled.
var _pending: Array[Array] = []
## Falls straight to Dead get ids of their own (RSC-01 numbers only falls to Unconscious).
var _next_death_id: int = -1
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.FALLS


func order() -> int:
	return 40


func system_name() -> String:
	return "fall_audio"


func bind(run: RunState) -> void:
	_run = run
	if run.falls != null:
		run.falls.fell.connect(_on_fell)
	if run.miner_state != null:
		run.miner_state.state_changed.connect(_on_state_changed)


func tick(run: RunState) -> void:
	var keep: Array[Array] = []
	for p: Array in _pending:
		if run.tick < int(Variants.number(p[0])):
			keep.append(p)
			continue
		var miner: int = p[2]
		var slot: int = p[3]
		match int(Variants.number(p[1])):
			SCREAM_END:
				var route: int = int(Variants.number(run.voice.route_of.get(slot, VoiceRoutes.Route.NORMAL)))
				if route == VoiceRoutes.Route.FALL_SCREAM or route == VoiceRoutes.Route.FALL_MUFFLED:
					run.voice.set_route(slot, VoiceRoutes.Route.CUT)
			KNOCKS:
				_send_knocks(miner, int(Variants.number(p[4])))
	_pending = keep


func _on_fell(record: Dictionary) -> void:
	var miner: int = int(Variants.number(record["miner_id"]))
	var tile: Vector2i = record["tile"]
	_sound(miner, int(Variants.number(record["fall_id"])), int(Variants.number(record["scream_mode"])), tile)


func _on_state_changed(entity: int, old: int, new: int, cause: String) -> void:
	if new == MinerTransitions.Life.DEAD and _conscious(old):
		var scream: int = FallCause.Scream.FULL
		var c: int = FallCause.from_state_cause(cause)
		if c == FallCause.Cause.SHOT_DEAD or c == FallCause.Cause.FRIENDLY_HIT or _is_hand(entity):
			scream = FallCause.Scream.NONE
		var e: SimEntity = _run.registry.get_entity(entity)
		_sound(entity, _next_death_id, scream, e.tile() if e != null else Vector2i.ZERO)
		_next_death_id -= 1
	elif old == MinerTransitions.Life.UNCONSCIOUS and new == MinerTransitions.Life.UPRIGHT:
		var slot: int = _slot_of(entity)
		if slot >= 0 and _run.voice != null:
			_run.voice.set_route(slot, VoiceRoutes.Route.NORMAL)  # revived: the voice is back
		var keep: Array[Array] = []
		for p: Array in _pending:
			if int(Variants.number(p[1])) != SCREAM_END or int(Variants.number(p[2])) != entity:
				keep.append(p)
		_pending = keep


func _sound(miner: int, fall_id: int, scream: int, tile: Vector2i) -> void:
	var hz: float = Tuning.f(&"net.tick_hz")
	var slot: int = _slot_of(miner)
	if slot >= 0 and _run.movement != null:
		_run.movement.set_breath_hold(slot, false)  # a held breath ends with the fall, no gasp
	if scream != FallCause.Scream.NONE:
		var opts: Dictionary = {"source": miner, "players": false, "mode": RoadGraphService.MODE_VOICE}
		if slot >= 0:
			opts["voice_id"] = _voice(slot)
		_run.noise.emit(NoiseTypes.Type.FALL_SCREAM, tile, opts)  # the rock hears one scream
		if slot >= 0 and _run.voice != null:
			var muffled: bool = scream == FallCause.Scream.MUFFLED_WHISPER
			if not _run.voice.mic_live(slot):
				_character_scream(slot, muffled)
			_run.voice.set_route(slot, VoiceRoutes.Route.FALL_MUFFLED if muffled else VoiceRoutes.Route.FALL_SCREAM)
			_pending.append([_run.tick + roundi(Tuning.f(&"voice.fall_scream_s") * hz), SCREAM_END, miner, slot, fall_id])
	elif slot >= 0 and _run.voice != null:
		_run.voice.set_route(slot, VoiceRoutes.Route.CUT)
	_pending.append([_run.tick + roundi(Tuning.f(&"voice.knock_delay_s") * hz), KNOCKS, miner, slot, fall_id])


## No voice on the mic: the character's scream line, to every living listener a shout (or, muffled,
## a whisper) reaches by road or rock, as SND-07 would route the voice. SND-03's masks still apply
## (a deafened listener gets nothing; SND-16's Fan).
func _character_scream(slot: int, muffled: bool) -> void:
	if _run.road_graph == null or _run.audio == null:
		return
	var m: MovementSystem.Miner = _run.movement.miner(slot)
	if m == null or not _run.registry.has(m.entity_id):
		return
	var from: SimEntity = _run.registry.get_entity(m.entity_id)
	var band: int = 1 if muffled else 3
	for other: int in _run.movement.miner_slots():
		var om: MovementSystem.Miner = _run.movement.miner(other)
		if other == slot or om == null or not _run.registry.has(om.entity_id):
			continue
		if _run.miner_state != null and _run.miner_state.life(om.entity_id) == MinerTransitions.Life.DEAD:
			continue
		var to: SimEntity = _run.registry.get_entity(om.entity_id)
		var r: Dictionary = VoiceRoutes.reach(_run.road_graph.graph, from.tile(), from.position, to.tile(), band, other)
		if r.is_empty():
			continue
		var record: AudioRecord = AudioRecord.new()
		record.type = NoiseTypes.Type.FALL_SCREAM
		record.start_tick = _run.tick
		record.apparent = r["position"]
		record.level_np = Tuning.f(&"voice.scream_np")
		record.remaining_np = record.level_np  # its level is the voice's gain, as live voice's
		record.duration_s = Tuning.f(&"voice.fall_scream_s")
		record.voice = _voice(slot)
		record.gain_db = roundi(float(Variants.number(r["gain_db"])))
		if muffled or Variants.flag(r["muffled"]):
			record.flags |= AudioRecord.MUFFLED
		_run.audio.deliver(other, record)


## Every conscious human miner but the fallen, wherever they are.
func _send_knocks(fallen: int, fall_id: int) -> void:
	var slots: Array[int] = _run.movement.miner_slots() if _run.movement != null else ([] as Array[int])
	slots.sort()
	for slot: int in slots:
		var m: MovementSystem.Miner = _run.movement.miner(slot)
		if m == null or m.entity_id == fallen or _is_hand(m.entity_id):
			continue
		if _run.miner_state != null and not _conscious(_run.miner_state.life(m.entity_id)):
			continue
		outbox.append(slot)
		knocks_sent += 1
		fall_heard.emit(m.entity_id, fall_id)
	falls_sounded += 1
	fall_sounded.emit(fall_id)


func _conscious(life: int) -> bool:
	return life == MinerTransitions.Life.UPRIGHT or life == MinerTransitions.Life.CAUGHT or life == MinerTransitions.Life.GRABBED


func _is_hand(entity: int) -> bool:
	return _run.crew != null and Variants.flag(_run.crew.is_hand_driven.call(entity))


func _slot_of(entity: int) -> int:
	if _run.miner_state != null and _run.miner_state.miner(entity) != null and _run.miner_state.miner(entity).slot >= 0:
		return _run.miner_state.miner(entity).slot
	if _run.movement != null:
		for slot: int in _run.movement.miner_slots():
			if _run.movement.miner(slot).entity_id == entity:
				return slot
	return -1


## SND-13's voice index for a slot (SND-11's callouts speak in it too).
func voice_for(slot: int) -> int:
	return _voice(slot)


func _voice(slot: int) -> int:
	if voice_of.is_valid():
		return int(Variants.number(voice_of.call(slot)))
	if _run.replication != null:
		for session: Sessions.Session in _run.replication.net.sessions.welcomed():
			if session.slot == slot:
				return VoiceAssignment.default_for(session.identity)
	return VoiceAssignment.default_for(str(slot))


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(_next_death_id)
	writer.put_i64(_pending.size())
	for p: Array in _pending:
		for v: Variant in p:
			writer.put_i64(int(Variants.number(v)))


func read_state(reader: SimStateReader) -> void:
	_next_death_id = reader.get_i64()
	_pending.clear()
	for _i: int in reader.get_i64():
		var p: Array = []
		for _j: int in 5:
			p.append(reader.get_i64())
		_pending.append(p)
