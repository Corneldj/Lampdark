extends Node
## The client entry (FND-03). It shows the dev lobby (STM-02 replaces the placeholder) or,
## with --connect, heads for a direct connection (NET-02 supplies the transport).

const TICK_SECONDS: float = 0.05

var config: ClientConfig = null
var ticks: int = 0
var connection: ClientConnection = null
var _accumulated: float = 0.0
var _reported_state: int = -1
## The first-launch screens are done (the lobby may show).
var _first_launch_done: bool = false
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
## The menus (Pithead, first-launch screens, dev lobby, Steam failure) on their own layer: the mine
## camera moves the default canvas, and the mine view is drawn on it.
const MENU_LAYER: int = 20
var menus: CanvasLayer = null
## STM-01: Steam (or dev mode), brought up before anything else.
var steam: SteamService = null
## STM-02: the friends lobby (Steam's, or the dev server's rendezvous in dev mode).
var lobby: LobbyService = null
## STM-04: a private host's server process, and Path B's relay.
var local_server: LocalServerHost = null
var host_relay: HostRelay = null
## UI-01: the in-play UI (only the design's private elements).
var in_play: InPlayLayer = null
## UI-02's close-ups, over the mine and under the menus.
var closeups: CloseupManager = null
## UI-03's captions and subtitles.
var captions: CaptionLayer = null
## RSC-04's Dark: the black, the replay of the fall, watching.
var dark: DarkView = DarkView.new()
## SND-11's callouts: played as heard; the wheel's picks.
var callout_player: CalloutPlayer = null
var callout_wheel: CalloutWheel = null
## LFT-14: the map table's close-up, and the map card once the sheet freezes (RSC-06 shows it).
var map_table: MapTableCloseup = null
var map_card: Image = null
## RSC-06: Lamp Check's screen while it is open, on its own layer under the captions (12).
const LAMP_CHECK_LAYER: int = 11
var lamp_check: LampCheckView = null
var _lamp_check_layer: CanvasLayer = null
var _lamp_check_seen: int = 0
## MOD-01's profile and its store, loaded at start (MOD-03): the hello offers its Available miners,
## and the one seated goes Below once the run begins; Lamp Check puts the run's outcome on that
## roster. Null for a bot.
var profile: Profile = null
var profile_store: ProfileStore = null
## MOD-03: the run the seated miner went Below for ("" until the run's first frame, and after Lamp
## Check); a connection lost before Lamp Check ends it abnormally on the roster (RSC-06).
var _seated_run: String = ""
## MOD-05: the host may knock off now (UI-05's "Knock off" shows only then); and the save a host's
## server resumes when the crew opens ("" for a new run; UI-04's resume list sets it).
var knock_off_available: bool = false
var resume_path: String = ""
## LFT-03: the Manual at its lectern.
var manual_closeup: ManualCloseup = null
var _closeup_messages_seen: int = 0
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
	if not _start_steam():
		return
	if not Tuning.load_client():
		Log.error("client tuning table failed to load")
		get_tree().quit(ExitCode.FATAL)
		return
	Log.info("client tuning loaded: %d keys" % Tuning.current.entries.size())
	if not config.bot_script.is_empty():
		_start_bot()
		return
	_load_profile()
	_start_lobby()
	if not config.connect_target.is_empty():
		_connect(config.connect_target)
	elif not config.connect_lobby.is_empty():
		Log.info("Steam lobby %s requested (lobbies arrive with STM-02)" % config.connect_lobby)
	_start_input()
	_show_pithead()
	set_process(true)


func _ready() -> void:
	set_process(false)
	_menus()


func _menus() -> CanvasLayer:
	if menus == null:
		menus = CanvasLayer.new()
		menus.name = "Menus"
		menus.layer = MENU_LAYER
		add_child(menus)
	return menus


