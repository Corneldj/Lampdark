class_name ServerNet
extends SimSystem
## Stage 1 of the tick (NET-02): drain the transport, run the handshake, answer clock-sync
## pings, route lane traffic to its owners, and drop peers that never finish the handshake.
## Nothing but Welcome or Reject goes to a peer before it is welcomed.

var transport: Transport
var sessions: Sessions
var handshake_timeout_usec: int = 5000000
## Overridable for tests; defaults to this build's identity.
var build_id: String = Protocol.build_id()
## Per-peer count of malformed or unknown messages (NET-13 reads it).
var bad_messages: Dictionary = {}
## lane -> Array of [slot, message type, payload]: game traffic for NET-03 (inputs). Each owner takes
## and clears its lane every tick.
var routed: Dictionary = {}
## SND-07: VoiceSystem.on_voice(slot, payload) -> bool; voice packets go to it as they arrive.
var voice: Callable = Callable()
## FND-08: this server's build flavour (a release client never joins a dev or QA server, nor the
## reverse) and its QA token: a dev or QA server opens the debug lane to a client presenting it,
## and a dev server also to a local client without one. A release server opens it to nobody.
var flavour: int = BuildInfo.detect(FeatureProvider.new()).flavour
var qa_token: String = ""
## STM-04: the host link's token; a relay tag carrying it (from a loopback peer) names a friend's
## SteamID for Path B. Empty: no relay tags accepted.
var relay_token: String = ""

## A client was welcomed into `slot` as `identity` (QA-01's M1 arrival gives it a miner).
signal welcomed(slot: int, identity: String)
## NET-11: a dropped player retook its reserved seat (MOD-08 hands the miner back).
signal rejoined(slot: int, identity: String)

## NET-11: who holds which place, dropped players' seats included.
var seats: SeatTable = SeatTable.new()
## Debug-lane messages refused from sessions without the grant (FND-08's isolation checks).
var debug_refused: int = 0
## Slots dropped during this tick's pump (cleared at the next).
var dropped_slots: PackedInt64Array = PackedInt64Array()
var _closing: Dictionary = {}
## Events taken between ticks by service(), handled at the next tick.
var _buffered: Array[TransportEvent] = []


func _init(net_transport: Transport, slots: int = 5) -> void:
	transport = net_transport
	sessions = Sessions.new(slots)
	if Tuning.current.has_key(&"net.handshake_timeout_s"):
		handshake_timeout_usec = roundi(Tuning.f(&"net.handshake_timeout_s") * 1000000.0)


func stage() -> int:
	return StageTable.Stage.RECEIVE


func order() -> int:
	return 0


func tick(run: RunState) -> void:
	pump(run)


## Between ticks (the driver calls this about every millisecond): answer clock-sync pings
## at once, so RTT measures the link and not the tick, and buffer everything else for the
## next tick, so game state still changes only on tick boundaries.
func service() -> void:
	var now: int = Transport.now_usec()
	for event: TransportEvent in transport.poll():
		if event.kind == TransportEvent.Kind.MESSAGE and (_answer_ping(event, now) or _take_voice(event)):
			continue
		_buffered.append(event)
	transport.flush()


## SND-07: a voice packet from a welcomed client goes to VoiceSystem the moment it arrives (never
## waiting for the tick); a malformed one counts against the peer.
func _take_voice(event: TransportEvent) -> bool:
	if not voice.is_valid() or event.lane != Lane.Id.VOICE:
		return false
	var session: Sessions.Session = sessions.for_peer(event.peer)
	if session == null or not session.welcomed or _closing.has(event.peer):
		return false
	var message: Dictionary = Protocol.unframe(event.data)
	if message.is_empty() or int(Variants.number(message["type"])) != Protocol.Msg.VOICE:
		return false
	if not Variants.flag(voice.call(session.slot, message["payload"])):
		_count_bad(event.peer)
	return true


func _answer_ping(event: TransportEvent, now: int) -> bool:
	var session: Sessions.Session = sessions.for_peer(event.peer)
	if session == null or not session.welcomed or event.lane != Lane.Id.CONTROL:
		return false
	var message: Dictionary = Protocol.unframe(event.data)
	if message.is_empty() or int(Variants.number(message["type"])) != Protocol.Msg.PING:
		return false
	var payload: PackedByteArray = message["payload"]
	transport.send(event.peer, Lane.Id.CONTROL, Protocol.pong(Protocol.read_i64(payload), now))
	return true


