class_name VoiceNoise
extends RefCounted
## SND-09: voice is noise (Gameplay §6.2, §6.3, A.3). Every frame the server receives becomes a
## Road Graph event at the speaker's tile, at its band's np, at band onset and then every
## noise.voice_event_interval_s, before any listener's loss (SND-08) and never dropped, so the
## rock hears every word a teammate misses (§7.3). Events go by route: NORMAL and DRAGGED at the
## band's np (a dragged voice is muffled only for listeners); ASIDE and COMING_ROUND at whisper
## np while the band is above silent; FALL_SCREAM (SND-15 emits its one scream) and CUT none. They
## travel in SND-01's voice mode (no shut door or gate passes them), as voice, not a struck sound,
## and reach creatures and the collapse hook only: no client is sent a record of anyone's band.
## The dead (a channel replaces proximity) make none. Voice arrives between ticks, so each event
## is a voice fact (VoiceFacts): applied on the next tick, at the miner's tile then, and logged.

const NP_KEYS: Array[StringName] = [&"", &"voice.whisper_np", &"voice.talk_np", &"voice.shout_np", &"voice.scream_np"]

## Events emitted (QA-04's telemetry).
var emitted: int = 0
## slot -> [band, tick] of its last event in the current utterance.
var _last: Dictionary = {}
var _run: RunState = null


func bind(run: RunState) -> void:
	_run = run
	run.voice.band_heard.connect(_on_band)
	run.voice.utterance_closed.connect(_on_closed)


## The np of a band's event on a route; 0 when the route makes none.
static func level_np(route: VoiceRoutes.Route, band: int) -> float:
	if band <= 0 or band > VoicePackets.MAX_BAND:
		return 0.0
	match route:
		VoiceRoutes.Route.FALL_SCREAM, VoiceRoutes.Route.FALL_MUFFLED, VoiceRoutes.Route.CUT:
			return 0.0
		VoiceRoutes.Route.ASIDE, VoiceRoutes.Route.COMING_ROUND:
			return Tuning.f(NP_KEYS[1])
	return Tuning.f(NP_KEYS[band])


func _on_band(slot: int, band: int) -> void:
	var route: VoiceRoutes.Route = int(Variants.number(_run.voice.route_of.get(slot, VoiceRoutes.Route.NORMAL))) as VoiceRoutes.Route
	var np: float = level_np(route, band)
	# RSC-04: the dream channel makes no noise, but a coming-round window's whisper does.
	if np <= 0.0 or (_in_channel(slot) and route != VoiceRoutes.Route.COMING_ROUND) or _run.movement == null or _run.noise == null:
		return
	var m: MovementSystem.Miner = _run.movement.miner(slot)
	if m == null or not _run.registry.has(m.entity_id):
		return
	if _run.miner_state != null and _run.miner_state.life(m.entity_id) == MinerTransitions.Life.DEAD:
		return
	var every: int = maxi(1, roundi(Tuning.f(&"noise.voice_event_interval_s") * Tuning.f(&"net.tick_hz")))
	var last: Array = Variants.array(_last.get(slot, []))
	if not last.is_empty() and int(Variants.number(last[0])) == band and _run.tick - int(Variants.number(last[1])) < every:
		return
	_run.voice_facts.add(VoiceFacts.BAND, slot, np)
	_last[slot] = [band, _run.tick]
	emitted += 1


## VoiceFacts: the event itself, at the speaker's tile this tick.
func emit_band(slot: int, np: float) -> void:
	var m: MovementSystem.Miner = _run.movement.miner(slot) if _run.movement != null else null
	if m == null or not _run.registry.has(m.entity_id):
		return
	_run.noise.emit(NoiseTypes.Type.VOICE, _run.registry.get_entity(m.entity_id).tile(), {"level_np": np, "source": m.entity_id,
		"mode": RoadGraphService.MODE_VOICE, "players": false})


func _on_closed(slot: int, _frames: int, _delivered: Dictionary, _band: int, ended: bool) -> void:
	if ended:
		_last.erase(slot)  # the next frame is a new onset


func _in_channel(slot: int) -> bool:
	for raw: Variant in _run.voice.channels.values():
		if Variants.dict(raw).has(slot):
			return true
	return false
