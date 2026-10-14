class_name SteamService
extends Node
## STM-01's Steam service (GDD §15.1): the restart-through-Steam check, initialisation and the
## callback pump, ordered shutdown, identity and persona names, overlay state, Steam's game language
## and hardware. Every later Steam ticket builds on it, through SteamApi (the only file that calls
## GodotSteam). ClientMain owns it as a child, not an autoload: server exports carry no client code
## and never touch the client API.
##
## Dev and QA builds fall back to dev mode when Steam is absent or --no-steam is given: a stable fake
## identity, every Steam service unavailable, and no GodotSteam call after the failed init. Release
## builds never run without Steam: they relaunch through Steam or show the failure screen (exit 4).

enum Mode { OFF, STEAM, DEV, FAILED }
## What boot() tells ClientMain to do.
enum Boot { CONTINUE, QUIT_RELAUNCHING, FAIL }

const SETTING_APP_ID: String = "lampblack/steam/app_id"
## SteamID64's individual-account base: a fake ID is this plus a 32-bit account number.
const STEAM_ID_BASE: int = 76561197960265728

## A persona name changed (the own or a friend's): names on screen refresh.
signal persona_changed(steam_id: int)
## The overlay opened or closed. ClientMain lets every gameplay input go while it is open.
signal overlay_toggled(active: bool)

var api: SteamApi = null
var mode: Mode = Mode.OFF
var init_status: int = -1
var steam_id: int = 0
## True in dev mode: the identity is made up from --name, never a Steam account.
var fake_identity: bool = false
var overlay_active: bool = false
## UI-05's streamer mode: display_name() then gives lamp numbers, never a Steam name.
var streamer_mode: bool = false
## Each known miner's lamp number by SteamID (the lobby sets them, STM-02).
var lamp_numbers: Dictionary = {}
var _persona: String = ""
var _hooks: Array[Array] = []
var _shut_down: bool = false


func _init(steam_api: SteamApi = null) -> void:
	api = steam_api if steam_api != null else SteamApi.new()
	name = "SteamService"
	# Callbacks keep flowing through loading, close-ups and Night Shift's pause.
	process_mode = Node.PROCESS_MODE_ALWAYS


## The app ID for this build: lampblack/steam/app_id with its feature-tag overrides (.lb_release,
## and later .lb_playtest, .lb_demo).
static func app_id() -> int:
	return int(Variants.number(ProjectSettings.get_setting_with_override(SETTING_APP_ID)))


## What an init status means for this build (the ticket's table).
static func outcome_for(status: int, release: bool) -> Boot:
	if status == SteamApi.Init.OK:
		return Boot.CONTINUE
	return Boot.FAIL if release else Boot.CONTINUE


## A stable SteamID-shaped value from the dev persona name (FND-06's hash), flagged as fake.
static func fake_steam_id(persona: String) -> int:
	var keys: PackedInt64Array = PackedInt64Array()
	for b: int in persona.to_utf8_buffer():
		keys.append(b)
	return STEAM_ID_BASE + (LbHash.hash(0, HashDomain.STEAM_FAKE_ID, keys) & 0xFFFFFFFF)


## Brings Steam up. `release`: the build's flavour; `no_steam`: --no-steam (ignored by release
## builds' argument parser); `persona`: --name for dev mode.
func boot(release: bool, no_steam: bool, persona: String) -> Boot:
	if no_steam and not release:
		_enter_dev(persona, "--no-steam")
		return Boot.CONTINUE
	var id: int = app_id()
	if release and api.restart_app_if_necessary(id):
		Log.info("steam: relaunching through Steam")
		mode = Mode.OFF
		return Boot.QUIT_RELAUNCHING
	var r: Dictionary = api.init(id)
	init_status = int(Variants.number(r["status"]))
	if init_status != SteamApi.Init.OK:
		var why: String = "init status %d (%s)" % [init_status, str(r["verbal"])]
		if outcome_for(init_status, release) == Boot.FAIL:
			Log.error("steam: %s; this build needs Steam" % why)
			mode = Mode.FAILED
			return Boot.FAIL
		_enter_dev(persona, why)
		return Boot.CONTINUE
	mode = Mode.STEAM
	steam_id = api.steam_id()
	_persona = api.persona_name()
	api.overlay_toggled.connect(_on_overlay_toggled)
	api.persona_changed.connect(_on_persona_changed)
	Log.info("steam: app %d, user %d, language %s, hardware %s, overlay %s" % [id, steam_id, api.game_language(),
		SteamApi.Hardware.keys()[api.hardware()], "on" if api.overlay_enabled() else "off"])
	return Boot.CONTINUE


func _enter_dev(persona: String, why: String) -> void:
	mode = Mode.DEV
	fake_identity = true
	_persona = persona if not persona.is_empty() else "dev"
	steam_id = fake_steam_id(_persona)
	Log.info("steam: dev mode (%s); fake identity %d" % [why, steam_id])


## Whether Steam itself is up (false in dev mode: every Steam service reports unavailable).
func available() -> bool:
	return mode == Mode.STEAM


func _process(_delta: float) -> void:
	if mode == Mode.STEAM:
		api.run_callbacks()


## The own persona name (dev mode: the --name persona).
func persona_name() -> String:
	return _persona


## Every Steam name the game shows comes from here (GDD §14.3): the persona, or the miner's lamp
## number while streamer mode is on.
func display_name(of_steam_id: int) -> String:
	if streamer_mode:
		if lamp_numbers.has(of_steam_id):
			return UiText.text("steam.lamp_number") % int(Variants.number(lamp_numbers[of_steam_id]))
		return UiText.text("steam.lamp_unknown")
	if of_steam_id == steam_id:
		return _persona
	return api.friend_persona_name(of_steam_id) if mode == Mode.STEAM else ""


## With the overlay disabled, STM-02 offers invite codes in place of the invite dialog.
func overlay_enabled() -> bool:
	return mode == Mode.STEAM and api.overlay_enabled()


## Steam's current game language, seeding UI-07's default ("" without Steam).
func language() -> String:
	return api.game_language() if mode == Mode.STEAM else ""


## For STM-07's defaults.
func steam_hardware() -> SteamApi.Hardware:
	return api.hardware() if mode == Mode.STEAM else SteamApi.Hardware.NONE


## Registers a shutdown step. They run in `order` before Steam shuts down: 10 STM-02 leaves the
## lobby, 20 STM-03 closes connections, 30 STM-04 stops the local server, 40 STM-05 ends its Cloud
## write batch.
func add_shutdown_hook(order: int, label: String, hook: Callable) -> void:
	_hooks.append([order, label, hook])
	_hooks.sort_custom(func(a: Array, b: Array) -> bool: return int(Variants.number(a[0])) < int(Variants.number(b[0])))


## Runs the hooks in order, then shuts Steam down. Once only; on window close and on leaving the tree.
func shutdown() -> void:
	if _shut_down:
		return
	_shut_down = true
	for h: Array in _hooks:
		var hook: Callable = h[2]
		if hook.is_valid():
			hook.call()
	if mode == Mode.STEAM:
		api.overlay_toggled.disconnect(_on_overlay_toggled)
		api.persona_changed.disconnect(_on_persona_changed)
		api.shutdown()
		Log.info("steam: shut down")
	mode = Mode.OFF


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()


func _exit_tree() -> void:
	shutdown()


func _on_overlay_toggled(active: bool) -> void:
	overlay_active = active
	overlay_toggled.emit(active)


func _on_persona_changed(of_steam_id: int) -> void:
	if of_steam_id == steam_id:
		_persona = api.persona_name()
	persona_changed.emit(of_steam_id)
