class_name ClientConnection
extends RefCounted
## The client's connection to the server (NET-02): handshake, clock sync and drop detection
## over any Transport.

enum State { IDLE, CONNECTING, CONNECTED, REJECTED, DROPPED }

var transport: Transport
var state: State = State.IDLE
var peer: int = -1
var identity: String = "dev"
var seat_request: int = Protocol.Seat.PLAYER
var session_token: String = ""
## Overridable for tests.
var build_id: String = Protocol.build_id()
var protocol_version: int = Protocol.PROTOCOL_VERSION
var welcome: Protocol.Welcome = null
var reject_reason: int = -1
var drop_reason: String = ""
var clock: ClockSync = ClockSync.new()
var frames_received: int = 0
var last_frame_tick: int = -1
## NET-03: the newest input seq the server applied, from the last frame (VIS-05's reconciliation).
var last_input_ack: int = -1
## NET-05's client timeline, fed by each newer frame: the render time NET-03 stamps on inputs.
var timeline: ClientClock = ClientClock.new()
## NET-06: timed cues presented on that timeline and reported up.
var cues: CueReporter = CueReporter.new()
## NET-03: inputs up, and the action acknowledgement and buffer depth from each frame header.
var inputs: ClientInputSender = ClientInputSender.new()
## NET-04: frames decoded against the baselines they name; `view` is what the client holds now.
var decoder: FrameDecoder = FrameDecoder.new()
var view: ReceivedView = null
## MNR-04: the own miner's hands and belt, as last received (InventoryWire.decode), and how many
## such messages arrived.
var inventory: Dictionary = {}
var inventory_messages: int = 0
## VIS-07: the own miner's feel answers and wall bumps.
var feel: FeelClient = FeelClient.new()
## MNR-05: the interact ring as last received (RingMessages.decode); {} before any.
var ring: Dictionary = {}
var ring_messages: int = 0
## SND-03: ambient cues in arrival order ({layer, start, fade_s}); the audio side drains them.
var ambient_cues: Array[Dictionary] = []
## SND-04: Deafened records in arrival order ({duration_s, dip_db}); the audio side drains them.
var deafened: Array[Dictionary] = []
## SND-15: KNOCKS messages not yet played (each is a fall's set; the message carries nothing).
var knocks: int = 0
## RSC-04: WATCH and REPLAY messages not yet taken (DarkView drains them), decoded.
var watch_in: Array[Dictionary] = []
var replay_in: Array[Dictionary] = []
## SND-11: callout records not yet played, in arrival order (CalloutPlayer drains them).
var callouts: Array[CalloutRecord] = []
## UI-02: the own close-up and the board's seat as last received (CloseupKind.decode); {} before any.
var closeup: Dictionary = {}
var closeup_messages: int = 0
## LFT-14: this client's copy of the map table's sheet (shown only in its close-up), and LFT-03's
## of the Manual's pencil layer: SheetKind -> ClientSheet.
var sheet: ClientSheet = ClientSheet.new(SheetKind.Kind.MAP_TABLE)
var sheets: Dictionary = {}
## LFT-03: the run's repair list as the Manual prints it ({kind, cans, jobs}), {} until first shown.
var manual: Dictionary = {}
## SND-07: voice packets from the server in arrival order, [packet, arrival usec]; VoicePlayback
## drains them (a bounded queue: older ones go first if nobody does).
var voice_in: Array[Array] = []
const VOICE_IN_MAX: int = 256
## Audio events received, each once, in arrival order (SND-03 plays them).
var events: Array[Dictionary] = []
var _event_numbers: Dictionary = {}
## FND-09: bytes received and sent per lane, and an optional observer called with
## (lane, data, now_usec) for every message received (bots' receive logs).
var bytes_in: Dictionary = {}
var bytes_out: Dictionary = {}
var message_observer: Callable = Callable()
## FND-08: the QA token this client presents (--qa-token), and debug-lane messages in arrival order
## ({type, payload}) once the server granted the channel. A message on the debug lane without the
## grant, or in a release build, is dropped and counted as a protocol violation.
var qa_token: String = ""
## NET-09: this member's copy of the run's saves (stored, never opened).
var saves: SaveStore = SaveStore.new()
## The own miner's status (StatusWire.decode): cues, the self-rescue offer, the self-revive.
var status: Dictionary = {}
var debug_inbox: Array[Dictionary] = []
var debug_violations: int = 0
## Messages received before Welcome other than Reject (must stay 0).
var early_messages: int = 0
var handshake_timeout_usec: int = 5000000
var _started_usec: int = 0


