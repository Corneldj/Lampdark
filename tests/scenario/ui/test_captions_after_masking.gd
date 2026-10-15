extends "res://tests/scenario/kit/scenario_test.gd"
## UI-03: captions come after the server's masks and the rock. What a mask drops (the Fan's surge,
## stood in for here until SND-16; a shot's deafness) or a shut gate keeps out never reaches the
## client, so it is never captioned; '[ringing]' shows while deafened.

const F = preload("res://tests/scenario/ui/caption_feed.gd")
const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _feed(s: Scenario, h: MinerHandle) -> F:
	var f: F = F.new(h, self)
	s.on_tick = func(sc: Scenario) -> void: f.pump(sc)
	return f


func _count(f: F, text: String) -> int:
	return f.texts().filter(func(t: String) -> bool: return t == text).size()


func test_a_mask_and_deafness_leave_no_caption() -> void:
	var s: Scenario = make({"seed": 301, "fixture": "test"})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(2, 1))
	var f: F = _feed(s, ann)
	s.step(5)
	var near: Vector2i = Vector2i(5, 1)
	s.run.noise.emit(NoiseTypes.Type.ROCK_TAP, near)
	s.step(6)
	assert_eq(_count(f, "[a tap on the rock]"), 1, "heard, captioned")
	# The Fan's surge (SND-16) drops what it covers; a stand-in mask does the same here.
	var surge: Array[bool] = [true]
	s.run.audio.register_mask("fan_surge_stand_in", func(_r: RunState, _slot: int, _rec: AudioRecord) -> Variant:
		return null if surge[0] else {})
	s.run.noise.emit(NoiseTypes.Type.HAMMER, near)
	s.step(6)
	assert_eq(_count(f, "[hammering]"), 0, "masked: neither heard nor captioned")
	surge[0] = false
	# A shot's deafness: taps and voices dropped for 5 s, other sounds 20 dB down; '[ringing]' over it.
	s.run.deafen.deafen(s.run, ann.slot)
	s.step(3)
	s.run.noise.emit(NoiseTypes.Type.ROCK_TAP, near + Vector2i(0, 1))
	s.run.noise.emit(NoiseTypes.Type.GATE, near)
	s.step(6)
	assert_eq(_count(f, "[a tap on the rock]"), 1, "the tap during deafness: no caption")
	assert_eq(_count(f, "[a gate clanging]"), 1, "the gate, delivered 20 dB down: captioned")
	assert_eq(_count(f, "[ringing]"), 1, "'[ringing]' while deafened")
	var shown: Array[String] = []
	for l: Dictionary in f.system.visible_lines():
		shown.append(str(l["text"]))
	assert_true(shown.has("[ringing]"))
	f.free_nodes()


func test_a_shut_gate_keeps_out_a_quiet_sound_and_its_caption() -> void:
	var s: Scenario = make({"seed": 302, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	var inside: Vector2i = west.middle() - west.outward
	var ann: MinerHandle = s.add_miner("ann", inside)
	var f: F = _feed(s, ann)
	s.step(5)
	var road: Vector2i = west.middle() + west.outward * 3
	s.run.noise.emit(NoiseTypes.Type.STEP_WALK, road)
	s.step(6)
	assert_eq(_count(f, "[footsteps]"), 0, "a footstep beyond the shut gate: unheard, uncaptioned")
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	s.step(2)
	s.run.noise.emit(NoiseTypes.Type.STEP_WALK, road)
	s.step(6)
	assert_eq(_count(f, "[footsteps]"), 1, "the gate open: heard and captioned")
	f.free_nodes()