## STM-01's boot order: release builds relaunch through Steam when needed and quit; then Steam
## initialises, or dev and QA builds fall back to dev mode, or a release build shows the failure
## screen and exits 4. Bots never start Steam. False when the client must not go on.
func _start_steam() -> bool:
	steam = SteamService.new()
	add_child(steam)
	var no_steam: bool = config.no_steam or not config.bot_script.is_empty()
	match steam.boot(config.build.is_release(), no_steam, config.persona_name):
		SteamService.Boot.QUIT_RELAUNCHING:
			Log.close()
			get_tree().quit(ExitCode.OK)
			return false
		SteamService.Boot.FAIL:
			_show_steam_failure()
			return false
	steam.overlay_toggled.connect(_on_overlay_toggled)
	if not config.sdr_fake.is_empty() and steam.available():
		var parts: PackedStringArray = config.sdr_fake.split(",")
		if SdrTransport.set_fake_conditions(steam.api, config.build, parts[0].to_int(), parts[1].to_float()):
			Log.info("steam: SDR fake conditions %s (lag ms, loss %%)" % config.sdr_fake)
	return true


## STM-02: the lobby service on Steam's backend, or (dev mode) on the dev server's rendezvous at the
## --connect host (else this machine), on the game port plus net.dev_lobby_port_offset.
func _start_lobby() -> void:
	MenuInput.install()
	var target: String = config.connect_target if not config.connect_target.is_empty() else "127.0.0.1:%d" % Tuning.i(&"net.dev_port")
	var host: String = target.substr(0, target.rfind(":"))
	var port: int = target.substr(target.rfind(":") + 1).to_int()
	var backend: LobbyBackend = null
	if steam.available():
		backend = SteamLobbyBackend.new(steam.api)
	else:
		var fake: FakeLobbyBackend = FakeLobbyBackend.new(EnetTransport.new(), steam.steam_id, steam.persona_name())
		fake.aim(host, LobbyRendezvousWire.port_for(port))
		backend = fake
	lobby = LobbyService.new(backend, steam, config.build.is_release())
	# MOD-03: the lobby's options (UI-04's option screens change them); Go down starts the run.
	lobby.options = RunOptions.defaults(ServerConfig.Mode.FRIENDS).to_dict()
	lobby.start_pressed.connect(_on_go_down)
	# A typed or launch server address takes M1's path (lb_dev_addr: the kill test's studio server, a
	# dev server); without one, a host with Steam runs its own server (STM-04).
	if config.build.is_release():
		lobby.server_address = ""
	elif not config.connect_target.is_empty() or not steam.available():
		lobby.server_address = target
	lobby.state_changed.connect(_on_lobby_state)
	lobby.lobby_changed.connect(_send_members)
	lobby.connect_sdr_requested.connect(_connect_sdr)
	lobby.connect_requested.connect(func(address: String) -> void:
		if _may_connect():
			_connect(address))
	add_child(lobby)
	if not config.connect_lobby.is_empty():
		Log.info("lobby: +connect_lobby at launch")
		lobby.join(config.connect_lobby.to_int())


func _show_steam_failure() -> void:
	if DisplayServer.get_name() == "headless":
		Log.close()
		get_tree().quit(ExitCode.STEAM_INIT_FAILED)
		return
	var screen: SteamFailureScreen = SteamFailureScreen.new(steam.init_status)
	screen.quit_requested.connect(func(code: int) -> void:
		Log.close()
		get_tree().quit(code))
	_menus().add_child(screen)


## STM-01: the overlay is like settings (GDD §14.3): every gameplay input lets go and the miner
## stands where they are; nothing pauses online.
func _on_overlay_toggled(active: bool) -> void:
	Log.info("steam: overlay %s" % ("open" if active else "closed"))
	if active and router != null:
		router.release_all()


