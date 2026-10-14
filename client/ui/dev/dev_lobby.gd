class_name DevLobby
extends Control
## STM-02's minimal M1 lobby screen (UI-04's Pithead replaces it): who you are; open a crew, or join
## one by code; in a crew, its code (masked in streamer mode, with a copy button), the overlay invite,
## the crew with ready marks, Ready, Go down (host) and Leave; in dev and QA builds, a server address
## and direct connect. Every control is reachable by focus, so a controller alone works it
## (MenuInput maps the pad).

signal direct_connect(address: String)

var lobby: LobbyService = null
var steam: SteamService = null
var dev: bool = false
var who: Label = Label.new()
var status: Label = Label.new()
var crew_list: Label = Label.new()
var code_label: Label = Label.new()
var create_button: Button = Button.new()
var code_entry: LineEdit = LineEdit.new()
var join_button: Button = Button.new()
var server_entry: LineEdit = LineEdit.new()
var direct_button: Button = Button.new()
var copy_button: Button = Button.new()
var invite_button: Button = Button.new()
var ready_button: Button = Button.new()
var start_button: Button = Button.new()
var leave_button: Button = Button.new()
var _idle_box: VBoxContainer = VBoxContainer.new()
var _crew_box: VBoxContainer = VBoxContainer.new()


func _init(lobby_service: LobbyService, steam_service: SteamService, dev_build: bool, server_address: String) -> void:
	name = "DevLobby"
	lobby = lobby_service
	steam = steam_service
	dev = dev_build
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(720, 0)
	box.position = Vector2(-360, -320)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	var title: Label = Label.new()
	title.text = UiText.text("lobby.title")
	box.add_child(title)
	box.add_child(who)
	box.add_child(status)
	for l: Label in [title, who, status, crew_list, code_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 26)
	box.add_child(_idle_box)
	box.add_child(_crew_box)
	_button(create_button, "lobby.create", _idle_box, func() -> void: lobby.create())
	code_entry.placeholder_text = UiText.text("lobby.code_hint")
	code_entry.max_length = 12
	code_entry.text_submitted.connect(func(t: String) -> void: lobby.join_code(t))
	_idle_box.add_child(code_entry)
	_button(join_button, "lobby.join", _idle_box, func() -> void: lobby.join_code(code_entry.text))
	server_entry.placeholder_text = UiText.text("lobby.server_hint")
	server_entry.text = server_address
	server_entry.text_changed.connect(func(t: String) -> void: lobby.server_address = t)
	_idle_box.add_child(server_entry)
	_button(direct_button, "lobby.direct", _idle_box, func() -> void: direct_connect.emit(server_entry.text))
	server_entry.visible = dev
	direct_button.visible = dev
	_crew_box.add_child(code_label)
	_button(copy_button, "lobby.copy", _crew_box, func() -> void: DisplayServer.clipboard_set(lobby.code))
	_button(invite_button, "lobby.invite", _crew_box, func() -> void:
		if not lobby.invite():
			status.text = UiText.text("lobby.invite_none"))
	_crew_box.add_child(crew_list)
	_button(ready_button, "lobby.ready", _crew_box, func() -> void: lobby.set_ready(not lobby.is_ready))
	_button(start_button, "lobby.start", _crew_box, func() -> void: lobby.start())
	_button(leave_button, "lobby.leave", _crew_box, func() -> void: lobby.leave())
	lobby.state_changed.connect(func(_s: LobbyService.State) -> void: refresh())
	lobby.lobby_changed.connect(refresh)
	lobby.failed.connect(func(key: String) -> void: status.text = UiText.text(key))
	if steam != null:
		steam.persona_changed.connect(func(_id: int) -> void: refresh())


func _button(b: Button, key: String, parent: Control, action: Callable) -> void:
	b.text = UiText.text(key)
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(action)
	parent.add_child(b)


func _ready() -> void:
	refresh()
	create_button.grab_focus()


func refresh() -> void:
	if steam != null:
		who.text = "%s\n%d%s\n%s" % [steam.display_name(steam.steam_id), steam.steam_id,
			(" " + UiText.text("lobby.dev_identity")) if steam.fake_identity else "", steam.relay_text()]
	var in_lobby: bool = lobby.state == LobbyService.State.IN_LOBBY
	var busy: bool = lobby.state != LobbyService.State.IDLE and not in_lobby
	_idle_box.visible = not in_lobby
	_crew_box.visible = in_lobby
	create_button.disabled = busy
	join_button.disabled = busy
	code_entry.editable = not busy
	if busy:
		status.text = UiText.text("lobby.working")
	if in_lobby:
		if status.text == UiText.text("lobby.working"):
			status.text = ""
		code_label.text = UiText.text("lobby.code") % lobby.shown_code()
		ready_button.text = UiText.text("lobby.not_ready" if lobby.is_ready else "lobby.ready")
		start_button.visible = lobby.is_host()
		var lines: PackedStringArray = PackedStringArray()
		for m: Dictionary in lobby.crew():
			lines.append("%s%s%s" % [str(m["name"]), "  (%s)" % UiText.text("lobby.host") if Variants.flag(m["host"]) else "",
				"  ✓" if Variants.flag(m["ready"]) else ""])
		crew_list.text = "\n".join(lines)
		if not _has_focus_in(_crew_box) and is_inside_tree():
			ready_button.grab_focus.call_deferred()
	elif not _has_focus_in(_idle_box) and is_inside_tree():
		create_button.grab_focus.call_deferred()


func _has_focus_in(c: Control) -> bool:
	if not is_inside_tree():
		return false
	var f: Control = get_viewport().gui_get_focus_owner()
	return f != null and c.is_ancestor_of(f)
