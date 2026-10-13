extends "res://tests/scenario/kit/scenario_test.gd"
## FND-08 (GDD §15.7, Gameplay §9.2): on a QA server, an illusion delivered to miner A produces
## exactly one magenta tag on A's client, naming its lie-log id, and none on any other client. The
## illusion itself arrives as an ordinary event; the tag rides only the debug lane. A server that is
## not dev or QA never sends a tag. (Before CRT-10, a test fixture injects the fake lie-log entry.)

const D = preload("res://tests/scenario/debug/debug_world.gd")
const FakeLie = preload("res://tests/scenario/debug/fake_lie.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## Clients join a QA server and switch their overlays on; then the server runs as `flavour`.
func _world(run_seed: int, flavour: BuildInfo.Flavour) -> Array:
	var lie: SimSystem = FakeLie.new()
	var s: Scenario = make({"seed": run_seed, "fixture": D.hall(), "systems": [lie]})
	s.net.flavour = BuildInfo.Flavour.QA
	s.net.qa_token = "lamp-qa"
	var a: MinerHandle = s.add_miner("a", Vector2i(3, 2), {"qa_token": "lamp-qa"})
	var b: MinerHandle = s.add_miner("b", Vector2i(6, 6), {"qa_token": "lamp-qa"})
	s.step(2)
	var clients: Array[DebugClient] = []
	for h: MinerHandle in [a, b]:
		var c: DebugClient = DebugClient.new()
		add_child_autofree(c)
		c.connection = h.connection
		assert_eq(c.run_line("overlay on"), "overlay on")
		clients.append(c)
	s.step(2)
	s.net.flavour = flavour
	lie.set(&"slot", a.slot)
	lie.set(&"at_tick", s.run.tick + 3)
	s.step(8)
	for c: DebugClient in clients:
		c.poll()
	return [s, a, b, clients]


func test_one_tag_on_the_target_only() -> void:
	var w: Array = _world(41, BuildInfo.Flavour.QA)
	var a: MinerHandle = w[1]
	var b: MinerHandle = w[2]
	var clients: Array[DebugClient] = w[3]
	var callouts: Array[Dictionary] = []
	for e: Dictionary in a.connection.events:
		if int(Variants.number(e["type"])) == NoiseTypes.Type.CALLOUT:
			callouts.append(e)
	assert_eq(callouts.size(), 1, "A received the illusion as an ordinary event")
	assert_eq(clients[0].overlay.received, 1, "exactly one tag on A's client")
	assert_eq(clients[0].overlay.tags.size(), 1)
	var tag: Dictionary = clients[0].overlay.tags[0]
	assert_eq(int(Variants.number(tag["illusion_id"])), 77, "naming its lie-log id")
	assert_eq(int(Variants.number(tag["number"])), int(Variants.number(callouts[0]["number"])), "by that event's record number")
	assert_eq(clients[1].overlay.received, 0, "none on B's")
	for e: Dictionary in b.connection.events:
		assert_ne(int(Variants.number(e["type"])), NoiseTypes.Type.CALLOUT, "B never received the illusion")


func test_no_tag_off_a_qa_server() -> void:
	var w: Array = _world(42, BuildInfo.Flavour.RELEASE)
	var clients: Array[DebugClient] = w[3]
	assert_eq(clients[0].overlay.received, 0, "a release server sends no tag")
	var a: MinerHandle = w[1]
	var callouts: int = 0
	for e: Dictionary in a.connection.events:
		if int(Variants.number(e["type"])) == NoiseTypes.Type.CALLOUT:
			callouts += 1
	assert_eq(callouts, 1, "though the illusion itself arrived")
