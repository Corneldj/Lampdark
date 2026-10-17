class_name CalloutSystem
extends SimSystem
## SND-11 (stage INPUTS, after UI-02's close-ups): callouts (Gameplay §6.7, GDD §15.5). A pick
## (ActionRecord.Kind.CALLOUT: the slice's angle and the ring's distance, or the timing) becomes a
## line at whisper, talk or shout, spoken from the miner's mouth: SND-07's routes at that band for
## the speaker's route (dragged: muffled to whisper range), SND-08's seeded drop mask for each
## listener's loss rate, and a CalloutRecord to each, whole down a live phone line. Its Road Graph
## events (as voice, at the band's np, from onset every noise.voice_event_interval_s for the bark's
## length) never drop and reach creatures only: players hear the bark itself. The speaker is heard
## (SND-09) when a conscious teammate keeps at least voice.heard_min_fraction of it.
##
## Refused, with no sound and no event: during the Aside or a held breath (Proposed), unconscious or
## dead, at no band (the centre cancels; nothing screams), from the wrong page for the miner's state
## (the job page while carrying two-handed or at a two-miner job), or while the miner's last bark
## still plays (Proposed). Grabbed and Caught miners may call. Nothing parses speech; nothing marks.

## ([run, entity]) -> bool: LFT-04 says the miner stands at a two-miner job (the job page).
var at_two_miner_job: Callable = func(_r: RunState, _entity: int) -> bool: return false
## Every callout spoken: {id, tick, slot, line, band, frames, until, tile, position, utterance}.
var spoken: Array[Dictionary] = []
## This tick's records as sent, [slot, bytes] (NET-08's audit and the tests read them).
var sent: Array[Array] = []
var refused: Dictionary = {}
var _net: ServerNet = null
var _run: RunState = null
## slot -> the tick its bark ends.
var _until: Dictionary = {}
## Barks still sounding: [slot, entity, np, next event tick, end tick].
var _sounding: Array[Array] = []
var _next_id: int = 1


func stage() -> int:
	return StageTable.Stage.INPUTS


func order() -> int:
	return 20


func system_name() -> String:
	return "callouts"


func bind(run: RunState, net: ServerNet) -> void:
	_run = run
	_net = net


func tick(run: RunState) -> void:
	_run = run
	sent.clear()
	if run.movement == null:
		return
	for slot: int in run.movement.miner_slots():
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null:
			continue
		for a: ActionRecord in c.actions:
			if a.kind != ActionRecord.Kind.CALLOUT:
				continue
			var pick: Dictionary = Intents.decode_wheel_arg(a.arg)
			var band: int = CalloutLines.band_of(pick)
			var entity: int = run.movement.miner(slot).entity_id
			var angle: float = float(a.aim) / 65536.0 * 360.0
			if run.dark != null and run.dark.in_window(entity):
				# RSC-04: coming round, the wheel offers 'Help!' and a moan, each at its own band.
				var said: String = CalloutLines.COMING_ROUND[CalloutLines.slice(angle, CalloutLines.COMING_ROUND.size())]
				if speak(run, slot, said, CalloutLines.coming_round_band(said), false, true) > 0 and said == "help":
					var f: DarkSystem.Fallen = run.dark.fallen[entity]
					f.window_help = true
				continue
			var page: bool = job_page(run, entity)
			var line: String = CalloutLines.line_at(angle, page)
			speak(run, slot, line, band, (c.record.holds & InputRecord.HOLD_BREATH) != 0)
	_sound_on(run)


## Whether the miner's wheel is the job page: carrying two-handed, or at a two-miner job (LFT-04).
func job_page(run: RunState, entity: int) -> bool:
	if run.inventory != null and run.inventory.hands_of(entity).two_handed:
		return true
	return Variants.flag(at_two_miner_job.call(run, entity))


