extends Node
## The client entry (FND-03). It shows the dev lobby (STM-02 replaces the placeholder) or,
## with --connect, heads for a direct connection (NET-02 supplies the transport).

const TICK_SECONDS: float = 0.05

var config: ClientConfig = null
var ticks: int = 0
var connection: ClientConnection = null
var _accumulated: float = 0.0
var _reported_state: int = -1
## MNR-15: the bindings (user://input.cfg), the router that turns them into intents, and the
## Godot device source; one input record per received frame until NET-05's predicted tick.
var bindings: BindingsStore = BindingsStore.new()
var router: InputRouter = null
var source: GodotInputSource = null
## VIS-01: the one camera, following the own miner.
var camera: LampCamera = null
## SND-03: the client's sounds: delivered events, the beds, the sputter.
var events_player: EventPlayer = null
var beds: AmbientBeds = null
## SND-04: the ears on the own miner, the deafened ringing and dip, and the audio options.
var listener: MinerListener = null
var deafness: Deafness = null
var knocks: KnocksPlayer = null
var audio_options: AudioOptions = null
## SND-05: the microphone, open only while the mic mode allows it and voice is live (SND-06 and
## SND-07 take its frames; SND-10 supplies the mode, Mute until its first-launch choice exists).
var voice_capture: VoiceCapture = null
## SND-10: the player's microphone choice (Mute until chosen), its consent log and the crew-list label.
var mic_mode: MicMode = null
## SND-06: the own voice's loudness band (SND-07 sends it; the breath-cloud shows it).
var voice_bands: VoiceBands = null
## SND-07: the own voice upstream, and the others' voices played.
var voice_sender: VoiceSender = null
var voice_playback: VoicePlayback = null
var _events_played: int = 0
## NET-12: light-to-contents and about-turn probes on this client; a telemetry summary each minute
## (release builds keep no per-tile sample).
var probes: ClientProbes = null
var _probe_reported_usec: int = 0
## FND-08: the console, truth view and QA overlay (DebugClient), outside release builds only.
const DEBUG_CLIENT: String = "res://client/debug/debug_client.gd"
var debug: Node = null
## VIS-05: the mine view and what it may draw.
var world_view: WorldView = null
## UI-01: the in-play UI (only the design's private elements).
var in_play: InPlayLayer = null
var _ui_violations_seen: Dictionary = {}
var drawn: DrawnSet = DrawnSet.new()
var _facing_seq: int = -1
## NET-12: the facing as drawn and heard: it turns toward the wanted one (the input's) at
## movement.turn_rate_deg_s, as the server and NET-05's prediction turn the miner.
var _shown_facing: int = 0
var _last_facing: int = -1
var _input_frame: int = -1
## FND-09's headless bot (tools/bots/bot_client.gd), when started with --bot.
var _bot: RefCounted = null