func pump(run: RunState) -> void:
	var now: int = Transport.now_usec()
	# Last tick's drops and routed traffic were for last tick's systems; anything a lane's owner
	# did not take (a lane whose system does not exist yet) is dropped here, never kept.
	dropped_slots.clear()
	routed.clear()
	for peer: Variant in _closing.keys():
		var id: int = int(Variants.number(peer))
		var left: int = int(Variants.number(_closing[peer])) - 1
		if left <= 0:
			_closing.erase(peer)
			transport.disconnect_peer(id)
		else:
			_closing[peer] = left
	var events: Array[TransportEvent] = _buffered
	_buffered = []
	events.append_array(transport.poll())
	for event: TransportEvent in events:
		match event.kind:
			TransportEvent.Kind.CONNECTED:
				sessions.on_connected(event.peer, now)
			TransportEvent.Kind.DROPPED:
				var session: Sessions.Session = sessions.on_dropped(event.peer)
				_closing.erase(event.peer)
				if session != null and session.welcomed:
					dropped_slots.append(session.slot)
					Log.info("slot %d dropped (%s)" % [session.slot, event.reason])
			TransportEvent.Kind.MESSAGE:
				_on_message(run, event, now)
	for session: Sessions.Session in sessions.pending():
		if now - session.connected_usec > handshake_timeout_usec and not _closing.has(session.peer):
			Log.info("peer %d: handshake timed out" % session.peer)
			transport.disconnect_peer(session.peer)
			sessions.on_dropped(session.peer)


func _on_message(run: RunState, event: TransportEvent, now: int) -> void:
	var session: Sessions.Session = sessions.for_peer(event.peer)
	if session == null or _closing.has(event.peer):
		return
	var message: Dictionary = Protocol.unframe(event.data)
	if message.is_empty():
		_count_bad(event.peer)
		return
	var type: int = int(Variants.number(message["type"]))
	var payload: PackedByteArray = message["payload"]
	if not session.welcomed:
		if type == Protocol.Msg.HELLO and event.lane == Lane.Id.CONTROL:
			_on_hello(run, session, Protocol.Hello.decode(payload), now)
		elif type == Protocol.Msg.RELAY_TAG and event.lane == Lane.Id.CONTROL and session.relayed_identity.is_empty():
			var tag: Array = Protocol.read_relay_tag(payload)
			if relay_token.is_empty() or tag.is_empty() or str(tag[0]) != relay_token or not transport.is_local_peer(session.peer):
				Log.info("peer %d refused: a relay tag without the host's token" % session.peer)
				_reject(session, Protocol.Reject.AUTH_FAILED)
			else:
				session.relayed_identity = str(tag[1])
		else:
			_reject(session, Protocol.Reject.BAD_MESSAGE)
		return
	if event.lane == Lane.Id.DEBUG:
		if session.debug and flavour != BuildInfo.Flavour.RELEASE:
			_route(event.lane, session.slot, type, payload)
		else:
			debug_refused += 1
			_count_bad(event.peer)
		return
	match type:
		Protocol.Msg.PING:
			transport.send(event.peer, Lane.Id.CONTROL, Protocol.pong(Protocol.read_i64(payload), now))
		Protocol.Msg.VOICE when voice.is_valid() and event.lane == Lane.Id.VOICE:
			if not Variants.flag(voice.call(session.slot, payload)):
				_count_bad(event.peer)
		Protocol.Msg.MIC_LABEL:
			if event.lane != Lane.Id.CONTROL or payload.size() != 1 or payload[0] > 1:
				_count_bad(event.peer)
			else:
				session.mute_label = payload[0] == 1
		Protocol.Msg.HELLO, Protocol.Msg.WELCOME, Protocol.Msg.REJECT, Protocol.Msg.PONG, Protocol.Msg.FRAME:
			_count_bad(event.peer)
		_:
			if Protocol.Msg.values().has(type):
				_route(event.lane, session.slot, type, payload)
			else:
				_count_bad(event.peer)