## One callout from `slot` (also RSC-04's forced 'Help!' with `forced`). Returns the callout's id,
## or 0 when refused (the reason counted in `refused`).
func speak(run: RunState, slot: int, line: String, band: int, holding_breath: bool = false, forced: bool = false) -> int:
	var why: String = _refusal(run, slot, line, band, holding_breath, forced)
	if not why.is_empty():
		refused[why] = int(Variants.number(refused.get(why, 0))) + 1
		return 0
	var entity: int = run.movement.miner(slot).entity_id
	var voice_id: String = _voice_of(run, slot)
	var form: String = CalloutLines.form_of(line, band)
	var frames: int = maxi(1, VoiceManifest.frames_of(voice_id, line, form))
	var hz: float = Tuning.f(&"net.tick_hz")
	var duration_ticks: int = maxi(1, ceili(frames * VoicePackets.FRAME_S * hz))
	var e: SimEntity = run.registry.get_entity(entity)
	var id: int = _next_id
	_next_id += 1
	var utterance: int = 0x5C000000 + id
	var entry: Dictionary = {"id": id, "tick": run.tick, "slot": slot, "line": line, "band": band, "frames": frames,
		"until": run.tick + duration_ticks, "tile": e.tile(), "position": e.position, "utterance": utterance, "voice": voice_id}
	spoken.append(entry)
	_until[slot] = run.tick + duration_ticks
	var kept: Dictionary = {}
	# RSC-04's coming-round 'Help!' goes at talk band and range, whatever the window's whisper route.
	var help_override: int = VoiceRoutes.Route.NORMAL if forced and line == "help" else -1
	for route: Dictionary in run.voice.compute(slot, band, {}, {}, help_override):
		var listener: int = int(Variants.number(route["listener"]))
		var loss: float = float(Variants.number(route["loss"]))
		var r: CalloutRecord = CalloutRecord.new()
		r.voice = VoiceManifest.wire_voice(voice_id)
		r.line = VoiceManifest.wire_line(line)
		r.band = band
		r.apparent = Vector2(float(Variants.number(route["x"])), float(Variants.number(route["y"])))
		r.gain_db = roundi(float(Variants.number(route["gain_db"])))
		r.muffle = float(Variants.number(route["muffle"]))
		var vflags: int = int(Variants.number(route["flags"]))
		r.flags = (CalloutRecord.FLAG_MUFFLED if (vflags & VoicePackets.MUFFLED) != 0 else 0) \
			| (CalloutRecord.FLAG_TELEPHONE if (vflags & VoicePackets.TELEPHONE) != 0 else 0) \
			| (CalloutRecord.FLAG_DRY if (vflags & VoicePackets.DRY) != 0 else 0) \
			| (CalloutRecord.FLAG_CRACKLE if Variants.flag(route["crackle"]) else 0)
		r.mask = mask(run, utterance, listener, frames, loss)
		kept[listener] = r.kept_share()
		send(listener, r)
	# The speaker hears their own bark, whole and dry.
	var own: CalloutRecord = CalloutRecord.new()
	own.voice = VoiceManifest.wire_voice(voice_id)
	own.line = VoiceManifest.wire_line(line)
	own.band = band
	own.flags = CalloutRecord.FLAG_DRY
	own.mask = mask(run, utterance, slot, frames, 0.0)
	send(slot, own)
	if run.heard != null and run.heard.callout_counts(slot, kept, band):
		run.heard.mark_heard(slot, &"callout")
	var route_kind: int = help_override if help_override >= 0 else int(Variants.number(run.voice.route_of.get(slot, VoiceRoutes.Route.NORMAL)))
	var np: float = VoiceNoise.level_np(route_kind as VoiceRoutes.Route, band)
	if np > 0.0:
		_sounding.append([slot, entity, np, run.tick, run.tick + duration_ticks])
	return id


## SND-08's mask for one listener of a recorded line: the same seeded process live voice gets.
func mask(run: RunState, utterance: int, listener: int, frames: int, loss: float) -> PackedByteArray:
	return LbVoiceLoss.mask_for(run.header.run_seed, utterance, listener, frames, loss,
		roundi(Tuning.f(&"voice.loss_run_min_frames")), roundi(Tuning.f(&"voice.loss_run_max_frames")))