func start(client_config: ClientConfig) -> void:
	config = client_config
	if not Tuning.load_client():
		Log.error("client tuning table failed to load")
		get_tree().quit(ExitCode.FATAL)
		return
	Log.info("client tuning loaded: %d keys" % Tuning.current.entries.size())
	if not config.bot_script.is_empty():
		_start_bot()
		return
	if not config.connect_target.is_empty():
		_connect(config.connect_target)
	elif not config.connect_lobby.is_empty():
		Log.info("Steam lobby %s requested (lobbies arrive with STM-02)" % config.connect_lobby)
	_start_input()
	_show_pithead()
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if _bot != null:
		var code: int = _bot.call(&"process")
		if code >= 0:
			Log.close()
			get_tree().quit(code)
			set_process(false)
		return
	if connection != null:
		connection.poll()
		_report_connection()
		_follow_camera(delta)
		_play_audio()
		if voice_capture != null:
			voice_capture.voice_live = connection.state == ClientConnection.State.CONNECTED
			voice_capture.tick(Time.get_ticks_usec())
			voice_bands.ptt_held = router != null and router.push_to_talk_held
			voice_playback.tick(connection, Transport.now_usec())
			if world_view != null:
				var shown_band: int = InPlayLayer.breath_band(voice_bands.band, voice_bands.sending(),
					mic_mode != null and mic_mode.voice_enabled(), router != null and router.aside_held)
				world_view.breath.set_band(shown_band, Time.get_ticks_msec() / 1000.0)
		if connection.state == ClientConnection.State.CONNECTED and connection.last_frame_tick > _input_frame:
			_input_frame = connection.last_frame_tick
			var stamp: PackedInt64Array = connection.stamp_for_send(Transport.now_usec())
			var record: InputRecord = _sample_input(stamp[0])
			# VIS-05: the input that turns the miner; held walls show provisionally until it is acknowledged.
			if record.facing != _last_facing:
				_last_facing = record.facing
				_facing_seq = connection.inputs.next_seq & 0xFFFF
			connection.inputs.send_tick(connection, record, stamp[0], stamp[1])
	if config.exit_after_ticks <= 0:
		return
	_accumulated += delta
	while _accumulated >= TICK_SECONDS:
		_accumulated -= TICK_SECONDS
		ticks += 1
	if ticks >= config.exit_after_ticks:
		if connection != null and connection.state == ClientConnection.State.CONNECTED:
			Log.info("frames received %d, last frame tick %d, rtt %.1f ms, inputs sent %d" % [connection.frames_received,
				connection.last_frame_tick, connection.clock.rtt_ms(), connection.inputs.packets_sent])
			connection.close()
		# SND-05: the device-open count for the session (never audio); Mute must leave it at 0.
		Log.info("voice: the microphone opened %d times this session" % LbVoiceCapture.total_open_count())
		Log.info("exit after %d ticks" % ticks)
		Log.close()
		get_tree().quit(ExitCode.OK)


func _start_input() -> void:
	if FileAccess.file_exists(BindingsStore.PATH) and bindings.load_from() != OK:
		Log.warn("input.cfg unreadable; using the default bindings")
	router = InputRouter.new(bindings, "kbm")
	source = GodotInputSource.new("kbm", get_viewport())
	camera = LampCamera.new()
	camera.name = "LampCamera"
	add_child(camera)
	camera.make_current()
	world_view = WorldView.new()
	world_view.name = "WorldView"
	add_child(world_view)
	in_play = InPlayLayer.new()
	add_child(in_play)
	AudioBuses.install()
	events_player = EventPlayer.new()
	events_player.name = "EventPlayer"
	add_child(events_player)
	beds = AmbientBeds.new()
	beds.name = "AmbientBeds"
	add_child(beds)
	listener = MinerListener.new(events_player.mixer, events_player)
	deafness = Deafness.new(beds)
	deafness.name = "Deafness"
	add_child(deafness)
	knocks = KnocksPlayer.new(deafness)
	knocks.name = "Knocks"
	add_child(knocks)
	audio_options = AudioOptions.load_from()
	audio_options.apply(events_player.mixer)
	mic_mode = MicMode.new()
	voice_capture = VoiceCapture.new()
	voice_capture.mic_mode = func() -> int: return mic_mode.mode
	voice_bands = VoiceBands.new()
	voice_capture.state_changed.connect(_on_voice_state)
	voice_capture.frame_ready.connect(_on_voice_frame)
	voice_sender = VoiceSender.new()
	voice_sender.send = func(packet: PackedByteArray) -> void:
		if connection != null and connection.state == ClientConnection.State.CONNECTED:
			connection.send_voice(packet)
	voice_playback = VoicePlayback.new()
	voice_playback.mixer = events_player.mixer
	mic_mode.label_changed.connect(_send_mic_label)
	Log.info("voice: capture ready, backend %s, mic mode %s" % [voice_capture.backend,
		MicMode.Mode.keys()[voice_capture.effective_mode()]])
	_start_debug()


