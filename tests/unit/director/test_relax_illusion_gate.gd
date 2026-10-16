extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-02's illusion gate (Gameplay §9.2, §10.3): no illusion plays in a relax, the apex's included;
## one playing when the relax begins is cut (illusions_cut), and none starts until the relax ends.
## A stand-in for CRT-10's illusion stage (stage 14) keeps the rule as CRT-10 will: it starts one
## only while illusions_allowed(), and ends one playing when told.

const D = preload("res://tests/scenario/director/draught_world.gd")


## Plays one illusion after another, each `length` ticks, whenever the gate allows.
class IllusionStub:
	extends SimSystem
	var relax: RelaxRules = null
	var length: int = 60
	var playing_until: int = -1
	var started: Array[int] = []
	var cut: Array[int] = []

	func stage() -> int:
		return StageTable.Stage.ILLUSIONS

	func order() -> int:
		return 0

	func system_name() -> String:
		return "illusion_stub"

	func bind(r: RelaxRules) -> void:
		relax = r
		relax.illusions_cut.connect(_on_cut)

	func playing(run: RunState) -> bool:
		return run.tick < playing_until

	func tick(run: RunState) -> void:
		if not playing(run) and relax.illusions_allowed():
			playing_until = run.tick + length
			started.append(run.tick)

	func _on_cut() -> void:
		if playing_until >= 0:
			cut.append(playing_until)
		playing_until = -1


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	WorldCoords.ring_override = -1


func test_illusions_allowed_by_phase_never_in_a_relax() -> void:
	var s: Scenario = make({"seed": 1301, "fixture": D.hall(), "director": true})
	var cycle: DraughtCycle = s.run.draught.cycle
	assert_true(s.run.relax.illusions_allowed(), "in a build")
	cycle.phase = DraughtCycle.Phase.PEAK
	assert_true(s.run.relax.illusions_allowed(), "in a peak")
	D.force_relax(s, true)
	assert_false(s.run.relax.illusions_allowed(), "never in a relax")
	s.run.creatures.gate.apex_on = func() -> bool: return true
	assert_false(s.run.relax.illusions_allowed(), "the apex's included")


func test_one_playing_is_cut_and_none_starts_until_the_relax_ends() -> void:
	var stub: IllusionStub = IllusionStub.new()
	var s: Scenario = make({"seed": 1302, "fixture": D.hall(), "director": true, "systems": [stub]})
	stub.bind(s.run.relax)
	var ids: Array[int] = D.crew(s, ["ann"] as Array[String], ["a"] as Array[String])
	D.stand_in(s)
	s.step(10)
	assert_true(stub.playing(s.run), "an illusion plays in the build")
	# A peak, then the relax.
	WorldCoords.ring_override = 3
	D.set_value(s, ids[0], 70.0)
	var relaxes: Array[int] = []
	s.run.draught.cycle.relax_begun.connect(func(_n: int, _r: int) -> void: relaxes.append(s.run.tick))
	while relaxes.is_empty():
		s.step(1)
	WorldCoords.ring_override = -1
	assert_eq(stub.cut.size(), 1, "the one playing was cut at the relax's start")
	assert_false(stub.playing(s.run))
	var before: int = stub.started.size()
	while s.run.draught.cycle.in_relax():
		s.step(1)
	assert_eq(stub.started.size(), before, "none started in the relax")
	s.step(2)
	assert_gt(stub.started.size(), before, "they play again once it ends")
