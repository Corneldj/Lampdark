class_name LobbyService
extends Node
## STM-02's friends lobbies (GDD §13.8): a host opens a lobby of 1-5 (modes.friends_lobby_max), writes
## its data and an invite code; friends join by overlay invite, the friends list ("Join Game"),
## +connect_lobby at launch, or the code. A lobby of another build is refused ("Different version").
## In M1 every member connects over NET-02's dev transport to lb_dev_addr; from M2 STM-03 and STM-04
## take over (lb_server). The backend is Steam's, or FakeLobbyBackend's dev rendezvous.

enum State { IDLE, CREATING, SEARCHING, JOINING, IN_LOBBY }
enum SearchFor { NONE, CODE_CHECK, CODE_LOOKUP }

## How many fresh codes a host draws before giving up on one no live lobby holds.
const CODE_TRIES: int = 8

signal state_changed(state: State)
## Members or lobby data changed: the screen redraws.
signal lobby_changed
## Something failed; `text_key` is for UiText ("lobby.no_crew", "lobby.different_version", ...).
signal failed(text_key: String)
## M1: connect to the dev-transport server at host:port.
signal connect_requested(address: String)
## STM-04 (M2): connect over SDR to the host's server (lb_server: "<SteamID>:<virtual port>").
signal connect_sdr_requested(identity: int, vport: int)

var backend: LobbyBackend = null
var steam: SteamService = null
var release: bool = false
## What a host writes as lb_dev_addr (dev, QA and kill-test builds; never release).
var server_address: String = ""
var options: Dictionary = {}
var state: State = State.IDLE
var code: String = ""
var is_ready: bool = false
## Where fresh codes come from (tests script clashes).
var next_code: Callable = InviteCode.generate
var _search: SearchFor = SearchFor.NONE
var _lookup: Dictionary = {}
var _lookup_retried: bool = false
var _tries: int = 0
var _connected_to: String = ""
var _via_code: bool = false


func _init(lobby_backend: LobbyBackend, steam_service: SteamService, release_build: bool) -> void:
	name = "LobbyService"
	backend = lobby_backend
	steam = steam_service
	release = release_build
	process_mode = Node.PROCESS_MODE_ALWAYS
	backend.created.connect(_on_created)
	backend.entered.connect(_on_entered)
	backend.changed.connect(func(_id: int) -> void: _on_changed())
	backend.search_done.connect(_on_search_done)
	backend.join_requested.connect(func(id: int) -> void:
		Log.info("lobby: join requested (invite or friends list)")
		join(id))
	if steam != null:
		steam.add_shutdown_hook(10, "leave the lobby", leave)


func _process(_delta: float) -> void:
	backend.poll()


static func limit() -> int:
	return Tuning.i(&"modes.friends_lobby_max")


func is_host() -> bool:
	return state == State.IN_LOBBY and backend.owner() == backend.self_id()


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


func _fail(text_key: String) -> void:
	Log.info("lobby: %s" % text_key)
	_search = SearchFor.NONE
	_set_state(State.IDLE)
	failed.emit(text_key)


## Host: open a lobby, draw a code no live lobby holds, write every key.
func create() -> void:
	if state != State.IDLE:
		return
	_set_state(State.CREATING)
	backend.create(limit())


func _on_created(ok: bool, _id: int) -> void:
	if state != State.CREATING:
		return
	if not ok:
		_fail("lobby.create_failed")
		return
	_tries = 0
	_draw_code()


func _draw_code() -> void:
	_tries += 1
	code = str(next_code.call())
	_search = SearchFor.CODE_CHECK
	backend.search(LobbyMetadata.code_filters(code))


func _publish() -> void:
	backend.set_limit(limit())
	var d: Dictionary = LobbyMetadata.lobby_data(options, LobbyMetadata.PITHEAD, code, server_address, release)
	for key: Variant in d.keys():
		backend.set_data(str(key), str(d[key]))
	backend.set_joinable(true)
	_write_member()
	_set_state(State.IN_LOBBY)
	Log.info("lobby: open (%d members max)" % limit())
	_on_changed()


## Join by a typed code: any case, O for 0, I or L for 1.
func join_code(typed: String) -> void:
	if state != State.IDLE:
		return
	var c: String = InviteCode.normalise(typed)
	if c.is_empty():
		failed.emit("lobby.no_crew")
		return
	_set_state(State.SEARCHING)
	_search = SearchFor.CODE_LOOKUP
	_via_code = true
	_lookup = LobbyMetadata.code_filters(c)
	_lookup_retried = false
	backend.search(_lookup)