func _init(net_transport: Transport) -> void:
	transport = net_transport
	sheets[SheetKind.Kind.MAP_TABLE] = sheet
	sheets[SheetKind.Kind.MANUAL] = ClientSheet.new(SheetKind.Kind.MANUAL)
	for raw: Variant in sheets.values():
		var cs: ClientSheet = raw
		cs.send = func(lane: int, payload: PackedByteArray) -> Error: return send(lane, payload, Protocol.Msg.SHEET)
	if Tuning.current.has_key(&"net.handshake_timeout_s"):
		handshake_timeout_usec = roundi(Tuning.f(&"net.handshake_timeout_s") * 1000000.0)


func start(host: String, port: int) -> bool:
	_started_usec = Transport.now_usec()
	peer = transport.connect_to(host, port)
	state = State.CONNECTING if peer >= 0 else State.DROPPED
	return peer >= 0


func poll() -> void:
	var now: int = Transport.now_usec()
	for event: TransportEvent in transport.poll():
		match event.kind:
			TransportEvent.Kind.CONNECTED:
				_send_hello()
			TransportEvent.Kind.DROPPED:
				if state == State.CONNECTING or state == State.CONNECTED:
					state = State.DROPPED
					drop_reason = event.reason
			TransportEvent.Kind.MESSAGE:
				bytes_in[event.lane] = int(Variants.number(bytes_in.get(event.lane, 0))) + event.data.size()
				if message_observer.is_valid():
					message_observer.call(event.lane, event.data, now)
				_on_message(event, now)
	if state == State.CONNECTING and now - _started_usec > handshake_timeout_usec:
		state = State.DROPPED
		drop_reason = "handshake_timeout"
		transport.disconnect_peer(peer)
	if state == State.CONNECTED and clock.ping_due(now):
		transport.send(peer, Lane.Id.CONTROL, Protocol.ping(now))
	if state == State.CONNECTED:
		for raw: Variant in sheets.values():
			var cs: ClientSheet = raw
			cs.pump(now)
	transport.flush()


## LFT-14 and LFT-03: this client's copy of a sheet (SheetKind), or null.
func sheet_of(kind: int) -> ClientSheet:
	var cs: ClientSheet = sheets.get(kind, null)
	return cs


func send(lane: int, payload: PackedByteArray, type: int) -> Error:
	return send_raw(lane, Protocol.frame(type as Protocol.Msg, payload))


## Sends an already framed message (InputPacket.encode() frames itself).
func send_raw(lane: int, framed: PackedByteArray) -> Error:
	if state != State.CONNECTED:
		return ERR_UNCONFIGURED
	bytes_out[lane] = int(Variants.number(bytes_out.get(lane, 0))) + framed.size()
	return transport.send(peer, lane, framed)


## SND-07: one voice packet upstream (VoicePackets.up, .end or .probe), on the voice lane.
func send_voice(packet: PackedByteArray) -> Error:
	return send_raw(Lane.Id.VOICE, Protocol.frame(Protocol.Msg.VOICE, packet))


## SND-10: the crew-list label flag, on joining and whenever it changes.
func send_mic_label(muted: bool) -> Error:
	return send_raw(Lane.Id.CONTROL, Protocol.mic_label(muted))


func close() -> void:
	transport.close()
	state = State.IDLE


func _send_hello() -> void:
	var hello: Protocol.Hello = Protocol.Hello.new()
	hello.protocol_version = protocol_version
	hello.build_id = build_id
	hello.identity = identity
	hello.seat_request = seat_request
	hello.session_token = session_token
	hello.flavour = transport.build.flavour
	hello.qa_token = "" if transport.build.is_release() else qa_token
	transport.send(peer, Lane.Id.CONTROL, hello.encode())


## FND-08: the server opened the debug lane to this client (never in a release build).
func has_debug() -> bool:
	return state == State.CONNECTED and welcome != null and welcome.debug and not transport.build.is_release()


