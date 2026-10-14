class_name VoiceSystem
extends SimSystem
## SND-07: in-game proximity voice, through the server (GDD §15.5 step 4). A speaker's frames are
## forwarded the moment they arrive (ServerNet services the network between ticks), never decoded,
## mixed or kept: LbVoiceForwarder rewrites each for the listeners its routes name and hands the
## packets straight to the transport. Routes (VoiceRoutes) are worked out when an utterance starts,
## when its band changes and every voice.route_refresh_s while it lasts. Each utterance gets fresh
## stream ids, one per listener, so nothing identifies a speaker. Not simulation state: outside the
## state hash, and nothing about voice is recorded.
## SND-08: each listener's frames are dropped on the way, in runs of 3-10 (the forwarder's loss
## processes): distance beyond half range (to voice.edge_loss at the edge, and muffled with it), a
## Stythe whose tell plays within voice.stythe_radius_tiles of speaker or listener
## (voice.stythe_loss, with crackle), the speaker running or panting (voice.running_loss); combined
## independently. The Fan's surge cuts listeners beyond half range; a deafened listener gets nothing.
## The fall's scream, phone lines and channels lose nothing. Only listeners lose frames: `band_heard`
## fires for every frame before any loss (SND-09's band events, which the rock hears whole).

## SND-09: every valid frame's band, before routing or loss: (speaker slot, band).
signal band_heard(slot: int, band: int)

var forwarder: LbVoiceForwarder = LbVoiceForwarder.new()
## slot -> VoiceRoutes.Route; NORMAL unless an owning ticket sets one.
var route_of: Dictionary = {}
## slot -> {other slot: true}: LFT-12's phone lines (both ways once opened).
var direct: Dictionary = {}
## channel name -> {slot: true}: RSC-04's dream channel, RSC-06's Lamp Check.
var channels: Dictionary = {}
var forwarded: int = 0
var refused: int = 0
## SND-08: frames not sent because a listener's loss dropped them (QA-04's telemetry counter).
var dropped: int = 0
var conditions: VoiceConditions = VoiceConditions.new()
## Dev and QA builds: one line per utterance and listener (band, route, path, each rate, frames).
var loss_logs: bool = false
var _utterances: int = 0
## slot -> {band, ended, streams {listener: id}, refreshed_tick}
var _speaking: Dictionary = {}
var _next_stream: int = 0
var _run: RunState = null
var _net: ServerNet = null


func stage() -> int:
	return StageTable.Stage.ROAD_GRAPH


func order() -> int:
	return 30


func system_name() -> String:
	return "voice"


func hashed() -> bool:
	return false


func bind(run: RunState, net: ServerNet) -> void:
	_run = run
	_net = net
	net.voice = on_voice
	conditions.bind(run)
	forwarder.set_loss(run.header.run_seed if run.header != null else 0, roundi(Tuning.f(&"voice.loss_run_min_frames")),
		roundi(Tuning.f(&"voice.loss_run_max_frames")))
	loss_logs = net.flavour != BuildInfo.Flavour.RELEASE


func set_route(slot: int, route: VoiceRoutes.Route) -> void:
	route_of[slot] = route
	_refresh_if_speaking(slot)


## LFT-12: a phone line between two slots: every frame both ways, telephone band, no distance loss.
func open_direct(a: int, b: int) -> void:
	for pair: Array in [[a, b], [b, a]]:
		var lines: Dictionary = Variants.dict(direct.get(pair[0], {}))
		lines[pair[1]] = true
		direct[pair[0]] = lines
		_refresh_if_speaking(int(Variants.number(pair[0])))


func close_direct(a: int, b: int) -> void:
	for pair: Array in [[a, b], [b, a]]:
		Variants.dict(direct.get(pair[0], {})).erase(pair[1])
		_refresh_if_speaking(int(Variants.number(pair[0])))


## RSC-04, RSC-06: a shared channel: dry, unspatialised, to every member; it replaces proximity.
func channel_join(channel: String, slot: int) -> void:
	var members: Dictionary = Variants.dict(channels.get(channel, {}))
	members[slot] = true
	channels[channel] = members
	for raw: Variant in members.keys():
		_refresh_if_speaking(int(Variants.number(raw)))