## FND-08: the debug client, loaded by path so no release script names a debug class. Release builds
## read no debug input: the folder is not in their pack.
func _start_debug() -> void:
	if config.build.is_release() or not ResourceLoader.exists(DEBUG_CLIENT):
		return
	var script: GDScript = load(DEBUG_CLIENT)
	debug = script.new()
	debug.name = "Debug"
	debug.set(&"connection", connection)
	debug.set(&"listener", listener)
	var origin: Callable = func() -> Vector2:
		if connection == null or connection.view == null or connection.view.own.is_empty():
			return Vector2.ZERO
		var own: Vector2 = connection.view.own["position"]
		return camera.view_rect(own).position
	debug.set(&"view_origin", origin)
	add_child(debug)


## The last device used picks the family; the mouse wheel arrives only as events.
func _input(event: InputEvent) -> void:
	if source == null:
		return
	var pad: bool = event is InputEventJoypadButton or (event is InputEventJoypadMotion
		and absf((event as InputEventJoypadMotion).axis_value) > Tuning.f(&"movement.stick_dead_zone"))
	var kbm: bool = event is InputEventKey or event is InputEventMouseButton
	if pad or kbm:
		var family: String = "pad" if pad else "kbm"
		if family != router.family:
			router.family = family
			source.family = family
			source.device = event.device
	source.push_event(event, bindings)


func _sample_input(shown_tick: int) -> InputRecord:
	router.know_inventory(connection.inventory)
	router.know_ring(connection.ring)
	source.wheel_open = router.picking()
	var record: InputRecord = router.sample(source.frame(Time.get_ticks_msec() / 1000.0, bindings))
	for action: Array in router.actions:
		connection.inputs.queue_action(int(Variants.number(action[0])) as ActionRecord.Kind, int(Variants.number(action[1])), shown_tick,
			int(Variants.number(action[2])))
	return record


## The camera follows the own miner as last received (NET-05's predicted position once the client
## predicts), easing its lead; the squint or the aim (MNR-15's held bits) gives the 8-tile lead.
## Mouse facing is measured from the miner's position without the lead: the screen's centre.
func _follow_camera(delta: float) -> void:
	if camera == null or connection.view == null or connection.view.own.is_empty():
		return
	var own: Vector2 = connection.view.own["position"]
	var squint: bool = (router.record.holds & (InputRecord.HOLD_SQUINT | InputRecord.HOLD_AIM)) != 0
	var rate: float = Tuning.f(&"movement.turn_rate_deg_s") if Tuning.current.has_key(&"movement.turn_rate_deg_s") else 0.0
	_shown_facing = MinerMotion.turn_toward(_shown_facing, router.record.facing, MinerMotion.turn_step(rate, delta))
	camera.follow(own, _shown_facing, squint, delta)
	source.own_screen = get_viewport().get_visible_rect().size / 2.0
	# VIS-05: the drawn set and the darkness composite, from the live facing and the own lamp
	# (NET-05's predicted pool replaces the server's radius once the client predicts).
	var radius: float = float(Variants.number(connection.view.own.get("lamp_radius", 0.0)))
	var predicted: Dictionary = {"position": own, "facing": _shown_facing,
		"lamp": {"position": own, "radius": radius} if radius > 0.0 else {}}
	drawn.build(connection.view, predicted, connection.last_input_ack, _facing_seq)
	# VIS-06: the own lamp blended over the server's light (the same lamp both sides until NET-05's
	# predicted pool is wired here; then a wick step shows at once).
	var server_lamp: Dictionary = {"position": own, "radius": radius}
	var lights: Dictionary = OwnLampBlend.lights(drawn, connection.view, server_lamp, Variants.dict(predicted["lamp"]))
	var own_light: float = float(Variants.number(lights.get(Vector2i(floori(own.x), floori(own.y)), 0.0)))
	world_view.show_frame(drawn, connection.view, camera.view_rect(own).position, own, _shown_facing, own_light,
		lights, Time.get_ticks_msec() / 1000.0)
	_show_in_play(own)
	_probe(predicted)