func _process(delta: float) -> void:
	if _bot != null:
		var code: int = _bot.call(&"process")
		if code >= 0:
			steam.shutdown()
			Log.close()
			get_tree().quit(code)
			set_process(false)
		return
	if host_relay != null:
		host_relay.poll()
	if connection != null:
		connection.poll()
		_report_connection()
		_on_run_begun()
		_follow_camera(delta)
		_play_audio()
		_keep_map_card()
		_keep_lamp_check()
		if voice_capture != null:
			voice_capture.voice_live = connection.state == ClientConnection.State.CONNECTED
			voice_capture.tick(Time.get_ticks_usec())
			voice_bands.ptt_held = router != null and router.push_to_talk_held
			voice_playback.tick(connection, Transport.now_usec())
			callout_player.tick(connection, events_player.listener)
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
		steam.shutdown()  # STM-01: hooks, then Steam, before the log closes
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
	world_view.set_shown(false)  # until the first frame: the pithead and lobby must not be drawn over
	in_play = InPlayLayer.new()
	add_child(in_play)
	closeups = CloseupManager.new()
	closeups.name = "Closeups"
	closeups.input_context = CloseupInputContext.new(router, camera)
	closeups.in_play_layer = in_play
	add_child(closeups)
	map_table = MapTableCloseup.new()
	map_table.name = "MapTableCloseup"
	map_table.client_sheet = func() -> ClientSheet: return connection.sheet if connection != null else null
	map_table.store = bindings
	map_table.router = router
	map_table.pad_state = func() -> Dictionary: return source.close_up_pad(bindings)
	map_table.show_keyboard = func(field: Rect2i) -> bool:
		return steam != null and steam.mode == SteamService.Mode.STEAM and steam.api.show_floating_keyboard(field)
	closeups.register(CloseupKind.Kind.MAP_TABLE, map_table)
	manual_closeup = ManualCloseup.new()
	manual_closeup.name = "ManualCloseup"
	manual_closeup.client_sheet = func() -> ClientSheet:
		return connection.sheet_of(SheetKind.Kind.MANUAL) if connection != null else null
	manual_closeup.manual_list = func() -> Dictionary: return connection.manual if connection != null else {}
	manual_closeup.store = bindings
	manual_closeup.router = router
	manual_closeup.pad_state = map_table.pad_state
	manual_closeup.show_keyboard = map_table.show_keyboard
	closeups.register(CloseupKind.Kind.MANUAL, manual_closeup)
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
	# UI-03: captions from exactly what plays, above the close-ups.
	captions = CaptionLayer.new()
	captions.name = "Captions"
	captions.system.arcs_only = audio_options.direction_only_arcs()
	captions.wire(events_player, voice_playback, beds, deafness, knocks, func() -> Vector2: return events_player.listener)
	add_child(captions)
	# SND-11: callouts heard, and the wheel's picks settled before they go.
	callout_player = CalloutPlayer.new()
	callout_player.mixer = events_player.mixer
	callout_player.on_caption = func(r: CalloutRecord, key: String, shares: PackedFloat32Array, direction: Variant, duration_s: float) -> void:
		captions.system.on_callout(key, shares, r.band, CalloutPlayer.voice_id_of(r.voice), direction, duration_s, Time.get_ticks_msec() / 1000.0)
	callout_wheel = CalloutWheel.new(bindings)
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
	debug.set(&"steam", steam)
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
	router.at_job = (int(Variants.number(connection.status.get("flags", 0))) & StatusWire.AT_JOB) != 0
	router.struggling = (int(Variants.number(connection.status.get("flags", 0))) & StatusWire.STRUGGLE) != 0 \
		and DarkView.life_of(connection.view) == StatusWire.LIFE_GRABBED
	source.wheel_open = router.picking()
	var frame: Dictionary = source.frame(Time.get_ticks_msec() / 1000.0, bindings)
	if steam != null and steam.overlay_active:
		frame = InputRouter.neutral_frame(frame)
	var record: InputRecord = router.sample(frame)
	for action: Array in callout_wheel.filter(router.actions, Time.get_ticks_msec() / 1000.0):
		connection.inputs.queue_action(int(Variants.number(action[0])) as ActionRecord.Kind, int(Variants.number(action[1])), shown_tick,
			int(Variants.number(action[2])))
	for ask: int in closeups.process_input(router):
		connection.inputs.queue_action(ActionRecord.Kind.CLOSE_UP, ask, shown_tick, 0)
	router.coming_round = DarkView.in_window(connection.view)
	for ask: int in dark.asks(router, connection.view):
		connection.inputs.queue_action(ActionRecord.Kind.WATCH, ask, shown_tick, 0)
	return record


