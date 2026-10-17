extends GutTest
## MOD-03 (GDD §15.9, §15.10): the same seed and options make a byte-identical run header: the plan
## (GEN-08's, which records the list, the solo rule, the draw, the staging and the hard variant), the
## repair list and the draw. A golden of those bytes holds on Windows and Linux alike (FND-04's CI runs
## this on both). Made on GEN-07's road pack with the plan's numbers at the generator's own defaults,
## so only a generator or list change moves a golden (re-record from the digests the test prints).

const Specs = preload("res://tests/unit/gen/template_specs.gd")
## SHA-256 over the plan bytes, the list's jobs and the draw.
const GOLDEN_PAIR: String = "9a08f77688f1f517906fae5b41fb7fdb1ca628c690d81cbce04147e27fddb14b"
const GOLDEN_STAGED_ONE: String = "2f38f1f1d374de2f56fd49a74ad2a2a98233846dbe6e3323a7d0224bc16413ab"


func before_all() -> void:
	assert_true(Tuning.load_server())


func _options(list: RunOptions.List, hard: String = "", hands: bool = false) -> RunOptions:
	var o: RunOptions = RunOptions.defaults(ServerConfig.Mode.FRIENDS)
	o.list = list
	o.hard_variant = hard
	o.hands_in_empty_places = hands
	return o


class Made:
	extends RefCounted
	var plan: PackedByteArray = PackedByteArray()
	var jobs: PackedStringArray = PackedStringArray()
	var draw: PackedStringArray = PackedStringArray()
	var staging: String = ""
	var kind: int = 0
	var solo: bool = false
	var hard: String = ""

	func digest() -> String:
		var ctx: HashingContext = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(plan)
		ctx.update(("|jobs:" + ",".join(jobs)).to_utf8_buffer())
		ctx.update(("|draw:" + ",".join(draw)).to_utf8_buffer())
		return ctx.finish().hex_encode()


## A run created on its own server state, and its plan fixed.
func _made(run_seed: int, options: RunOptions, humans: int, brigade_runs: Array[int]) -> Made:
	var run: RunState = RunState.create(run_seed, ServerConfig.Mode.FRIENDS, false)
	ServerSystems.install(run, ServerNet.new(InProcessTransport.new(InProcessTransport.Hub.new()), 5))
	assert_eq(RunSetup.create(run, options, humans, brigade_runs, RunSetup.unlocked_variants(true)), "")
	var layouts: LbLayouts = LbLayouts.new()
	assert_true(layouts.load_pack(Specs.road_pack()))
	MineLayouts.configure(layouts, run_seed)
	var plan: Dictionary = RunPlan.fix(layouts, run, PackedByteArray(), {"data_version": "test", "tuning": {}})
	assert_false(plan.is_empty(), "the plan was made")
	var m: Made = Made.new()
	m.plan = run.header.plan
	for j: StringName in run.repair.list.jobs:
		m.jobs.append(String(j))
	m.draw = run.header.draw
	m.staging = run.header.staging
	m.kind = run.repair.list.kind
	m.solo = Variants.flag(run.header.rule_flags["solo_rules"])
	m.hard = str(plan.get("hard_variant", ""))
	return m


func test_the_same_seed_and_options_make_the_same_header() -> void:
	var a: Made = _made(90210, _options(RunOptions.List.STANDARD, "dead_lines", true), 2, [5, 9] as Array[int])
	var b: Made = _made(90210, _options(RunOptions.List.STANDARD, "dead_lines", true), 2, [5, 9] as Array[int])
	assert_eq(a.plan, b.plan, "the plan byte for byte")
	assert_eq(a.jobs, b.jobs, "the list")
	assert_eq(a.draw, b.draw, "the draw")
	assert_eq(a.hard, "dead_lines", "the hard variant is in the plan")
	gut.p("pair: %s (%d plan bytes, jobs %s)" % [a.digest(), a.plan.size(), a.jobs])
	if not GOLDEN_PAIR.is_empty():
		assert_eq(a.digest(), GOLDEN_PAIR, "the golden: the same bytes on Windows and Linux")
	var other: Made = _made(90211, _options(RunOptions.List.STANDARD, "dead_lines", true), 2, [5, 9] as Array[int])
	assert_ne(other.plan, a.plan, "another seed, another plan")


func test_a_staged_lobby_of_one_makes_the_same_header() -> void:
	var a: Made = _made(4401, _options(RunOptions.List.FULL), 1, [0] as Array[int])
	var b: Made = _made(4401, _options(RunOptions.List.FULL), 1, [0] as Array[int])
	assert_eq(a.staging, "1")
	assert_eq(a.kind, RepairList.Kind.SHORT, "staged run 1: the Short list")
	assert_true(a.solo, "a lobby of one: the solo rules, in the plan too")
	assert_eq(a.plan, b.plan)
	assert_eq(a.jobs, b.jobs)
	gut.p("staged one: %s (%d plan bytes, jobs %s)" % [a.digest(), a.plan.size(), a.jobs])
	if not GOLDEN_STAGED_ONE.is_empty():
		assert_eq(a.digest(), GOLDEN_STAGED_ONE, "the golden: the same bytes on Windows and Linux")