## UI-01: the in-play elements; debug and test builds check that nothing else is drawn.
func _show_in_play(own: Vector2) -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	in_play.update({"view": connection.view, "view_origin": camera.view_rect(own).position,
		"black": world_view.mode == WorldView.Mode.BLACK, "inventory": connection.inventory, "feel": connection.feel,
		"router": router, "store": bindings, "wheel_anchor": source.wheel_anchor() if router.family == "kbm" else screen / 2.0,
		"short_side": minf(screen.x, screen.y), "now_s": Time.get_ticks_msec() / 1000.0})
	if config.build.is_release():
		return
	for v: String in in_play.check_frame([world_view.overlay_layer()]):
		if not _ui_violations_seen.has(v):
			_ui_violations_seen[v] = true
			push_error("UI-01: unregistered in-play element %s" % v)


## NET-12: one probe frame against the lamp the client predicts, and a telemetry line each minute.
func _probe(predicted: Dictionary) -> void:
	if probes == null:
		probes = ClientProbes.new()
		probes.keep_samples = not config.build.is_release()
		_probe_reported_usec = Time.get_ticks_usec()
	probes.on_frame(Time.get_ticks_usec(), connection.view, Variants.dict(predicted["lamp"]), _shown_facing)
	if Time.get_ticks_usec() - _probe_reported_usec >= 60000000:
		_probe_reported_usec = Time.get_ticks_usec()
		var s: Dictionary = probes.summary()
		var light: Dictionary = s["light"]
		var turn: Dictionary = s["turn"]
		Log.info("telemetry probes light_n=%s light_p95_ms=%s turn_n=%s turn_p95_ms=%s turn_held_frames_max=%s down_bytes=%s up_bytes=%s" % [
			light["n"], light["p95"], turn["n"], turn["p95"], s["turn_held_frames_max"], connection.bytes_in, connection.bytes_out])


## SND-03: each delivered event plays once, ambient cues change the beds, guttering flames sputter.
## SND-04: the ears follow the own miner and its live facing (never the camera); a Deafened record
## starts the ringing and the beds' dip.
func _play_audio() -> void:
	if events_player == null or connection.view == null:
		return
	var own: Vector2 = connection.view.own["position"]
	listener.follow(own, _shown_facing)
	while _events_played < connection.events.size():
		var ev: Dictionary = connection.events[_events_played]
		var record: AudioRecord = AudioRecord.from_event(ev)
		if VisualEvents.is_visual(record.type):
			world_view.puffs.add(record, Time.get_ticks_msec() / 1000.0)  # VIS-09: drawn, not played
		else:
			events_player.play(record, int(Variants.number(ev.get("number", _events_played))))
		_events_played += 1
	while not connection.ambient_cues.is_empty():
		var cue: Dictionary = connection.ambient_cues.pop_front()
		beds.apply(cue)
	while not connection.deafened.is_empty():
		var record: Dictionary = connection.deafened.pop_front()
		deafness.start(record)
	while connection.knocks > 0:
		connection.knocks -= 1
		knocks.enqueue()
	var sputters: Array[Vector2] = []
	if (int(Variants.number(connection.view.own.get("flame", 0))) & FlameFlags.GUTTER) != 0:
		sputters.append(connection.view.own["position"])
	for raw: Variant in connection.view.entities.values():
		var e: Dictionary = raw
		if (int(Variants.number(e.get("flame", 0))) & FlameFlags.GUTTER) != 0:
			sputters.append(e["position"])
	events_player.set_sputters(sputters)


## Bot mode (FND-09): no lobby, no rendering, no audio; the brains live in the source tree.
func _start_bot() -> void:
	const BOT_CLIENT: String = "res://tools/bots/bot_client.gd"
	Log.info("bot mode: display=%s audio=%s" % [DisplayServer.get_name(), AudioServer.get_driver_name()])
	if not ResourceLoader.exists(BOT_CLIENT):
		Log.error("bot brains are not in this build; run bots from the source tree")
		get_tree().quit(ExitCode.BAD_ARGUMENTS)
		return
	Engine.max_fps = 250
	var script: GDScript = load(BOT_CLIENT)
	_bot = script.new()
	if not _bot.call(&"start", config):
		get_tree().quit(ExitCode.BAD_ARGUMENTS)
		return
	set_process(true)


