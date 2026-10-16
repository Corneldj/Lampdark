extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-02: the seam ticks as it cools (Gameplay §10.3). Through a relax every miner below hears
## SND-03's seam_cooling bed layer, from the relax's start to its end; inside base camp it does not
## play (Proposed). A miner who walks out mid-relax starts hearing it. On GEN-03's grey box, whose
## base camp LFT-01 runs.

const D = preload("res://tests/scenario/director/draught_world.gd")
const MAP: String = "m1_greybox"


func before_all() -> void:
	assert_true(Tuning.load_server())


func _seam(h: MinerHandle) -> Array[bool]:
	var out: Array[bool] = []
	for raw: Variant in h.connection.ambient_cues:
		var cue: Dictionary = raw
		if StringName(str(cue["layer"])) == AmbientMessages.SEAM_COOLING:
			out.append(Variants.flag(cue["start"]))
	return out


func test_heard_below_through_the_relax_not_in_base_camp() -> void:
	var s: Scenario = make({"seed": 1801, "fixture": MAP, "director": true})
	FixedMapLoader.populate(s.run, MAP, true, true)
	var inside: Array = Basecamp.inside_tiles(FixedMapLoader.run_seed(FixedMapLoader.manifest(MAP)),
		FixedMapLoader.blind_side(FixedMapLoader.manifest(MAP))).keys()
	inside.sort()
	var home: Vector2i = inside[0]
	var ann: MinerHandle = s.add_miner("ann", Vector2i(31, 14)) # out on the east arm
	var ben: MinerHandle = s.add_miner("ben", home)
	D.stand_in(s)
	s.step(10)
	assert_true(s.run.base_camp.is_inside(ben.entity_id), "Ben is inside base camp")
	assert_false(s.run.base_camp.is_inside(ann.entity_id), "Ann is below")
	assert_eq(_seam(ann), [] as Array[bool], "no ticking in a build")
	D.force_relax(s, true)
	s.step(5)
	assert_eq(_seam(ann), [true] as Array[bool], "the seam ticks for Ann below")
	assert_eq(_seam(ben), [] as Array[bool], "not inside base camp")
	# Ben walks out into the mine.
	s.run.movement.place(s.run, ben.entity_id, Vector2(31.5, 15.5))
	s.step(5)
	assert_eq(_seam(ben), [true] as Array[bool], "he hears it once he is below")
	D.force_relax(s, false)
	s.step(5)
	assert_eq(_seam(ann), [true, false] as Array[bool], "it stops when the relax ends")
	assert_eq(_seam(ben), [true, false] as Array[bool])