## MOD-08: the share of a callout a listener at `tile` would keep (0 out of reach), by the same
## routing and seeded mask; `listener` keys the mask as a real listener's slot would.
func kept_fraction_at(callout_id: int, tile: Vector2i, listener: int) -> float:
	var entry: Dictionary = {}
	for e: Dictionary in spoken:
		if int(Variants.number(e["id"])) == callout_id:
			entry = e
	if entry.is_empty() or _run == null or _run.road_graph == null:
		return 0.0
	var slot: int = entry["slot"]
	var route: VoiceRoutes.Route = int(Variants.number(_run.voice.route_of.get(slot, VoiceRoutes.Route.NORMAL))) as VoiceRoutes.Route
	var rb: Array = VoiceRoutes.route_band(route, int(Variants.number(entry["band"])))
	var from_tile: Vector2i = entry["tile"]
	var from_pos: Vector2 = entry["position"]
	var r: Dictionary = VoiceRoutes.reach(_run.road_graph.graph, from_tile, from_pos, tile, int(Variants.number(rb[0])), 0)
	if r.is_empty():
		return 0.0
	var d: float = float(Variants.number(r["distance"]))
	var rng: float = float(Variants.number(r["range"]))
	var clean: float = Tuning.f(&"voice.clean_range_fraction")
	var conditions: VoiceConditions = _run.voice.conditions
	if conditions.fan_surge_active and d > rng * clean:
		return 0.0
	var crackle: bool = conditions.near_stythe(from_pos) or conditions.near_stythe(Vector2(tile) + Vector2(0.5, 0.5))
	var loss: float = LbVoiceLoss.combine(PackedFloat64Array([LbVoiceLoss.distance_loss(d, rng, clean, Tuning.f(&"voice.edge_loss")),
		Tuning.f(&"voice.stythe_loss") if crackle else 0.0, Tuning.f(&"voice.running_loss") if conditions.running(slot) else 0.0]))
	var record: CalloutRecord = CalloutRecord.new()
	record.mask = mask(_run, int(Variants.number(entry["utterance"])), listener, int(Variants.number(entry["frames"])), loss)
	return record.kept_share()


## CRT-10's illusions and CRT-12's echoes use the same path (and the same record) to one client.
func send(slot: int, record: CalloutRecord) -> void:
	var bytes: PackedByteArray = record.encode()
	sent.append([slot, bytes])
	if _net == null:
		return
	for session: Sessions.Session in _net.sessions.welcomed():
		if session.slot == slot:
			_net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.CALLOUT, bytes))


func _refusal(run: RunState, slot: int, line: String, band: int, holding_breath: bool, forced: bool) -> String:
	var m: MovementSystem.Miner = run.movement.miner(slot)
	if m == null or run.voice == null:
		return "no miner"
	if band < CalloutLines.WHISPER or band > CalloutLines.SHOUT:
		return "band"
	var life: int = run.miner_state.life(m.entity_id) if run.miner_state != null else MinerTransitions.Life.UPRIGHT
	if life == MinerTransitions.Life.DEAD or (life == MinerTransitions.Life.UNCONSCIOUS and not (forced and CalloutLines.COMING_ROUND.has(line))):
		return "state"
	if int(Variants.number(run.voice.route_of.get(slot, VoiceRoutes.Route.NORMAL))) == VoiceRoutes.Route.ASIDE:
		return "aside"
	if holding_breath:
		return "breath"
	var page: bool = job_page(run, m.entity_id)
	if line == "moan" and not forced:
		return "page"
	if not forced and ((page and not CalloutLines.JOB_PAGE.has(line)) or (not page and not CalloutLines.WHEEL.has(line))):
		return "page"
	if int(Variants.number(_until.get(slot, -1))) > run.tick:
		return "playing"
	return ""


## Each sounding bark's Road Graph event: at onset, then every noise.voice_event_interval_s, as voice.
func _sound_on(run: RunState) -> void:
	var every: int = maxi(1, roundi(Tuning.f(&"noise.voice_event_interval_s") * Tuning.f(&"net.tick_hz")))
	var keep: Array[Array] = []
	for s: Array in _sounding:
		var entity: int = s[1]
		var next: int = s[3]
		var end: int = s[4]
		if run.tick >= end or not run.registry.has(entity):
			continue
		if run.tick >= next and run.noise != null:
			run.noise.emit(NoiseTypes.Type.CALLOUT, run.registry.get_entity(entity).tile(), {"level_np": s[2], "source": entity,
				"mode": RoadGraphService.MODE_VOICE_EVENT, "players": false})
			s[3] = next + every
		keep.append(s)
	_sounding = keep


## The slot's character voice: the one its scream uses (SND-15's FallAudio, from SND-13's assignment).
func _voice_of(run: RunState, slot: int) -> String:
	var ids: PackedStringArray = VoiceManifest.voice_ids()
	if ids.is_empty():
		return ""
	var index: int = run.fall_audio.voice_for(slot) if run.fall_audio != null else VoiceAssignment.default_for(str(slot))
	return ids[posmod(index, ids.size())]


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(_next_id)
	var slots: Array = _until.keys()
	slots.sort()
	writer.put_i64(slots.size())
	for raw: Variant in slots:
		var slot: int = raw
		writer.put_i64(slot)
		writer.put_i64(int(Variants.number(_until[raw])))
	writer.put_i64(_sounding.size())
	for s: Array in _sounding:
		for i: int in 5:
			writer.put_f64(float(Variants.number(s[i])))