## A direct ENet connection (NET-02), for development and the M1 kill test.
func _connect(target: String) -> void:
	var host: String = target.substr(0, target.rfind(":"))
	var port: int = target.substr(target.rfind(":") + 1).to_int()
	connection = ClientConnection.new(EnetTransport.new())
	connection.identity = config.persona_name if not config.persona_name.is_empty() else "dev"
	connection.qa_token = config.qa_token
	connection.seat_request = Protocol.Seat.BOT if not config.bot_script.is_empty() else Protocol.Seat.PLAYER
	if connection.start(host, port):
		Log.info("connecting to %s" % target)
	else:
		Log.error("could not start a connection to %s" % target)


func _report_connection() -> void:
	if connection.state == _reported_state:
		return
	_reported_state = connection.state
	match connection.state:
		ClientConnection.State.CONNECTED:
			Log.info("welcomed: slot %d, server tick %d, %d Hz" % [connection.welcome.slot,
				connection.welcome.server_tick, connection.welcome.tick_hz])
			if mic_mode != null:
				_send_mic_label(mic_mode.show_mute_label())
		ClientConnection.State.REJECTED:
			Log.warn("refused by the server: %s" % RejectText.text(connection.reject_reason))
		ClientConnection.State.DROPPED:
			Log.warn("connection lost: %s" % connection.drop_reason)


## SND-05/06/10: the capture opened, closed or lost its device: the label follows, and the band
## meter takes that device's thresholds (or the defaults), or falls silent.
func _on_voice_state(state: int) -> void:
	mic_mode.set_device_present(not voice_capture.no_device())
	if state == VoiceCapture.State.OPEN:
		voice_bands.set_thresholds(Calibration.thresholds_for(voice_capture.native.device_id()))
	else:
		voice_sender.stop()
		voice_bands.reset()


## SND-06 measures each clean frame, then SND-07 sends it if it may go out.
func _on_voice_frame(pcm: PackedFloat32Array, _ticks_usec: int) -> void:
	voice_bands.push(pcm)
	voice_sender.on_frame(pcm, voice_bands)


## SND-10: the label flag on joining and on every change; nothing else about voice goes to the server.
func _send_mic_label(muted: bool) -> void:
	if connection != null and connection.state == ClientConnection.State.CONNECTED:
		connection.send_mic_label(muted)


## Placeholder Pithead until MOD-04: one Play button. Play leads through the first-launch screens
## (the comfort step, the microphone choice; SND-10) before any lobby.
func _show_pithead() -> void:
	var play: Button = Button.new()
	play.name = "Play"
	play.text = "Play"
	play.custom_minimum_size = Vector2(320, 64)
	play.set_anchors_preset(Control.PRESET_CENTER)
	play.pressed.connect(func() -> void:
		play.queue_free()
		_start_first_launch())
	add_child(play)
	Log.info("pithead shown")


func _start_first_launch() -> void:
	var flow: FirstLaunch = FirstLaunch.new(mic_mode)
	flow.name = "FirstLaunch"
	flow.finished.connect(func() -> void:
		flow.queue_free()
		Log.info("microphone: %s under notice %d" % [MicMode.MODE_NAMES[mic_mode.mode], mic_mode.notice_version])
		_show_dev_lobby())
	add_child(flow)


## Placeholder until STM-02's dev lobby screen exists.
func _show_dev_lobby() -> void:
	var label: Label = Label.new()
	label.name = "DevLobby"
	label.text = "LAMPBLACK\ndev lobby (STM-02)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(label)
	Log.info("dev lobby shown")
