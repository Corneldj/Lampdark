extends "res://tests/scenario/kit/scenario_test.gd"
## NET-12's turn band: the miner's turning is capped (movement.turn_rate_deg_s), so the server sends
## a lit large thing just outside the cone, within what she can turn into before the next frame
## lands, as a hidden margin record (level 3) the client reveals with its own predicted cone. Past
## the band, the blind area, nothing is sent; small things are never prefetched; the band follows
## the link's round trip, up to vision.turn_band_max_deg.

const M = preload("res://tests/scenario/vis/margin_world.gd")
const LAMP_AT: Vector2 = Vector2(8.5, 4.5)


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(seed_value: int, radius: float = 4.0) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": M.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.at(0).face(0.0)
	M.lamp(s, ann.entity_id, LAMP_AT, radius)
	return [s, ann]


## Where a thing `deg` off Ann's facing (east), `dist` tiles away, stands.
func _at(deg: float, dist: float) -> Vector2:
	return LAMP_AT + Vector2.from_angle(deg_to_rad(deg)) * dist


func _near(list: PackedVector2Array, p: Vector2) -> bool:
	for q: Vector2 in list:
		if q.distance_to(p) < 0.01:
			return true
	return false


func _sent(frame: Dictionary, key: String, p: Vector2) -> bool:
	var positions: PackedVector2Array = Variants.dict(frame.get(key, {})).get("position", PackedVector2Array())
	return _near(positions, p)


func test_band_width_follows_the_turn_rate_and_round_trip() -> void:
	var hz: float = Tuning.f(&"net.tick_hz")
	var lag: float = Tuning.f(&"net.input_buffer_target_ticks") / hz + 1.0 / hz + Tuning.f(&"vision.turn_band_extra_s")
	var rate: float = Tuning.f(&"movement.turn_rate_deg_s")
	assert_almost_eq(VisionSystem.turn_band_deg(0.0), rate * lag, 0.001)
	assert_almost_eq(VisionSystem.turn_band_deg(120.0), rate * (0.12 + lag), 0.001)
	assert_eq(VisionSystem.turn_band_deg(5000.0), Tuning.f(&"vision.turn_band_max_deg"), "capped")


func test_lit_moth_in_the_band_is_a_hidden_record_and_one_behind_is_never_sent() -> void:
	var setup: Array = _setup(71)
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	var half: float = Tuning.f(&"vision.cone_deg") / 2.0
	var band: float = VisionSystem.turn_band_deg(0.0)
	assert_gt(band, 20.0, "a band to test in")
	# In the band: past the cone's edge (footprint and all), short of the band's.
	var in_band: Vector2 = _at(half + band * 0.5 + 10.0, 2.6)
	var behind: Vector2 = _at(180.0, 3.0)
	s.run.registry.create(WorldIds.EntityKind.MOTH, in_band)
	s.run.registry.create(WorldIds.EntityKind.MOTH, behind)
	s.step(3)
	var frame: Dictionary = s.run.vision.frame_for(ann.slot)
	assert_false(s.run.vision.native.in_cone(ann.slot, in_band), "outside the cone")
	assert_false(_sent(frame, "tokens", in_band), "not seen: no fringe token")
	assert_true(_sent(frame, "margin_tokens", in_band), "prefetched as a hidden margin record")
	assert_false(_sent(frame, "tokens", behind), "behind: not seen")
	assert_false(_sent(frame, "margin_tokens", behind), "behind, past the band: never sent")


func test_small_things_never_ride_the_band() -> void:
	var setup: Array = _setup(72)
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	var half: float = Tuning.f(&"vision.cone_deg") / 2.0
	var band: float = VisionSystem.turn_band_deg(0.0)
	var trap: Vector2 = _at(half + band * 0.5 + 10.0, 2.6)
	s.run.registry.create(WorldIds.EntityKind.TRAP, trap)
	s.step(3)
	assert_false(_sent(s.run.vision.frame_for(ann.slot), "margin_tokens", trap), "a small thing is never prefetched")


func test_an_unlit_moth_in_the_band_is_never_sent() -> void:
	# A 1-tile pool: the moth stands in the band, 3 tiles out, in the dark.
	var setup: Array = _setup(74, 1.0)
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	var dark: Vector2 = _at(95.0, 3.2)
	assert_lt(95.0, Tuning.f(&"vision.cone_deg") / 2.0 + VisionSystem.turn_band_deg(0.0), "in the band")
	s.run.registry.create(WorldIds.EntityKind.MOTH, dark)
	s.step(3)
	var frame: Dictionary = s.run.vision.frame_for(ann.slot)
	assert_false(_sent(frame, "tokens", dark))
	assert_false(_sent(frame, "margin_tokens", dark), "unlit: never prefetched")


func test_a_longer_round_trip_widens_the_band() -> void:
	var setup: Array = _setup(73)
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	var half: float = Tuning.f(&"vision.cone_deg") / 2.0
	var narrow: float = VisionSystem.turn_band_deg(0.0)
	var wide: float = VisionSystem.turn_band_deg(200.0)
	assert_gt(wide - narrow, 40.0)
	var p: Vector2 = _at(half + narrow + 25.0, 2.6)
	s.run.registry.create(WorldIds.EntityKind.MOTH, p)
	s.step(3)
	assert_false(_sent(s.run.vision.frame_for(ann.slot), "margin_tokens", p), "past the band on a short link")
	s.run.vision.rtt_ms = func(_slot: int) -> float: return 200.0
	s.step(2)
	assert_true(_sent(s.run.vision.frame_for(ann.slot), "margin_tokens", p), "inside it at 200 ms")