## The camera follows the own miner as last received (NET-05's predicted position once the client
## predicts), easing its lead; the squint or the aim (MNR-15's held bits) gives the 8-tile lead.
## Mouse facing is measured from the miner's position without the lead: the screen's centre.
func _follow_camera(delta: float) -> void:
	if camera == null or connection.view == null or connection.view.own.is_empty():
		return
	# RSC-04: in the Dark, the replay of the fall or a watched teammate's stream is drawn instead.
	dark.tick(connection, delta)
	var shown: ReceivedView = dark.override_view(connection.view)
	var drawing_other: bool = shown != null and not shown.own.is_empty()
	if not drawing_other:
		shown = connection.view
	world_view.set_view_mode(dark.mode(connection.view))
	DarkMix.apply(DarkView.life_of(connection.view) == DarkView.LIFE_UNCONSCIOUS and not drawing_other)
	if camera.state != LampCamera.State.CLOSE_UP:
		# VIS-01: coming round, the camera centres on the body with no lead.
		camera.state = LampCamera.State.COMING_ROUND if DarkView.in_window(connection.view) else LampCamera.State.MINE
	var own: Vector2 = shown.own["position"]
	var squint: bool = (router.record.holds & (InputRecord.HOLD_SQUINT | InputRecord.HOLD_AIM)) != 0
	var rate: float = Tuning.f(&"movement.turn_rate_deg_s") if Tuning.current.has_key(&"movement.turn_rate_deg_s") else 0.0
	if drawing_other:
		_shown_facing = int(Variants.number(shown.own.get("facing", 0)))
		squint = false
	else:
		_shown_facing = MinerMotion.turn_toward(_shown_facing, router.record.facing, MinerMotion.turn_step(rate, delta))
	camera.follow(own, _shown_facing, squint, delta)
	source.own_screen = get_viewport().get_visible_rect().size / 2.0
	# VIS-05: the drawn set and the darkness composite, from the live facing and the own lamp
	# (NET-05's predicted pool replaces the server's radius once the client predicts).
	var radius: float = float(Variants.number(shown.own.get("lamp_radius", 0.0)))
	var predicted: Dictionary = {"position": own, "facing": _shown_facing,
		"lamp": {"position": own, "radius": radius} if radius > 0.0 else {}}
	drawn.build(shown, predicted, connection.last_input_ack, _facing_seq)
	# VIS-06: the own lamp blended over the server's light (the same lamp both sides until NET-05's
	# predicted pool is wired here; then a wick step shows at once).
	var server_lamp: Dictionary = {"position": own, "radius": radius}
	var lights: Dictionary = OwnLampBlend.lights(drawn, shown, server_lamp, Variants.dict(predicted["lamp"]))
	var own_light: float = float(Variants.number(lights.get(Vector2i(floori(own.x), floori(own.y)), 0.0)))
	if connection.closeup_messages != _closeup_messages_seen:
		_closeup_messages_seen = connection.closeup_messages
		closeups.apply(connection.closeup)
	# UI-02: under a close-up that covers the screen nothing of the mine is drawn; nor at Lamp Check
	# (RSC-06), up on the surface.
	if closeups.covers_world() or lamp_check != null:
		if world_view.visible:
			world_view.set_shown(false)
		return
	if not world_view.visible:
		world_view.set_shown(true)
	world_view.own_hands = {} if drawing_other else connection.inventory
	world_view.own_lit = not drawing_other and radius > 0.0
	world_view.own_flame = 0 if drawing_other else int(Variants.number(shown.own.get("flame", 0)))
	world_view.show_frame(drawn, shown, camera.view_rect(own).position, own, _shown_facing, own_light,
		lights, Time.get_ticks_msec() / 1000.0)
	_show_in_play(own)
	_probe(predicted)


## LFT-14: once the sheet freezes and this copy matches it, the map card is drawn once and kept for
## RSC-06's Lamp Check, which offers saving it (save_map_card).
func _keep_map_card() -> void:
	if map_card != null or not connection.sheet.card_ready():
		return
	map_card = MapCard.render(connection.sheet, Tuning.i(&"mine.map_card_px"))
	Log.info("map card ready: %d strokes and labels" % connection.sheet.sheet.count())