func channel_leave(channel: String, slot: int) -> void:
	Variants.dict(channels.get(channel, {})).erase(slot)
	_refresh_if_speaking(slot)


## A voice packet from `slot`'s client, as it arrives. False (counted as bad) when malformed.
func on_voice(slot: int, payload: PackedByteArray) -> bool:
	var head: Dictionary = LbVoiceForwarder.parse(payload)
	if not Variants.flag(head["valid"]):
		refused += 1
		return false
	var band: int = int(Variants.number(head["band"]))
	var ending: bool = Variants.flag(head["end"])
	if not ending:
		band_heard.emit(slot, band)
	var st: Dictionary = Variants.dict(_speaking.get(slot, {}))
	if st.is_empty() or Variants.flag(st["ended"]):
		if ending:
			return true  # an END with no utterance: nothing to close
		_utterances += 1
		st = {"band": band, "ended": false, "streams": {}, "refreshed_tick": -1, "utterance": _utterances, "rates": {}}
		_speaking[slot] = st
		_refresh(slot, st)
	elif not ending and band != int(Variants.number(st["band"])):
		st["band"] = band
		_refresh(slot, st)
	elif not ending and _conditions_signature(slot) != str(st.get("conditions", "")):
		_refresh(slot, st)  # deafness, the Fan, a Stythe since the last tick: this frame already obeys it
	var out: Array = forwarder.forward(slot, payload)
	dropped += forwarder.route_count(slot) - out.size()
	for raw: Variant in out:
		var item: Array = raw
		var peer: int = _peer_of(int(Variants.number(item[0])))
		var bytes: PackedByteArray = item[1]
		if peer >= 0:
			_net.transport.send(peer, Lane.Id.VOICE, Protocol.frame(Protocol.Msg.VOICE, bytes))
			forwarded += 1
	if ending:
		st["ended"] = true
		_log_utterance(slot, st)
		forwarder.clear(slot)
	return true


## SND-08's QA log (dev and QA builds; QA-01 checks it against §6.2): per listener, the band, the
## route, the path, each rate and the frames sent and forwarded. No audio, and nothing to clients.
func _log_utterance(slot: int, st: Dictionary) -> void:
	if not loss_logs:
		return
	var counts: Dictionary = forwarder.counts(slot)
	var rates: Dictionary = Variants.dict(st.get("rates", {}))
	for raw: Variant in counts.keys():
		var c: Dictionary = counts[raw]
		var r: Dictionary = Variants.dict(rates.get(raw, {}))
		Log.info(("voice loss: utterance %d speaker %d band %d route %s listener %d via %s path %.1f/%.1f "
			+ "distance %.2f stythe %.2f running %.2f p %.2f frames %d sent %d") % [
			int(Variants.number(st["utterance"])), slot, int(Variants.number(st["band"])), VoiceRoutes.Route.keys()[int(Variants.number(route_of.get(slot, 0)))],
			int(Variants.number(raw)), r.get("via", "-"), float(Variants.number(r.get("distance", 0.0))), float(Variants.number(r.get("range", 0.0))),
			float(Variants.number(r.get("distance_loss", 0.0))), float(Variants.number(r.get("stythe_loss", 0.0))),
			float(Variants.number(r.get("running_loss", 0.0))), float(Variants.number(r.get("loss", 0.0))),
			int(Variants.number(c["seen"])), int(Variants.number(c["sent"]))])


## While an utterance lasts: a change of conditions (deafness, the Fan, a Stythe, a route, a line or
## channel) re-routes on the tick; movement every voice.route_refresh_s, once a tile has changed.
func tick(run: RunState) -> void:
	var every: int = maxi(1, roundi(Tuning.f(&"voice.route_refresh_s") * Tuning.f(&"net.tick_hz")))
	for raw: Variant in _speaking.keys():
		var slot: int = int(Variants.number(raw))
		var st: Dictionary = _speaking[raw]
		if Variants.flag(st["ended"]):
			continue
		if _conditions_signature(slot) != str(st.get("conditions", "")):
			_refresh(slot, st)
		elif run.tick - int(Variants.number(st["refreshed_tick"])) >= every:
			if _signature(slot, st) != str(st.get("signature", "")):
				_refresh(slot, st)
			else:
				st["refreshed_tick"] = run.tick


