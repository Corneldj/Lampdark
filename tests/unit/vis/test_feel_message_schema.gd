extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-07: a feel answer holds only a caption key, a quantised bearing and a verb key: no position,
## entity id, token or distance. A heap of coats and a sleeping Moth give byte-identical answers;
## an awake Moth gives '[coats, moving]'.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const F = preload("res://tests/unit/vis/feel_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_schema() -> void:
	var bytes: PackedByteArray = FeelMessages.feel("feel.item.spanner", 3, "verb.pick_up")
	var d: Dictionary = FeelMessages.decode(bytes)
	var keys: Array = d.keys()
	keys.sort()
	assert_eq(keys, ["bearing_q", "caption_key", "kind", "verb_key"])
	assert_eq(bytes.size(), 1 + 1 + "feel.item.spanner".length() + 1 + 1 + "verb.pick_up".length(), "nothing else rides")
	var b: Dictionary = FeelMessages.decode(FeelMessages.bump("caption.bump.steel"))
	assert_eq(b.keys().size(), 2, "a bump: kind and caption only")


## The bytes ann's client receives from feeling one thing placed a tile east of her.
func _feel_bytes(run_seed: int, place: Callable) -> PackedByteArray:
	var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	place.call(s, a + Vector2i(1, 0))
	var ann: MinerHandle = s.add_miner("ann", a)
	s.step(2)
	var got: Array[PackedByteArray] = []
	ann.connection.message_observer = func(_lane: int, data: PackedByteArray, _now: int) -> void:
		var message: Dictionary = Protocol.unframe(data)
		if not message.is_empty() and int(Variants.number(message["type"])) == Protocol.Msg.FEEL:
			got.append(message["payload"])
	F.feel(s, ann)
	return got[0] if not got.is_empty() else PackedByteArray()


func test_heap_and_sleeping_moth_identical() -> void:
	var heap: PackedByteArray = _feel_bytes(10, func(s: Scenario, at: Vector2i) -> void:
		s.run.registry.create(WorldIds.EntityKind.COAT_HEAP, Vector2(at) + Vector2(0.5, 0.5)))
	var moth: PackedByteArray = _feel_bytes(11, func(s: Scenario, at: Vector2i) -> void:
		s.place_creature(WorldIds.EntityKind.MOTH, at))
	assert_false(heap.is_empty())
	assert_eq(moth, heap, "byte-identical")
	assert_eq(str(FeelMessages.decode(heap)["caption_key"]), "feel.heap_of_coats")
	var awake: PackedByteArray = _feel_bytes(12, func(s: Scenario, at: Vector2i) -> void:
		s.place_creature(WorldIds.EntityKind.MOTH, at)
		var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
		m.enter(s.run, &"prowl", "test")
		m.awake.begin(s.run, m, false)
		m.awake.heading_home = true)
	assert_eq(str(FeelMessages.decode(awake)["caption_key"]), "feel.coats_moving")
