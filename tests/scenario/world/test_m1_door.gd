extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-03 on the grey box's air door (GEN-15's AirDoorSystem; Gameplay §6.1, §6.2): shut, it stops
## bodies, light and voice and costs 12 np; open, none of these; it never shuts on an occupied doorway.

const MAP: String = "m1_greybox"
const DOOR: Vector2i = Vector2i(25, 12)
const PASSAGE: Vector2i = Vector2i(25, 11)  # the road side
const HOARD: Vector2i = Vector2i(25, 14)    # the coat chamber


func before_all() -> void:
	assert_true(Tuning.load_server())


func _work_door(s: Scenario, h: MinerHandle) -> void:
	var need: int = roundi(Tuning.f(&"mine.air_door_operate_s") * Tuning.f(&"net.tick_hz"))
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, need + 4)
	s.step(need + 8)


func test_shut_it_stops_bodies_light_and_voice_and_costs_12_np() -> void:
	var s: Scenario = make({"seed": 31, "fixture": MAP})
	var ann: MinerHandle = s.add_miner("ann", PASSAGE, {"facing_deg": 90.0})
	var ben: MinerHandle = s.add_miner("ben", Vector2i(36, 9))
	var cat: MinerHandle = s.add_miner("cat", Vector2i(24, 15))
	s.run.light.grid.add_point("gauze_lamp", LbLightGrid.COLOUR_AMBER, 0, 0, 5.0, 1.0, Vector2(HOARD) + Vector2(0.5, 0.5), 0)
	s.step(3)
	var door: AirDoorSystem.Door = s.run.air_doors.door_at(DOOR)
	assert_not_null(door, "the grey box's door is GEN-15's")
	assert_false(door.open, "shut at the start")
	var shut: Dictionary = _measure(s, ben, cat)
	_work_door(s, ann)
	assert_true(door.open, "Ann opened it")
	var open: Dictionary = _measure(s, ben, cat)
	assert_false(Variants.flag(shut["body"]), "shut: no way through")
	assert_true(Variants.flag(open["body"]), "open: a way through")
	assert_eq(int(Variants.number(shut["light"])), 0, "shut: the hoard's lamp lights nothing in the passage")
	assert_gt(int(Variants.number(open["light"])), 0, "open: it does")
	assert_eq(int(Variants.number(shut["voice"])), 0, "shut: Cat's shout never reaches Ben")
	assert_gt(int(Variants.number(open["voice"])), 0, "open: it does")
	assert_eq(int(Variants.number(shut["closed"])), 1)
	assert_eq(int(Variants.number(open["closed"])), 0)
	assert_almost_eq(float(Variants.number(open["remaining"])) - float(Variants.number(shut["remaining"])), 12.0, 1e-6,
		"the shut door costs exactly 12 np")


func _measure(s: Scenario, ben: MinerHandle, cat: MinerHandle) -> Dictionary:
	s.step(2)
	var out: Dictionary = {}
	out["body"] = s.mine.path_distance(PASSAGE, HOARD, 40.0, false).distance >= 0.0
	out["light"] = s.run.light.grid.value(PASSAGE)
	ben.connection.voice_in.clear()
	cat.at(s.run.tick).say(3, 6)
	s.step(8)
	out["voice"] = ben.connection.voice_in.size()
	cat.connection.send_voice(VoicePackets.end(cat.voice_frames_sent))
	s.step(2)
	ben.connection.voice_in.clear()
	var d: Dictionary = s.run.road_graph.graph.deliver(Vector2i(24, 15), 30.0, Vector2i(36, 9), LbRoadGraph.MODE_AIR, 0.0, 1.0, 7)
	out["closed"] = d.get("closed_portals", -1)
	out["remaining"] = d.get("remaining_np", -1.0)
	return out


func test_it_never_shuts_on_an_occupied_doorway() -> void:
	var s: Scenario = make({"seed": 32, "fixture": MAP})
	var ann: MinerHandle = s.add_miner("ann", PASSAGE, {"facing_deg": 90.0})
	s.step(3)
	_work_door(s, ann)
	var door: AirDoorSystem.Door = s.run.air_doors.door_at(DOOR)
	assert_true(door.open)
	var bob: MinerHandle = s.add_miner("bob", DOOR)
	s.step(2)
	var need: int = roundi(Tuning.f(&"mine.air_door_operate_s") * Tuning.f(&"net.tick_hz"))
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, need * 3)
	s.step(need + 10)
	assert_true(door.open, "Bob stands in the doorway: it waits")
	s.run.movement.place(s.run, bob.entity_id, Vector2(HOARD) + Vector2(0.5, 1.5))
	s.step(6)
	assert_false(door.open, "the doorway clear, it shuts")
