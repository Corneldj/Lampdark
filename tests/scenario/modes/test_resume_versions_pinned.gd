extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-05 (Gameplay §12.6; GDD §15.10): a resumed run uses the saved generator, template and bundle
## versions, even when the build carries newer ones. A generated run records the generator and the
## template set its plan was made with (RunPlan), its saves name them in the plain header, and this
## build accepts a save of its own generator on any set it still carries (GEN-04 keeps the previous
## one): the resume loads that set, never the newest, and derives the same cells from it. A save
## naming a generator or a set this build lacks is refused in plain words.

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const OLD: String = "09788b712cda32dd"


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_run_records_its_versions() -> void:
	var run: RunState = RunState.create(5041, ServerConfig.Mode.FRIENDS, false)
	ServerSystems.install(run, ServerNet.new(InProcessTransport.new(InProcessTransport.Hub.new()), 5))
	var layouts: LbLayouts = LbLayouts.new()
	assert_true(layouts.load_pack(Specs.road_pack()))
	MineLayouts.configure(layouts, 5041)
	assert_false(RunPlan.fix(layouts, run, PackedByteArray(), {"data_version": "test", "tuning": {}}).is_empty())
	assert_eq(run.header.generator, "gen:%d" % LbLayouts.generator_version(), "the generator its plan was made with")
	assert_eq(run.header.templates, layouts.set_version(), "and the template set")
	assert_eq(Saves.generator_version(run), run.header.generator, "as its saves name them")
	assert_eq(Saves.templates_version(run), run.header.templates)
	var again: RunState = RunState.create(5041, ServerConfig.Mode.FRIENDS, false)
	ServerSystems.install(again, ServerNet.new(InProcessTransport.new(InProcessTransport.Hub.new()), 5))
	var resumed: LbLayouts = LbLayouts.new()
	assert_true(resumed.load_pack(Specs.road_pack()))
	MineLayouts.configure(resumed, 5041)
	assert_false(RunPlan.fix(resumed, again, run.header.plan).is_empty(), "a resume's saved plan")
	assert_eq(again.header.templates, run.header.templates, "records the same versions")


func test_the_saved_set_is_loaded_not_the_newest() -> void:
	var current: String = str(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(MineLayouts.TEMPLATES.path_join("set.json")))).get("set_version", ""))
	assert_ne(current, OLD, "the build's newest set is another")
	var header: Dictionary = {"generator": "gen:%d" % LbLayouts.generator_version(), "templates": OLD, "mode": ServerConfig.Mode.FRIENDS,
		"bundle": Tuning.content_hash("server")}
	assert_eq(SaveResume.refusal(header), "", "this build resumes a save on the previous set")
	var began: LbLayouts = MineLayouts.for_run(5042, OLD)
	var resumed: LbLayouts = MineLayouts.for_run(5042, str(header["templates"]))
	assert_not_null(resumed)
	assert_eq(resumed.set_version(), OLD, "the saved set loaded, not the newest")
	var src: String = FileAccess.get_file_as_string("res://server/server_main.gd")
	assert_true(src.contains("MineLayouts.for_run(run.header.run_seed, templates if templates != \"none\" else \"\", config.template_pack)"),
		"server_main loads the save's set")
	for cell: Vector2i in [Vector2i(1, 0), Vector2i(-2, 3), Vector2i(4, -1)]:
		var first: Dictionary = began.derive(cell, 0)
		var later: Dictionary = resumed.derive(cell, 0)
		assert_eq(Variants.whole(later.get("digest", 0)), Variants.whole(first.get("digest", 0)), "the same cell %s" % cell)
	var lacking: Dictionary = header.duplicate()
	lacking["templates"] = "ffffffffffffffff"
	assert_ne(SaveResume.refusal(lacking), "", "a set the build lacks")
	assert_eq(SaveResume.refusal(lacking, PackedStringArray(["ffffffffffffffff"])), "", "unless this process holds it (--template-pack)")
	var other: Dictionary = header.duplicate()
	other["generator"] = "gen:%d" % (LbLayouts.generator_version() - 1)
	assert_ne(SaveResume.refusal(other), "", "another generator")
	assert_false(SaveResume.refusal(other).contains("gen:%d" % LbLayouts.generator_version()), "plain words")