func _on_message(event: TransportEvent, now: int) -> void:
	var message: Dictionary = Protocol.unframe(event.data)
	if message.is_empty():
		return
	var type: int = int(Variants.number(message["type"]))
	var payload: PackedByteArray = message["payload"]
	if event.lane == Lane.Id.DEBUG:
		if has_debug():
			debug_inbox.append({"type": type, "payload": payload})
		else:
			debug_violations += 1
			Log.warn("protocol violation: a debug-lane message without the debug channel; dropped")
		return
	if state == State.CONNECTING:
		if type == Protocol.Msg.WELCOME:
			welcome = Protocol.Welcome.decode(payload)
			session_token = welcome.session_token
			state = State.CONNECTED
			if not welcome.client_tuning.is_empty():
				Log.info("server sent an updated client tuning table (%s)" % welcome.client_tuning_hash.left(12))
		elif type == Protocol.Msg.REJECT:
			reject_reason = Protocol.read_u8(payload)
			state = State.REJECTED
		else:
			early_messages += 1
		return
	match type:
		Protocol.Msg.SAVE_DATA:
			var seq: int = saves.on_save_data(payload)
			if seq >= 0:
				send(Lane.Id.CONTROL, SaveWire.ack(seq), Protocol.Msg.SAVE_ACK)
		Protocol.Msg.JOURNAL:
			saves.on_journal(payload, now)
		Protocol.Msg.STATUS:
			var st: Dictionary = StatusWire.decode(payload)
			if not st.is_empty():
				status = st
		Protocol.Msg.REJECT:
			# NET-11: removed mid-run (MOD-11's kick or ejection): back to the Pithead.
			reject_reason = Protocol.read_u8(payload)
			state = State.REJECTED
		Protocol.Msg.PONG:
			clock.on_pong(Protocol.read_i64(payload, 0), Protocol.read_i64(payload, 1), now)
		Protocol.Msg.FEEL:
			feel.on_message(payload)
		Protocol.Msg.RING:
			var r: Dictionary = RingMessages.decode(payload)
			if not r.is_empty():
				ring = r
				ring_messages += 1
		Protocol.Msg.AMBIENT:
			var cue: Dictionary = AmbientMessages.decode(payload)
			if not cue.is_empty():
				ambient_cues.append(cue)
		Protocol.Msg.VOICE:
			if event.lane == Lane.Id.VOICE and payload.size() >= VoicePackets.DOWN_HEADER:
				voice_in.append([payload, now])
				if voice_in.size() > VOICE_IN_MAX:
					voice_in.pop_front()
		Protocol.Msg.KNOCKS:
			if payload.is_empty():
				knocks += 1
		Protocol.Msg.WATCH, Protocol.Msg.REPLAY:
			var d: Dictionary = DarkMessages.decode(payload)
			if not d.is_empty():
				(watch_in if type == Protocol.Msg.WATCH else replay_in).append(d)
		Protocol.Msg.CALLOUT:
			var r: CalloutRecord = CalloutRecord.decode(payload)
			if r != null:
				callouts.append(r)
		Protocol.Msg.SHEET:
			if event.lane == Lane.Id.BULK or event.lane == Lane.Id.FRAMES:
				var parts: Dictionary = SheetCodec.by_sheet(SheetCodec.decode(payload))
				for raw: Variant in parts.keys():
					var cs: ClientSheet = sheets.get(int(Variants.number(raw)), null)
					if cs != null:
						var ops: Array[Dictionary] = parts[raw]
						cs.apply_ops(ops, now)
		Protocol.Msg.MANUAL:
			var list: Dictionary = RepairJobs.decode(payload)
			if not list.is_empty():
				manual = list
		Protocol.Msg.CLOSE_UP:
			var c: Dictionary = CloseupKind.decode(payload)
			if not c.is_empty():
				closeup = c
				closeup_messages += 1
		Protocol.Msg.DEAFENED:
			var d: Dictionary = DeafenedMessages.decode(payload)
			if not d.is_empty():
				deafened.append(d)
		Protocol.Msg.INVENTORY:
			var own: Dictionary = InventoryWire.decode(payload)
			if not own.is_empty():
				inventory = own
				inventory_messages += 1
		Protocol.Msg.FRAME:
			var decoded: FrameDecoder.Decoded = decoder.decode(payload)
			if not decoded.ok:
				return
			frames_received += 1
			if decoded.tick > last_frame_tick:
				timeline.on_frame(decoded.tick, now)
			last_frame_tick = decoded.tick
			last_input_ack = decoded.input_ack
			view = decoded.view
			for e: Dictionary in decoded.events:
				var number: int = int(Variants.number(e["number"]))
				if not _event_numbers.has(number):
					_event_numbers[number] = true
					events.append(e)
					cues.on_event(e)
			inputs.on_frame(last_frame_tick, decoded.action_ack, decoded.input_depth, now)


## The tick the client is showing now and its fraction (0-255), for an input's stamp (NET-03):
## the render time, net.interp_delay_ms behind the received timeline (NET-05, NET-06).
func shown_stamp(now_usec: int) -> PackedInt64Array:
	if not timeline.has_estimate():
		return PackedInt64Array([maxi(last_frame_tick, 0), 0])
	var t: float = maxf(timeline.shown_tick(now_usec), 0.0)
	var whole: int = floori(t)
	return PackedInt64Array([whole, clampi(floori((t - whole) * 256.0), 0, 255)])


## Before each tick's input goes up: present the timed cues the shown time has reached and
## return the input's stamp.
func stamp_for_send(now_usec: int) -> PackedInt64Array:
	var stamp: PackedInt64Array = shown_stamp(now_usec)
	cues.poll(float(stamp[0]) + stamp[1] / 256.0, inputs)
	return stamp