## The player keeps the card: user://map_cards/<run_uuid>.png, and Steam's screenshot library
## (Proposed). Its path, or "".
func save_map_card() -> String:
	if map_card == null:
		return ""
	var path: String = MapCard.save(map_card, str(connection.sheet.frozen.get("run_uuid", "")))
	if not path.is_empty() and steam != null and steam.mode == SteamService.Mode.STEAM:
		MapCard.to_steam_library(steam.api, path, map_card)
	return path


## UI-01: the in-play elements; debug and test builds check that nothing else is drawn.
func _show_in_play(own: Vector2) -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	in_play.update({"view": connection.view, "view_origin": camera.view_rect(own).position,
		"black": world_view.mode == WorldView.Mode.BLACK, "inventory": connection.inventory, "feel": connection.feel,
		"router": router, "store": bindings, "wheel_anchor": source.wheel_anchor() if router.family == "kbm" else screen / 2.0,
		"status": connection.status, "server_tick": connection.last_frame_tick,
		"shown_tick": _shown_tick_f(),
		"short_side": minf(screen.x, screen.y), "now_s": Time.get_ticks_msec() / 1000.0})
	if config.build.is_release():
		return
	for v: String in in_play.check_frame([world_view.overlay_layer(), captions]):
		if not _ui_violations_seen.has(v):
			_ui_violations_seen[v] = true
			push_error("UI-01: unregistered in-play element %s" % v)


## The tick the client shows now, with its fraction (the struggle's needle turns smoothly on it).
func _shown_tick_f() -> float:
	var stamp: PackedInt64Array = connection.shown_stamp(Transport.now_usec())
	return float(stamp[0]) + stamp[1] / 256.0


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
	# RSC-04: watching, the ears sit on the watched miner and their game sound plays (never voice).
	var watched: ReceivedView = dark.watch_view if dark.watching else null
	if watched != null and not watched.own.is_empty():
		own = watched.own["position"]
	listener.follow(own, _shown_facing)
	while not dark.watch_events.is_empty():
		var wev: Dictionary = dark.watch_events.pop_front()
		var wrecord: AudioRecord = AudioRecord.from_event(wev)
		if not VisualEvents.is_visual(wrecord.type):
			events_player.play(wrecord, int(Variants.number(wev.get("number", 0))))
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
## STM-04: a host with Steam runs its own server when its crew opens, and stops it when it leaves.
func _on_lobby_state(state: LobbyService.State) -> void:
	if state == LobbyService.State.IN_LOBBY and lobby.is_host() and steam.available() and lobby.server_address.is_empty() and local_server == null:
		_start_hosting()
	elif state == LobbyService.State.IDLE and local_server != null:
		_stop_hosting()


func _start_hosting() -> void:
	local_server = LocalServerHost.new()
	add_child(local_server)
	local_server.server_ready.connect(_on_server_ready)
	local_server.ended.connect(_on_server_ended)
	local_server.start_refused.connect(func(reason: String) -> void:
		Log.warn("the run did not start: %s" % reason)
		lobby.failed.emit("lobby.start_refused"))
	local_server.knock_off_available.connect(func(on: bool) -> void: knock_off_available = on)
	local_server.knock_off_refused.connect(func(reason: String) -> void: Log.warn("knock off refused: %s" % reason))
	if not local_server.reattach():
		if not local_server.start(LocalServerHost.default_path(config.host_relay), resume_path):
			lobby.failed.emit("lobby.run_ended")
			return
	lobby.failed.emit("lobby.hosting")


func _on_server_ready(info: Dictionary) -> void:
	var vport: int = Variants.whole(info["vport"])
	var identity: int = Variants.whole(info["identity"])
	if local_server.path == LocalServerHost.Path.B:
		var sdr: SdrTransport = SdrTransport.new(steam.api)
		sdr.admission = func(id: int) -> bool:
			var l: Dictionary = lobby.admission_lists()
			var members: PackedInt64Array = l["ids"]
			var vouched_ids: PackedInt64Array = l["vouched"]
			var code_ids: PackedInt64Array = l["code_users"]
			var vouched: Dictionary = {}
			for v: int in vouched_ids:
				vouched[v] = true
			var codes: Dictionary = {}
			for c: int in code_ids:
				codes[c] = true
			return LobbyAdmission.judge(id, Variants.whole(l["owner"]), members, codes, vouched, PackedInt64Array(), 1 << 30) == LobbyAdmission.Verdict.SEAT
		host_relay = HostRelay.new(sdr, Variants.whole(info["game"]), str(info["token"]))
		if host_relay.listen(vport) != OK:
			Log.error("host relay: no SDR listen socket")
		identity = steam.steam_id
	lobby.publish_server(identity, vport)
	_send_members()
	if connection == null:
		_connect("127.0.0.1:%d" % Variants.whole(info["game"]))


