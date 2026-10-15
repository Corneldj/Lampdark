extends "res://tests/scenario/kit/scenario_test.gd"
## SND-12: a signal reaches only watchers who see its maker: inside the cone, in line of sight, within
## 40 tiles. The kind rides in the maker's identity record, so a watcher's client gets it and one
## facing away or beyond 40 tiles does not. A Hand stub inside the cone gets signal_seen (POINT with
## its tile); one facing away does not.

const W = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _client_kind(s: Scenario, h: MinerHandle) -> int:
	var view: ReceivedView = s.client(h).records_at(s.run.tick - 1)
	if view == null:
		return -1
	for raw: Variant in view.entities.keys():
		var e: Dictionary = view.entities[raw]
		if int(Variants.number(e.get("level", 0))) == 2:
			var k: int = LampSignalKind.of_flame(int(Variants.number(e.get("flame", 0))))
			if k != 0:
				return k
	return 0


func test_cone_line_of_sight_and_forty_tiles() -> void:
	var s: Scenario = make({"seed": 1121, "fixture": W.road(52)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = W.miner(s, "ann", a, 0.0)
	var bob: MinerHandle = W.miner(s, "bob", a + Vector2i(10, 0), 180.0)  # facing her
	var cid: MinerHandle = W.miner(s, "cid", a + Vector2i(12, 1), 0.0)  # facing away
	var dan: MinerHandle = W.miner(s, "dan", a + Vector2i(45, 0), 180.0)  # facing her, 45 tiles off
	var hands: Array[int] = [bob.entity_id, cid.entity_id]
	s.run.crew.is_hand_driven = func(e: int) -> bool: return hands.has(e)
	var seen: Array[Array] = []
	s.run.lamp_signals.signal_seen.connect(func(hand: int, kind: LampSignalKind.Kind, tile: Vector2i) -> void:
		seen.append([hand, kind, tile]))
	s.step(3)
	W.signal_press(s, ann, LampSignalKind.Kind.POINT)
	s.step(4)
	var row: Dictionary = s.run.lamp_signals.history[s.run.lamp_signals.history.size() - 1]
	var watchers: Array = row["watchers"]
	assert_true(watchers.has(bob.entity_id), "Bob, facing her at 10 tiles")
	assert_false(watchers.has(cid.entity_id), "not Cid, facing away")
	assert_false(watchers.has(dan.entity_id), "not Dan, beyond 40 tiles")
	s.step(2)
	assert_eq(_client_kind(s, bob), LampSignalKind.Kind.POINT, "Bob's client gets the signal")
	assert_eq(_client_kind(s, cid), 0, "Cid's gets nothing")
	assert_eq(_client_kind(s, dan), 0, "nor Dan's")
	assert_eq(seen.size(), 1, "the Hand stub in the cone got it; the one facing away did not")
	var got: Array = seen[0]
	var who: int = got[0]
	var kind: int = got[1]
	var tile: Vector2i = got[2]
	assert_eq(who, bob.entity_id)
	assert_eq(kind, LampSignalKind.Kind.POINT)
	assert_eq(tile, Vector2i(s.run.registry.get_entity(ann.entity_id).position + Vector2(6.0, 0.0)), "with its tile")
	s.step(45)
	assert_eq(_client_kind(s, bob), 0, "and only while it lasts")