func _on_search_done(ids: PackedInt64Array) -> void:
	var purpose: SearchFor = _search
	_search = SearchFor.NONE
	match purpose:
		SearchFor.CODE_CHECK:
			var others: PackedInt64Array = ids.duplicate()
			var own: int = others.find(backend.lobby_id)
			if own >= 0:
				others.remove_at(own)
			if not others.is_empty() and _tries < CODE_TRIES:
				_draw_code()
			else:
				_publish()
		SearchFor.CODE_LOOKUP:
			if ids.is_empty() and not _lookup_retried:
				# Steam indexes a new lobby's data a moment after it is written: look once more.
				_lookup_retried = true
				_search = SearchFor.CODE_LOOKUP
				get_tree().create_timer(Tuning.f(&"net.invite_code_retry_s")).timeout.connect(func() -> void:
					if state == State.SEARCHING:
						backend.search(_lookup))
			elif ids.is_empty():
				_fail("lobby.no_crew")
			else:
				_set_state(State.IDLE)
				join(ids[0])


## Join a lobby by ID (an invite, the friends list, +connect_lobby, a code's lookup).
func join(id: int) -> void:
	if id == 0:
		return
	if state == State.IN_LOBBY:
		if backend.lobby_id == id:
			return
		leave()
	if state != State.IDLE:
		return
	_set_state(State.JOINING)
	backend.join(id)


func _on_entered(_id: int, response: int) -> void:
	if state != State.JOINING:
		return  # a host's own entry: _on_created carries on
	if response != LobbyBackendEnter.SUCCESS:
		_fail("lobby.full" if response == LobbyBackendEnter.FULL else "lobby.gone")
		return
	if not LobbyMetadata.compatible(backend.all_data()):
		backend.leave()
		_fail("lobby.different_version")
		return
	code = backend.data("lb_code")
	_write_member()
	_set_state(State.IN_LOBBY)
	Log.info("lobby: joined")
	_on_changed()


func _write_member() -> void:
	var d: Dictionary = LobbyMetadata.member_data(is_ready, steam.persona_name() if steam != null else "", 0, 0, false)
	for key: Variant in d.keys():
		backend.set_member_data(str(key), str(d[key]))
	# STM-02's admission: how this member came in (a code, or an invite or friends-list join).
	backend.set_member_data("lb_via", "code" if _via_code else "invite")


func set_ready(on: bool) -> void:
	is_ready = on
	if state == State.IN_LOBBY:
		backend.set_member_data("lb_ready", "1" if on else "0")


## Host: the crew goes down (M1: the state only; MOD-03 starts the run).
func start() -> void:
	if is_host():
		backend.set_data("lb_state", LobbyMetadata.RUNNING)


func leave() -> void:
	if state == State.IN_LOBBY or state == State.JOINING:
		backend.leave()
		Log.info("lobby: left")
	code = ""
	is_ready = false
	_via_code = false
	_connected_to = ""
	_search = SearchFor.NONE
	if state != State.IDLE:
		_set_state(State.IDLE)


func invite() -> bool:
	return state == State.IN_LOBBY and backend.invite_dialog()


func _on_changed() -> void:
	if state != State.IN_LOBBY:
		return
	if steam != null:
		var numbers: Dictionary = {}
		var ids: PackedInt64Array = backend.members()
		for i: int in ids.size():
			numbers[ids[i]] = i + 1  # lamp numbers by joining order until UI-04 assigns them
		steam.lamp_numbers = numbers
	var address: String = backend.data("lb_dev_addr")
	if not release and not address.is_empty() and address != _connected_to:
		_connected_to = address
		connect_requested.emit(address)
	var server: String = backend.data("lb_server")
	if not server.is_empty() and server != _connected_to and not is_host():
		var parts: PackedStringArray = server.split(":")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			_connected_to = server
			connect_sdr_requested.emit(parts[0].to_int(), parts[1].to_int())
	lobby_changed.emit()


## STM-04: the host publishes its server's SDR identity and virtual port.
func publish_server(identity: int, vport: int) -> void:
	if is_host():
		backend.set_data("lb_server", "%d:%d" % [identity, vport])


## STM-04: the admission lists the host hands its server: {owner, ids, code_users, vouched}.
## Vouched: the members who are the host's Steam friends (invites and friends-list joins).
func admission_lists() -> Dictionary:
	var ids: PackedInt64Array = backend.members()
	var code_users: PackedInt64Array = PackedInt64Array()
	var vouched: PackedInt64Array = PackedInt64Array()
	for id: int in ids:
		if backend.member_data(id, "lb_via") == "code":
			code_users.append(id)
		if backend.is_friend(id):
			vouched.append(id)
	return {"owner": backend.owner(), "ids": ids, "code_users": code_users, "vouched": vouched}


## The crew as the screen shows it: [{id, name, ready, host}]. Names go through STM-01's
## display_name, so streamer mode shows lamp numbers.
func crew() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var host: int = backend.owner()
	for id: int in backend.members():
		var shown: String = ""
		if steam != null and (steam.streamer_mode or steam.available()):
			shown = steam.display_name(id)
		if shown.is_empty():
			shown = backend.member_name(id)
		out.append({"id": id, "name": shown, "ready": backend.member_data(id, "lb_ready") == "1", "host": id == host})
	return out


## The code as the screen may show it: masked in streamer mode (GDD §14.3).
func shown_code() -> String:
	return InviteCode.masked(code) if steam != null and steam.streamer_mode else code