func _send_members() -> void:
	if local_server == null or not lobby.is_host():
		return
	var l: Dictionary = lobby.admission_lists()
	var ids: PackedInt64Array = l["ids"]
	var code_users: PackedInt64Array = l["code_users"]
	var vouched: PackedInt64Array = l["vouched"]
	local_server.send_members(Variants.whole(l["owner"]), ids, code_users, vouched)


func _on_server_ended(_code: int, crashed: bool) -> void:
	if host_relay != null:
		host_relay.close()
		host_relay = null
	if crashed:
		lobby.failed.emit("lobby.run_ended")
	local_server.queue_free()
	local_server = null


func _stop_hosting() -> void:
	if local_server != null:
		local_server.stop()


## STM-04 (M2): a friend reaches the host's server over SDR (lb_server).
func _connect_sdr(identity: int, vport: int) -> void:
	if connection != null:
		return
	connection = ClientConnection.new(SdrTransport.new(steam.api))
	connection.identity = str(steam.steam_id)
	connection.qa_token = config.qa_token
	_offer_miners(connection)
	if connection.start(str(identity), vport):
		Log.info("connecting over SDR to %d (virtual port %d)" % [identity, vport])
	else:
		Log.error("could not start an SDR connection to %d" % identity)


func _connect(target: String) -> void:
	var host: String = target.substr(0, target.rfind(":"))
	var port: int = target.substr(target.rfind(":") + 1).to_int()
	connection = ClientConnection.new(EnetTransport.new())
	# With Steam, the identity is the SteamID (the server checks it where the transport knows it).
	connection.identity = str(steam.steam_id) if steam.available() else steam.persona_name()
	connection.qa_token = config.qa_token
	connection.seat_request = Protocol.Seat.BOT if not config.bot_script.is_empty() else Protocol.Seat.PLAYER
	_offer_miners(connection)
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
			Log.info("welcomed: slot %d, server tick %d, %d Hz%s" % [connection.welcome.slot,
				connection.welcome.server_tick, connection.welcome.tick_hz,
				", seated as roster miner %d with badge %d" % [connection.welcome.seated_miner, connection.welcome.badge]
				if connection.welcome.seated_miner >= 0 else ""])
			if mic_mode != null:
				_send_mic_label(mic_mode.show_mute_label())
		ClientConnection.State.REJECTED:
			Log.warn("refused by the server: %s" % RejectText.text(connection.reject_reason))
			if connection.reject_reason == Protocol.Reject.KNOCKED_OFF:
				# MOD-05: the run is saved, unfinished: the miner stays Below for it until it resumes.
				_seated_run = ""
			else:
				_end_seated_run()
			_lobby_again()
		ClientConnection.State.DROPPED:
			Log.warn("connection lost: %s" % connection.drop_reason)
			_end_seated_run()
			_lobby_again()


## No connection under way: none yet, or the last one refused or lost (a new one rejoins, NET-11).
func _may_connect() -> bool:
	return connection == null or connection.state == ClientConnection.State.REJECTED \
		or connection.state == ClientConnection.State.DROPPED


## MOD-01's profile on this PC for this player (STM-01's SteamID, or the dev persona's).
func _load_profile() -> void:
	profile_store = ProfileStore.new()
	profile = profile_store.load_or_create(steam.steam_id)
	var st: Profile.State = profile.state()
	Log.info("profile: %d on the roster, %d Available, New Brigade runs %d" % [st.roster.size(),
		st.roster.filter(func(m: RosterMiner) -> bool: return m.available()).size(), st.new_brigade_runs])


