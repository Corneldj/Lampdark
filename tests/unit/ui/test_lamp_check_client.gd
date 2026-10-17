extends GutTest
## RSC-06 on the client: Lamp Check's opening shows its screen over the mine, on a layer under the
## captions so the lampman's subtitles stay over it; the seated profile's miner takes the outcome
## (MOD-01) and the profile is saved; without a seated profile the screen still opens; Ready goes to
## the server on the control lane; the end closes the run's connection and brings the lobby back.

const HOOKS: Array = [{"lamp": 108, "hangs": true}, {"lamp": 114, "hangs": false}]
const CARD: String = "Morrow Main, first shift. Up 1 of 2. Left Below: Ada Rowe, Lamp 114. Deepest: the Third Level. Below 1 h 42 min."

var _dir: String = ""


func before_all() -> void:
	assert_true(Tuning.load_client())


func before_each() -> void:
	_dir = "user://test_lamp_check_client_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _mode() -> MicMode:
	var v: String = _dir.path_join("version.json")
	var f: FileAccess = FileAccess.open(v, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1}))
	f.close()
	return MicMode.new(_dir.path_join("log.jsonl"), _dir.path_join("queue.jsonl"), v)


func _client() -> Array:
	var script: GDScript = load("res://client/client_main.gd")
	var cm: Node = script.new()
	cm.set("mic_mode", _mode())
	add_child_autofree(cm)
	cm.set("_first_launch_done", true)
	var c: ClientConnection = ClientConnection.new(InProcessTransport.new(InProcessTransport.Hub.new()))
	c.welcome = Protocol.Welcome.new()
	c.state = ClientConnection.State.CONNECTED
	cm.set("connection", c)
	cm.call("_report_connection")
	return [cm, c]


func _open(c: ClientConnection, own: String, run_uuid: String) -> void:
	c.lamp_check = LampCheckWire.read(LampCheckWire.open(HOOKS, "drag", CARD, false, own, run_uuid, {}))
	c.lamp_check_messages += 1


func test_it_opens_over_the_mine_and_ends_in_the_lobby() -> void:
	var w: Array = _client()
	var cm: Node = w[0]
	var c: ClientConnection = w[1]
	var store: ProfileStore = ProfileStore.new()
	store.dir = _dir
	var p: Profile = Profile.create(7, 11)
	var sent: RosterMiner = p.state().roster[0]
	assert_true(p.send_below("run-x", sent.id, 1))
	cm.set("profile", p)
	cm.set("profile_store", store)
	_open(c, "escaped", "run-x")
	cm.call("_keep_lamp_check")
	var layer: CanvasLayer = cm.find_child("LampCheckScreen", true, false)
	assert_not_null(layer, "the screen, on its own layer")
	assert_lt(layer.layer, CloseupManager.CAPTIONS_LAYER, "under the captions: his subtitles show over it")
	var view: LampCheckView = cm.get("lamp_check")
	assert_not_null(view)
	assert_eq(view.card_text(), CARD)
	assert_true(p.state().miner(sent.id) != null and p.state().miner(sent.id).available(), "escaped: back on the roster")
	assert_true(FileAccess.file_exists(store.path_for(7)), "and the profile saved")
	var before: int = int(Variants.number(c.bytes_out.get(Lane.Id.CONTROL, 0)))
	view.step(view.started_s + view.sequence.reading_to_s + 0.5)
	view.press_ready()
	assert_eq(int(Variants.number(c.bytes_out.get(Lane.Id.CONTROL, 0))) - before,
		Protocol.frame(Protocol.Msg.LAMP_CHECK, LampCheckWire.ready()).size(), "Ready, on the control lane")
	c.lamp_check_end = LampCheckWire.read(LampCheckWire.end("ready"))
	c.lamp_check_messages += 1
	cm.call("_keep_lamp_check")
	await wait_physics_frames(2)
	assert_true(cm.get("lamp_check") == null, "the screen goes")
	assert_true(cm.get("connection") == null, "the run's connection closes")
	assert_null(cm.find_child("LampCheckScreen", true, false))
	assert_not_null(cm.find_child("DevLobby", true, false), "back to the lobby")
	assert_true(Variants.flag(cm.call("_may_connect")), "free to join the next run")


func test_without_a_seated_profile_it_still_opens() -> void:
	var w: Array = _client()
	var cm: Node = w[0]
	var c: ClientConnection = w[1]
	_open(c, "left_below", "run-y")
	cm.call("_keep_lamp_check")
	assert_true(cm.get("lamp_check") != null, "Lamp Check shows; no roster takes the outcome")
	assert_true(cm.get("profile") == null, "nor is a profile made for it")
