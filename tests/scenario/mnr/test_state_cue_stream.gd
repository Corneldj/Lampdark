extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-03 (scn_state_cue_stream): a Caught miner seen at 0.30 shows its cue; seen at 0.20 it
## is a bare token (the same scene, dimmer). The owning client gets its own life state and
## capabilities, and no stream carries overlays, marks, timers or causes.

const ROWS: PackedStringArray = [
	"#################",
	"#a......c......b#",
	"#################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_cue_only_with_identity() -> void:
	var s: Scenario = make({"seed": 63, "fixture": FixtureMap.from_ascii(ROWS)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	var cat: MinerHandle = s.add_miner("cat", s.fixture.spot("c"))
	ann.at(0).face(0.0)
	s.run.light.grid.add_spot(0, s.fixture.spot("c"), 0.30, 0)
	s.run.miner_state.enter_caught(cat.entity_id, &"man_trap", 1)
	s.run.miner_state.make_hurt(cat.entity_id, "test")
	s.run.miner_state.set_rock_touched(cat.entity_id, 100000)
	s.step(4)
	var identity: Dictionary = _record_of(s, ann)
	assert_eq(int(Variants.number(identity["level"])), 2, "Ann sees Cat at 0.30: identity")
	var cues: int = int(Variants.number(identity["cues"]))
	assert_true((cues & MinerCues.HELD_JAWS) != 0, "held in the jaws")
	assert_true((cues & MinerCues.LIMP) != 0, "and limping")
	# The same scene with Cat in the fringe (0.20): a bare token.
	var t: Scenario = make({"seed": 63, "fixture": FixtureMap.from_ascii(ROWS)})
	var ann2: MinerHandle = t.add_miner("ann", t.fixture.spot("a"), {"facing_deg": 0.0})
	var cat2: MinerHandle = t.add_miner("cat", t.fixture.spot("c"))
	ann2.at(0).face(0.0)
	t.run.light.grid.add_spot(0, t.fixture.spot("c"), 0.20, 0)
	t.run.miner_state.enter_caught(cat2.entity_id, &"man_trap", 1)
	t.step(4)
	var token: Dictionary = _record_of(t, ann2)
	assert_eq(int(Variants.number(token["level"])), 1, "at 0.20: a token")
	assert_false(token.has("cues"), "a token carries no state")
	# The owning client: its own life state and capabilities, nothing more.
	var own: Dictionary = s.client(cat).records_at(s.run.tick).own
	var flags: int = int(Variants.number(own["flags"]))
	assert_eq((flags >> 4) & 7, MinerTransitions.Life.CAUGHT, "Cat knows she is caught")
	assert_eq((flags >> 7) & 1, 0, "and cannot move")
	assert_eq((flags >> 8) & 1, 1, "but can turn")
	assert_eq(own.keys(), ["position", "facing", "gait", "speed_q", "flags", "stamina_q", "lamp_radius", "flame"],
		"no overlay, mark, timer or cause (the flame byte is VIS-08's real flame states)")


func _record_of(s: Scenario, viewer: MinerHandle) -> Dictionary:
	var entities: Dictionary = s.client(viewer).entities_visible(s.run.tick)
	assert_eq(entities.size(), 1)
	return Variants.dict(entities.values()[0])