## MOD-03: the hello offers up to three Available roster miners (UI-04's choice first; until then the
## roster's order), the preferred badge and the New Brigade runs. With every miner Below in an
## unfinished run, the player joins with none.
func _offer_miners(c: ClientConnection) -> void:
	if profile == null:
		return
	var st: Profile.State = profile.state()
	var offered: Array[Dictionary] = []
	for m: RosterMiner in st.roster:
		if m.available() and offered.size() < Protocol.MAX_CANDIDATES:
			offered.append({"id": m.id, "name": m.full_name(), "lamp_number": m.lamp_number, "voice_id": m.voice_id,
				"book_pages": m.book_pages.duplicate()})
	if offered.is_empty():
		Log.warn("profile: every miner is Below in an unfinished run; joining without a roster miner")
	c.candidates = offered
	c.preferred_badge = profile.preferred_badge
	c.new_brigade_runs = st.new_brigade_runs


## MOD-03: the run's first frame: the lobby gives way, and the seated miner goes Below for this run.
func _on_run_begun() -> void:
	if connection.state != ClientConnection.State.CONNECTED or connection.frames_received == 0:
		return
	if _menus().get_node_or_null("DevLobby") != null:
		_hide_dev_lobby()
	var w: Protocol.Welcome = connection.welcome
	if not _seated_run.is_empty() or profile == null or w.seated_miner < 0 or w.run_uuid.is_empty():
		return
	_seated_run = w.run_uuid
	if profile.send_below(w.run_uuid, w.seated_miner, int(Time.get_unix_time_from_system())):
		if profile_store != null:
			profile_store.save(profile)
		Log.info("profile: miner %d is Below in this run" % w.seated_miner)


## RSC-06: the connection went before Lamp Check: the run ends abnormally on the roster (voided in
## public, which gives the miner back; else Below until it resumes and ends).
func _end_seated_run() -> void:
	if _seated_run.is_empty() or profile == null:
		return
	var public: bool = RunOptions.mode_from(str(lobby.options.get("mode", "friends")) if lobby != null else "friends") == ServerConfig.Mode.PUBLIC
	profile.end_without_lamp_check(_seated_run, OutcomeEvent.End.VOIDED if public else OutcomeEvent.End.ABNORMAL,
		int(Time.get_unix_time_from_system()))
	if profile_store != null:
		profile_store.save(profile)
	Log.info("profile: the run ended without Lamp Check (%s)" % ("voided" if public else "unfinished"))
	_seated_run = ""


## MOD-05: the host's "Knock off" (UI-05's settings overlay calls it while knock_off_available).
func knock_off() -> void:
	if local_server != null and knock_off_available:
		local_server.send_knock_off()


## MOD-03: Go down: the host's own server creates the run from the lobby's options and the crew seated.
func _on_go_down() -> void:
	if local_server == null:
		return
	local_server.send_start(lobby.options, profile != null and profile.state().unlocked_variants)
	lobby.failed.emit("lobby.going_down")


## In play the lobby gives way to the mine (it would cover it and take the mouse).
func _hide_dev_lobby() -> void:
	var screen: Node = _menus().get_node_or_null("DevLobby")
	if screen != null:
		screen.queue_free()
		Log.info("dev lobby hidden: in play")


## Refused or lost: back to the lobby (once the first-launch screens are done), to connect again.
func _lobby_again() -> void:
	if _first_launch_done and _menus().get_node_or_null("DevLobby") == null:
		_show_dev_lobby()


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
	_menus().add_child(play)
	Log.info("pithead shown")


func _start_first_launch() -> void:
	var flow: FirstLaunch = FirstLaunch.new(mic_mode)
	flow.name = "FirstLaunch"
	flow.finished.connect(func() -> void:
		flow.queue_free()
		Log.info("microphone: %s under notice %d" % [MicMode.MODE_NAMES[mic_mode.mode], mic_mode.notice_version])
		_first_launch_done = true
		_show_dev_lobby())
	_menus().add_child(flow)


