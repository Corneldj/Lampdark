extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-01: every inside floor tile reads exactly 0.6 with no other source; nothing beyond a shut gate
## gets emergency light; a lamp inside adds to it, capped at 1.0; no modifier touches it.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_light() -> void:
	var s: Scenario = make({"seed": 8, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s, 3)
	C.shut_all(s)
	s.step(2)
	for raw: Variant in camp.inside_tiles.keys():
		var t: Vector2i = raw
		assert_almost_eq(s.run.light.light_at(t), 0.6, 1e-9, "0.6 at %s" % t)
	for g: Dictionary in camp.gates:
		var outward: Vector2i = g["outward"]
		for raw: Variant in Variants.array(g["tiles"]):
			var t: Vector2i = raw
			for k: int in range(1, 6):
				assert_eq(s.run.light.light_at(t + outward * k), 0.0, "no emergency light beyond a shut gate")
	var deck: Rect2i = Basecamp.deck_rect(C.SEED, 3)
	var lamp: int = s.run.light.grid.add_point("gauze_lamp", 1, 0, 0, 5.5, 1.0, Vector2(deck.get_center()), 0)
	s.step(2)
	var top: float = 0.0
	for raw: Variant in camp.inside_tiles.keys():
		var t: Vector2i = raw
		var v: float = s.run.light.light_at(t)
		assert_gte(v, 0.6 - 1e-9)
		assert_lte(v, 1.0 + 1e-9, "capped at 1.0")
		top = maxf(top, v)
	assert_almost_eq(top, 1.0, 1e-9, "a lamp inside adds, up to the cap")
	s.run.light.grid.remove_source(lamp)
	# A gutter or shrink acts on a flame's radius; on the emergency area it changes nothing.
	s.run.light.grid.set_radius_modifier(camp.lights.source, 0.5, "gutter")
	s.step(2)
	for t: Vector2i in camp.inside_tiles.keys():
		assert_almost_eq(s.run.light.light_at(t), 0.6, 1e-9)
