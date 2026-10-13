extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-15: scripted device frames become the expected server intents. Through the real input sender
## and the wire, the server receives exactly the router's direction, facing, held bits, wanted lamp
## and slot state and one-shot picks; and driven through the kit, the miner walks the way pressed,
## the shutter press shuts the lamp, and the rock tap and a callout pick arrive once each. Nothing
## the client sends is a hit, a target or a computed result.

const F = preload("res://tests/unit/mnr/input_frames.gd")
const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const TICK_S: float = 0.05


func before_all() -> void:
	assert_true(Tuning.load_server())


## The script: [from_s, until_s, down, extra].
func _script() -> Array:
	var own: Vector2 = Vector2(640, 360)
	return [
		[0.0, 0.5, {"move_right": true}, {"cursor": own + Vector2(100, 0), "own_screen": own}],
		[0.5, 0.55, {"shutter": true}, {"cursor": own + Vector2(0, 100), "own_screen": own}],
		[0.7, 0.75, {"slot_3": true}, {}],
		[0.8, 0.85, {"tap_rock": true}, {}],
		[0.9, 1.2, {"callout": true}, {"wheel_vec": Vector2(0.0, -0.8)}],
		[1.2, 1.25, {}, {"wheel_vec": Vector2(0.0, -0.8)}],
		[1.3, 1.6, {"crouch": true, "move_up": true}, {}],
	]


func _frame_at(t: float) -> Dictionary:
	var down: Dictionary = {}
	var extra: Dictionary = {}
	for raw: Variant in _script():
		var row: Array = raw
		if t >= Variants.number(row[0]) - 1e-9 and t < Variants.number(row[1]) - 1e-9:
			down.merge(Variants.dict(row[2]), true)
			extra.merge(Variants.dict(row[3]), true)
	return F.frame(t, down, extra)


func _wire(p: InputPacket) -> InputPacket:
	var message: Dictionary = Protocol.unframe(p.encode())
	var payload: PackedByteArray = message["payload"]
	return InputPacket.decode(payload)


func test_router_to_wire() -> void:
	var r: InputRouter = F.router()
	var sender: ClientInputSender = ClientInputSender.new()
	var sent_actions: Array = []
	for i: int in 40:
		var rec: InputRecord = r.sample(_frame_at(i * TICK_S))
		for a: Array in r.actions:
			sender.queue_action(int(Variants.number(a[0])) as ActionRecord.Kind, int(Variants.number(a[1])), i, int(Variants.number(a[2])))
			sent_actions.append(a)
		sender.sample(rec, i)
		var got: InputPacket = _wire(sender.build_packet(i, 0, 0))
		var newest: InputRecord = got.inputs[0]
		assert_eq([newest.move_dir, newest.gait, newest.facing, newest.holds, newest.desired],
			[rec.move_dir, rec.gait, rec.facing, rec.holds, rec.desired], "tick %d" % i)
	var p: InputPacket = _wire(sender.build_packet(40, 0, 0))
	var kinds: Array[int] = []
	for a: ActionRecord in p.actions:
		kinds.append(a.kind)
	assert_eq(kinds, [ActionRecord.Kind.TAP_ROCK, ActionRecord.Kind.CALLOUT] as Array[int], "unacknowledged, both still riding")
	assert_eq(p.actions[1].aim, Intents.facing_u16(270.0), "the pick's angle")
	assert_almost_eq(Variants.number(Intents.decode_wheel_arg(p.actions[1].arg)["distance"]), 0.8, 0.001, "and its distance")
	assert_eq(sent_actions.size(), 2)


func test_router_drives_the_miner() -> void:
	var s: Scenario = make({"seed": 15, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	var l: GauzeLamp = L.lit_in_hand(s, ann)
	var r: InputRouter = F.router()
	r.sync_lamp(false, l.wick)
	var base: int = s.run.tick
	for i: int in 40:
		var rec: InputRecord = r.sample(_frame_at(i * TICK_S))
		ann.at(base + i).input(rec)
		for a: Array in r.actions:
			ann.at(base + i).press(int(Variants.number(a[0])) as ActionRecord.Kind, int(Variants.number(a[1])),
				Variants.number(a[2]) / 65536.0 * 360.0)
	var start: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var applied: Array[ActionRecord] = []
	var x_at: Array[float] = []
	s.on_tick = func(sc: Scenario) -> void:
		var view: Dictionary = sc.state.miner(ann)
		var got: Array[ActionRecord] = view["actions"]
		applied.append_array(got)
		x_at.append(sc.run.registry.get_entity(ann.entity_id).position.x)
	s.step(12)
	assert_gt(x_at[-1], start.x + 0.5, "D walks east")
	s.step(30)
	var end: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	assert_lt(end.y, start.y - 0.1, "W walks north")
	assert_true(l.shutter_closed, "Q shut the lamp")
	assert_eq(s.run.inventory.hands_of(ann.entity_id).selected, 2, "3 picked the third slot")
	var kinds: Array[int] = []
	for a: ActionRecord in applied:
		kinds.append(a.kind)
	assert_eq(kinds, [ActionRecord.Kind.TAP_ROCK, ActionRecord.Kind.CALLOUT] as Array[int], "each once")