func _refresh_if_speaking(slot: int) -> void:
	var st: Dictionary = Variants.dict(_speaking.get(slot, {}))
	if not st.is_empty() and not Variants.flag(st["ended"]):
		_refresh(slot, st)


func _refresh(slot: int, st: Dictionary) -> void:
	st["refreshed_tick"] = _run.tick if _run != null else 0
	st["signature"] = _signature(slot, st)
	st["conditions"] = _conditions_signature(slot)
	var rates: Dictionary = {}
	forwarder.set_routes(slot, compute(slot, int(Variants.number(st["band"])), Variants.dict(st["streams"]), rates),
		int(Variants.number(st.get("utterance", 0))))
	st["rates"] = rates


## What changes routes at once: the route, lines, channels, running, the Fan, Stythes, deafness.
func _conditions_signature(slot: int) -> String:
	var parts: PackedStringArray = PackedStringArray([str(route_of.get(slot, 0)), str(direct.get(slot, {})), str(channels),
		str(conditions.running(slot)), str(conditions.fan_surge_active), str(conditions.stythe_tells.call())])
	for session: Sessions.Session in _net.sessions.welcomed():
		parts.append("%d:%s" % [session.slot, conditions.deafened(session.slot)])
	return "|".join(parts)


## What the routes depend on: the band, the route, every miner's tile, the lines and channels.
func _signature(slot: int, st: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray([str(st["band"]), str(route_of.get(slot, 0)), str(direct.get(slot, {})),
		str(channels), str(_run.road_graph.graph.epoch() if _run != null and _run.road_graph != null else 0),
		str(conditions.running(slot)), str(conditions.fan_surge_active), str(conditions.stythe_tells.call())])
	for session: Sessions.Session in _net.sessions.welcomed():
		var m: Dictionary = _miner(session.slot)
		parts.append("%d:%s:%s" % [session.slot, m.get("tile", Vector2i(-1, -1)), conditions.deafened(session.slot)])
	return "|".join(parts)


## The routes for `slot` speaking at `band` now: [{listener, stream, gain_db, flags, crackle, muffle,
## loss, x, y}]. `rates` (optional) receives each listener's rates for the QA log.
func compute(slot: int, band: int, streams: Dictionary, rates: Dictionary = {}) -> Array:
	var out: Array = []
	for name: Variant in channels.keys():
		var members: Dictionary = channels[name]
		if members.has(slot):
			for raw: Variant in members.keys():
				var other: int = int(Variants.number(raw))
				if other != slot:
					out.append(_route(streams, other, 0.0, VoicePackets.DRY, Vector2.ZERO))
			return out  # a channel replaces proximity
	var speaker: Dictionary = _miner(slot)
	if not speaker.is_empty():
		var kind: int = int(Variants.number(route_of.get(slot, VoiceRoutes.Route.NORMAL)))
		var rb: Array = VoiceRoutes.route_band(kind as VoiceRoutes.Route, band)
		if Variants.flag(rb[2]) and _run.road_graph != null:
			var from_tile: Vector2i = speaker["tile"]
			var from_pos: Vector2 = speaker["position"]
			var lossless: bool = kind == VoiceRoutes.Route.FALL_SCREAM
			var speaker_stythe: bool = conditions.near_stythe(from_pos)
			var running: float = Tuning.f(&"voice.running_loss") if conditions.running(slot) else 0.0
			var clean: float = Tuning.f(&"voice.clean_range_fraction")
			for other: int in _listeners(slot):
				if conditions.deafened(other):
					continue  # deafened: nothing for the ringing's length (SND-04)
				var to: Dictionary = _miner(other)
				var to_tile: Vector2i = to["tile"]
				var r: Dictionary = VoiceRoutes.reach(_run.road_graph.graph, from_tile, from_pos, to_tile,
					int(Variants.number(rb[0])), _stream_of(streams, other))
				if r.is_empty():
					continue
				var d: float = float(Variants.number(r["distance"]))
				var rng: float = float(Variants.number(r["range"]))
				if conditions.fan_surge_active and d > rng * clean:
					continue  # the Fan's surge: nothing beyond half range
				var to_pos: Vector2 = to["position"]
				var crackle: bool = speaker_stythe or conditions.near_stythe(to_pos)
				var muffled: bool = Variants.flag(r["muffled"]) or Variants.flag(rb[1])
				var lr: Dictionary = {"via": r["via"], "distance": d, "range": rng, "distance_loss": 0.0, "stythe_loss": 0.0,
					"running_loss": 0.0, "loss": 0.0}
				if not lossless:
					var dl: float = LbVoiceLoss.distance_loss(d, rng, clean, Tuning.f(&"voice.edge_loss"))
					var sl: float = Tuning.f(&"voice.stythe_loss") if crackle else 0.0
					lr["distance_loss"] = dl
					lr["stythe_loss"] = sl
					lr["running_loss"] = running
					lr["loss"] = LbVoiceLoss.combine(PackedFloat64Array([dl, sl, running]))
				rates[other] = lr
				var at: Vector2 = r["position"]
				var route: Dictionary = _route(streams, other, float(Variants.number(r["gain_db"])),
					VoicePackets.MUFFLED if muffled else 0, at)
				route["crackle"] = crackle
				route["muffle"] = 1.0 if muffled else LbVoiceLoss.distance_muffle(d, rng, clean)
				route["loss"] = lr["loss"]
				out.append(route)
	for raw: Variant in Variants.dict(direct.get(slot, {})).keys():
		var other: int = int(Variants.number(raw))
		var existing: int = -1
		for i: int in out.size():
			if int(Variants.number(Variants.dict(out[i])["listener"])) == other:
				existing = i
		var line: Dictionary = _route(streams, other, 0.0, VoicePackets.TELEPHONE, Vector2.ZERO)
		if existing >= 0:
			out[existing] = line
		else:
			out.append(line)
	return out


func _route(streams: Dictionary, listener: int, gain_db: float, flags: int, at: Vector2) -> Dictionary:
	return {"listener": listener, "stream": _stream_of(streams, listener), "gain_db": gain_db, "flags": flags,
		"crackle": false, "muffle": 0.0, "loss": 0.0, "x": at.x, "y": at.y}


## The listener's stream id for this utterance: new ones count on, so none names a speaker.
func _stream_of(streams: Dictionary, listener: int) -> int:
	if not streams.has(listener):
		_next_stream = (_next_stream % 0xFFFF) + 1
		streams[listener] = _next_stream
	return int(Variants.number(streams[listener]))


## The living miners in play other than `slot` (the dead have only the dream channel).
func _listeners(slot: int) -> Array[int]:
	var out: Array[int] = []
	for session: Sessions.Session in _net.sessions.welcomed():
		if session.slot == slot or _miner(session.slot).is_empty():
			continue
		var entity: int = int(Variants.number(_miner(session.slot)["entity"]))
		if _run.miner_state != null and _run.miner_state.life(entity) == MinerTransitions.Life.DEAD:
			continue
		out.append(session.slot)
	return out


func _miner(slot: int) -> Dictionary:
	if _run == null or _run.movement == null:
		return {}
	var m: MovementSystem.Miner = _run.movement.miner(slot)
	if m == null or not _run.registry.has(m.entity_id):
		return {}
	var entity: int = m.entity_id
	var e: SimEntity = _run.registry.get_entity(entity)
	return {"entity": entity, "position": e.position, "tile": e.tile()}


func _peer_of(slot: int) -> int:
	for session: Sessions.Session in _net.sessions.welcomed():
		if session.slot == slot:
			return session.peer
	return -1
