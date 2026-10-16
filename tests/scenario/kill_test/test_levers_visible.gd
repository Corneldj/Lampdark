extends "res://tests/scenario/kit/scenario_test.gd"
## A gate's levers can be found by looking: each is a LEVER entity, seen like a small thing (0.30 of
## light), so a miner in lit base camp sees the lever beside a shut gate with the glyph "Pull lever",
## and holding interact on it opens the gate. A lever out in the dark is not seen. (Found in a solo
## playtest: with nothing drawn, a player could not leave base camp.)

const MAP: String = "m1_greybox"


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_lever_is_seen_and_opens_its_gate() -> void:
	var s: Scenario = make({"seed": 141, "fixture": MAP})
	FixedMapLoader.populate(s.run, MAP, true, true)
	var levers: Array[Vector2] = []
	for id: int in s.run.registry.ids():
		var e: SimEntity = s.run.registry.get_entity(id)
		if e.kind == WorldIds.EntityKind.LEVER:
			levers.append(e.position)
	assert_eq(levers.size(), 6, "two levers at each of the three gates")
	var north: Gate = s.run.base_camp.gate_system.gate("north")
	var lever: Vector2i = north.levers["inside"]
	var h: MinerHandle = s.add_miner("me", lever + Vector2i(0, 1), {"facing_deg": 270.0})
	h.brain = null
	h.at(s.run.tick).face(270.0)
	s.step(10)
	var seen: Array = []
	for raw: Variant in h.connection.view.entities.keys():
		var e: Dictionary = h.connection.view.entities[raw]
		if int(Variants.number(e.get("size_or_kind", 0))) == SeenKind.Kind.LEVER and int(Variants.number(e.get("level", 0))) == 2:
			var at: Vector2 = e.get("position", Vector2.ZERO)
			seen.append(Vector2i(at.floor()))
	assert_has(seen, lever, "the lever beside the north gate is seen")
	var outside: Vector2i = north.levers["outside"]
	assert_does_not_have(seen, outside, "the one outside, in the dark, is not")
	var glyph: Dictionary = InteractionGlyph.pick(h.connection.view, Tuning.f(&"vision.touch_range_tiles"))
	assert_eq(str(glyph.get("verb_key", "")), "verb.lever", "its glyph: Pull lever")
	assert_false(north.open)
	var ticks: int = roundi(Tuning.f(&"basecamp.gate_lever_s") * Tuning.f(&"net.tick_hz")) + 4
	h.at(s.run.tick).face(270.0).hold(InputRecord.HOLD_INTERACT, ticks)
	s.step(ticks + 4)
	assert_true(north.open, "held, it opens the gate")
