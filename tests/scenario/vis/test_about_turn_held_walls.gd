extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-05 (GDD §5.6): Ann looks west down the hall, then east. The walls and floor she was sent stay
## held. When she turns west again, the very next client frame draws the held layout under her
## predicted lamp, before any server frame answers. Once the server acknowledges the turn, only what
## it lists stays drawn.

const FW = preload("res://tests/scenario/vis/flame_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _predicted(ann: MinerHandle, s: Scenario, deg: float) -> Dictionary:
	var at: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	return {"position": at, "facing": Intents.facing_u16(deg), "lamp": {"position": at, "radius": LampRules.hand_radius(2)}}


func test_next_frame_draws_held_walls() -> void:
	var s: Scenario = make({"seed": 81, "fixture": FW.hall(30)})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(15, 3), {"facing_deg": 180.0})
	ann.at(0).face(180.0)
	s.step(1)
	L.lit_in_hand(s, ann)
	s.step(6)
	var west_tiles: Array = ann.connection.view.tiles.keys().filter(func(t: Vector2i) -> bool: return t.x < 15)
	assert_gt(west_tiles.size(), 4, "she saw the west end")
	ann.at(s.run.tick).face(0.0)
	s.step(6)
	var view: ReceivedView = ann.connection.view
	var still_seen_west: int = view.tiles.keys().filter(func(t: Vector2i) -> bool: return t.x < 14).size()
	assert_eq(still_seen_west, 0, "facing east, nothing west is in the seen set")
	var held_west: int = view.geometry.keys().filter(func(t: Vector2i) -> bool: return t.x < 14).size()
	assert_gt(held_west, 0, "but its layout is held")
	# She turns west: the input that carries it has not been acknowledged yet.
	var turn_seq: int = (ann.connection.inputs.next_seq) & 0xFFFF
	var drawn: DrawnSet = DrawnSet.new()
	drawn.build(view, _predicted(ann, s, 180.0), ann.connection.last_input_ack, turn_seq)
	var drawn_west: int = drawn.tiles.keys().filter(func(t: Vector2i) -> bool: return t.x < 14).size()
	assert_gt(drawn_west, 0, "the next frame draws the held west end under the predicted lamp")
	var all_provisional: bool = true
	for raw: Variant in drawn.tiles.keys():
		var t: Vector2i = raw
		if t.x < 14 and not Variants.flag(Variants.dict(drawn.tiles[raw])["provisional"]):
			all_provisional = false
	assert_true(all_provisional, "provisionally: the server has not listed them")
	# The server answers the turn; the drawn set becomes exactly what it lists.
	ann.at(s.run.tick).face(180.0)
	s.step(8)
	view = ann.connection.view
	drawn.build(view, _predicted(ann, s, 180.0), ann.connection.last_input_ack, turn_seq)
	assert_eq(drawn.provisional_count, 0, "acknowledged: nothing provisional")
	var listed: Array = view.tiles.keys()
	listed.sort()
	var now: Array = drawn.tiles.keys()
	now.sort()
	assert_eq(now, listed, "only what the server lists")