func _on_hello(run: RunState, session: Sessions.Session, hello: Protocol.Hello, now: int) -> void:
	if hello.protocol_version != Protocol.PROTOCOL_VERSION or hello.build_id != build_id:
		Log.info("peer %d refused: version mismatch (protocol %d, build %s)" % [session.peer, hello.protocol_version, hello.build_id])
		_reject(session, Protocol.Reject.VERSION_MISMATCH)
		return
	if (hello.flavour == BuildInfo.Flavour.RELEASE) != (flavour == BuildInfo.Flavour.RELEASE):
		Log.info("peer %d refused: a %s client on a %s server" % [session.peer, _flavour_name(hello.flavour), _flavour_name(flavour)])
		_reject(session, Protocol.Reject.FLAVOUR_MISMATCH)
		return
	var verified: String = transport.verified_identity(session.peer)
	if verified.is_empty():
		verified = session.relayed_identity
	if not verified.is_empty() and verified != hello.identity:
		# STM-03: over SDR the connection's SteamID is Steam's word; a Hello claiming another is refused.
		Log.info("peer %d refused: identity %s on a connection from %s" % [session.peer, hello.identity, verified])
		_reject(session, Protocol.Reject.AUTH_FAILED)
		return
	# NET-11: a dropped player retakes its own seat; a removed one, or one whose place a Hand now
	# keeps, is refused; a newcomer never gets a seat held for someone.
	var verdict: Dictionary = seats.on_hello(hello.identity, hello.session_token, run.tick if run != null else 0,
		run != null and run.header.mode == ServerConfig.Mode.PUBLIC)
	if verdict.has("reject"):
		Log.info("peer %d refused: %s" % [session.peer, Protocol.reject_name(int(Variants.number(verdict["reject"])))])
		_reject(session, int(Variants.number(verdict["reject"])) as Protocol.Reject)
		return
	var forced: int = int(Variants.number(verdict.get("slot", -1)))
	if not sessions.seat(session, hello.identity, hello.seat_request, seats.held_slots(), forced):
		_reject(session, Protocol.Reject.FULL)
		return
	seats.on_seated(hello.identity, session.slot, session.token, run.tick if run != null else 0)
	session.debug = debug_granted(hello.qa_token, transport.is_local_peer(session.peer))
	var welcome: Protocol.Welcome = Protocol.Welcome.new()
	welcome.slot = session.slot
	welcome.session_token = session.token
	welcome.tick_hz = roundi(Tuning.f(&"net.tick_hz")) if Tuning.current.has_key(&"net.tick_hz") else 20
	welcome.server_tick = run.tick
	welcome.server_time_us = now
	welcome.client_tuning_hash = Tuning.content_hash("client") if Tuning.current.entries.size() > 0 else ""
	welcome.client_tuning = _client_tuning_if_changed(welcome.client_tuning_hash)
	welcome.debug = session.debug
	transport.send(session.peer, Lane.Id.CONTROL, welcome.encode())
	Log.info("slot %d welcomed: %s" % [session.slot, hello.identity])
	welcomed.emit(session.slot, hello.identity)
	if forced >= 0:
		rejoined.emit(session.slot, hello.identity)


## FND-08: never on a release server; on QA, only with this server's token; on dev, with the token
## or from a local peer (an editor run).
func debug_granted(token: String, local_peer: bool) -> bool:
	match flavour:
		BuildInfo.Flavour.RELEASE:
			return false
		BuildInfo.Flavour.QA:
			return not qa_token.is_empty() and token == qa_token
	return (not qa_token.is_empty() and token == qa_token) or local_peer


static func _flavour_name(f: int) -> String:
	return "release" if f == BuildInfo.Flavour.RELEASE else ("qa" if f == BuildInfo.Flavour.QA else "dev")


## The effective client table, only when it differs from the table clients ship with
## (a data bundle or a dev reload changed it). It never holds a server-only key.
func _client_tuning_if_changed(effective_hash: String) -> String:
	var shipped: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(TuningSet.CLIENT_TABLE)))
	if effective_hash.is_empty() or str(shipped.get("hash", "")) == effective_hash:
		return ""
	return JSON.stringify(Tuning.current.client_table())


func _reject(session: Sessions.Session, reason: Protocol.Reject) -> void:
	transport.send(session.peer, Lane.Id.CONTROL, Protocol.reject(reason))
	_closing[session.peer] = 3  # let ENet deliver the Reject, then disconnect


## NET-11: sends `slot`'s client away with `reason` (Reject.REMOVED: MOD-11's kicks and ejections).
func remove(slot: int, reason: Protocol.Reject) -> bool:
	for session: Sessions.Session in sessions.welcomed():
		if session.slot == slot:
			_reject(session, reason)
			return true
	return false


## SND-10: the crew-list label of the miner in `slot` (shown when unknown). UI-04 relays it.
func mute_label(slot: int) -> bool:
	for session: Sessions.Session in sessions.welcomed():
		if session.slot == slot:
			return session.mute_label
	return true


func _route(lane: int, slot: int, type: int, payload: PackedByteArray) -> void:
	var list: Array = routed.get(lane, [])
	list.append([slot, type, payload])
	routed[lane] = list


func _count_bad(peer: int) -> void:
	bad_messages[peer] = int(Variants.number(bad_messages.get(peer, 0))) + 1