## STM-02's dev lobby (UI-04's Pithead replaces it). Without a lobby service (a bare test), a label.
func _show_dev_lobby() -> void:
	if connection != null and connection.state == ClientConnection.State.CONNECTED:
		Log.info("dev lobby skipped: already in play")
		return
	if lobby == null:
		var label: Label = Label.new()
		label.name = "DevLobby"
		label.text = "LAMPBLACK\ndev lobby"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_menus().add_child(label)
		Log.info("dev lobby shown")
		return
	var screen: DevLobby = DevLobby.new(lobby, steam, not config.build.is_release(), lobby.server_address)
	screen.direct_connect.connect(func(address: String) -> void:
		if _may_connect() and not address.is_empty():
			_connect(address))
	_menus().add_child(screen)
	Log.info("dev lobby shown: %s" % screen.who.text.replace("\n", " | "))


## RSC-06: Lamp Check opens on the server's word: the screen over the mine, the mine's beds stopped,
## held inputs let go, and the player's own outcome put on their roster. Its end closes the run.
func _keep_lamp_check() -> void:
	if connection.lamp_check_messages != _lamp_check_seen:
		_lamp_check_seen = connection.lamp_check_messages
		if not connection.lamp_check_end.is_empty():
			_end_lamp_check()
			return
		if lamp_check == null and not connection.lamp_check.is_empty():
			_open_lamp_check(connection.lamp_check)
	if lamp_check != null:
		lamp_check.step(Time.get_ticks_msec() / 1000.0)


func _open_lamp_check(opening: Dictionary) -> void:
	_lamp_check_layer = CanvasLayer.new()
	_lamp_check_layer.name = "LampCheckScreen"
	_lamp_check_layer.layer = LAMP_CHECK_LAYER
	add_child(_lamp_check_layer)
	lamp_check = LampCheckView.new()
	if captions != null:
		lamp_check.subtitle = captions.system.subtitle
	lamp_check.map_card = func() -> Image: return map_card
	lamp_check.ready_pressed.connect(func() -> void:
		if connection != null:
			connection.send_lamp_check_ready())
	lamp_check.card_saved.connect(func(path: String, image: Image) -> void:
		if steam != null and steam.mode == SteamService.Mode.STEAM:
			LampCheckCardImage.to_steam_library(steam.api, path, image))
	_lamp_check_layer.add_child(lamp_check)
	lamp_check.open(opening, Time.get_ticks_msec() / 1000.0)
	if beds != null:
		beds.stop_all()
	if in_play != null:
		in_play.visible = false
	if router != null:
		router.release_all()
	_apply_outcome(opening)
	Log.info("lamp check: open (%d hooks, %s)" % [Variants.array(opening.get("hooks", [])).size(),
		"in public, %.0f s" % Variants.number(opening.get("public_s", 0.0)) if not lamp_check.is_friends() else "until everyone is ready"])


## MOD-01: the own outcome onto the seated profile's roster, saved; without a seated profile it
## goes nowhere (MOD-03 seats one).
func _apply_outcome(opening: Dictionary) -> void:
	_seated_run = ""
	# MOD-05: the run is over: its saves are never offered for a resume again.
	if connection != null:
		connection.saves.mark_ended(str(opening.get("run_uuid", "")))
	if profile == null:
		Log.info("lamp check: no profile seated, so no roster takes the outcome")
		return
	var at: int = int(Time.get_unix_time_from_system())
	if LampCheckRoster.apply(profile, str(opening.get("run_uuid", "")), str(opening.get("own", "")), Variants.flag(opening.get("wipe", false)), at):
		if profile_store != null:
			profile_store.save(profile)
		Log.info("lamp check: the roster took the outcome (%s)" % str(opening.get("own", "")))


## The end: the screen goes, and once this frame is done the run's connection closes and the lobby
## returns (the server goes too).
func _end_lamp_check() -> void:
	if _lamp_check_layer != null:
		_lamp_check_layer.queue_free()
	_lamp_check_layer = null
	lamp_check = null
	Log.info("lamp check: over")
	_leave_run.call_deferred()


func _leave_run() -> void:
	if connection != null:
		connection.close()
	connection = null
	_lamp_check_seen = 0
	# LFT-14's card belonged to that run.
	map_card = null
	if in_play != null:
		in_play.visible = true
	_lobby_again()
