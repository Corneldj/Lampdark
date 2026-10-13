extends "res://tests/scenario/kit/scenario_test.gd"
## FND-08 (§9.2, GDD §15.11): with the truth view and overlay on, and with both off, each miner's
## normal-stream bytes are identical tick for tick. A client without the QA token on a QA server
## gets no debug channel: its debug-lane lines are refused and nothing comes back. A release
## client never joins a QA server.

const D = preload("res://tests/scenario/debug/debug_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _run(views_on: bool) -> Array:
	var s: Scenario = make({"seed": 31, "fixture": D.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(3, 2))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(6, 6))
	s.step(2)
	if views_on:
		ann.connection.send(Lane.Id.DEBUG, DebugMessages.encode({"truth": true, "layers": DebugCommands.LAYERS, "overlay": true}),
			Protocol.Msg.DEBUG_SUBSCRIBE)
	s.place_creature(WorldIds.EntityKind.TAPPER, Vector2i(25, 7))
	ann.walk_to(Vector2i(20, 1))
	bob.walk_to(Vector2i(14, 8))
	s.step(80)
	return [s, ann, bob]


func _normal(h: MinerHandle) -> Array:
	var out: Array = []
	for m: Dictionary in h.capture.messages:
		if int(Variants.number(m["lane"])) != Lane.Id.DEBUG:
			out.append([m["tick"], m["lane"], m["bytes"]])
	return out


func test_normal_streams_identical_with_views_on_and_off() -> void:
	var on: Array = _run(true)
	var off: Array = _run(false)
	var ann_on: MinerHandle = on[1]
	var ann_off: MinerHandle = off[1]
	var truth: int = 0
	for m: Dictionary in ann_on.capture.messages:
		if int(Variants.number(m["lane"])) == Lane.Id.DEBUG:
			truth += 1
	assert_gt(truth, 10, "the truth view was fed (5 Hz) on the debug lane")
	assert_eq(_normal(ann_on), _normal(ann_off), "Ann's normal stream: identical tick for tick")
	var bob_on: MinerHandle = on[2]
	var bob_off: MinerHandle = off[2]
	assert_eq(_normal(bob_on), _normal(bob_off), "Bob's too")
	assert_gt(_normal(ann_on).size(), 80)


func test_no_token_no_channel_on_a_qa_server() -> void:
	var s: Scenario = make({"seed": 32, "fixture": D.hall()})
	s.net.flavour = BuildInfo.Flavour.QA
	s.net.qa_token = "lamp-qa"
	var ann: MinerHandle = s.add_miner("ann", Vector2i(3, 2))
	s.step(2)
	assert_false(ann.connection.has_debug(), "no token: no debug channel")
	var before: int = s.net.debug_refused
	ann.connection.send(Lane.Id.DEBUG, DebugMessages.encode({"line": "teleport me 20 1"}), Protocol.Msg.DEBUG_COMMAND)
	s.step(3)
	assert_eq(s.net.debug_refused, before + 1, "the server refuses the line")
	assert_false(s.run.header.debug_tainted, "and nothing ran")
	assert_eq(ann.connection.debug_inbox.size(), 0, "nothing comes back")
	var client: DebugClient = DebugClient.new()
	add_child_autofree(client)
	client.connection = ann.connection
	assert_string_contains(client.run_line("spawn moth"), "refused", "the console refuses server commands")
	assert_string_contains(client.run_line("help"), "commands", "client commands still work")


func test_token_opens_it_and_the_console_round_trips() -> void:
	var s: Scenario = make({"seed": 33, "fixture": D.hall()})
	s.net.flavour = BuildInfo.Flavour.QA
	s.net.qa_token = "lamp-qa"
	var ann: MinerHandle = s.add_miner("ann", Vector2i(3, 2), {"qa_token": "lamp-qa"})
	s.step(2)
	assert_true(ann.connection.has_debug(), "the token opens the debug channel")
	var client: DebugClient = DebugClient.new()
	add_child_autofree(client)
	client.connection = ann.connection
	assert_eq(client.run_line("teleport me 20 1"), "sent")
	s.step(3)
	client.poll()
	assert_eq(client.replies.size(), 1, "one answer, on the debug lane")
	assert_true(Variants.flag(Variants.flag(client.replies[0]["ok"])), str(client.replies[0]))
	assert_true(s.run.header.debug_tainted)


func test_release_client_never_joins_a_qa_server() -> void:
	var s: Scenario = make({"seed": 34, "fixture": D.hall()})
	s.net.flavour = BuildInfo.Flavour.QA
	assert_eq(s.net.debug_granted("", true), false, "QA: never without the token")
	s.net.flavour = BuildInfo.Flavour.RELEASE
	s.net.qa_token = "x"
	assert_false(s.net.debug_granted("x", true), "release: never")
	s.net.flavour = BuildInfo.Flavour.DEV
	s.net.qa_token = ""
	assert_true(s.net.debug_granted("", true), "dev: a local run needs no token")
	assert_false(s.net.debug_granted("", false), "but a remote one does")
	var hello: Protocol.Hello = Protocol.Hello.new()
	hello.flavour = BuildInfo.Flavour.RELEASE
	hello.qa_token = "t"
	var payload: PackedByteArray = Protocol.unframe(hello.encode())["payload"]
	var back: Protocol.Hello = Protocol.Hello.decode(payload)
	assert_eq([back.flavour, back.qa_token], [BuildInfo.Flavour.RELEASE, "t"])
