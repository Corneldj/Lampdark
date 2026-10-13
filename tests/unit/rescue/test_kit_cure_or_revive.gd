extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-02: one use revives or cures, never both. On an infested miner on a table both are offered
## and only the chosen one happens; an unconscious miner on the floor is offered no Revive; a dead
## body on a table is offered neither. A cure with nothing to cure completes and spends nothing.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const M = preload("res://tests/unit/rescue/medbay_world.gd")

## A stand-in for HAZ-06: entity -> mark.
var _marks: Dictionary = {}


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int, on_table: bool) -> Array:
	_marks = {}
	var s: Scenario = make({"seed": run_seed, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var table: Vector2i = camp.medbay_tables()[0]
	var spot: Vector2i = M.beside(s, table)
	var ann: MinerHandle = s.add_miner("ann", spot)
	var bob: MinerHandle = s.add_miner("bob", spot)
	s.step(1)
	M.give_kit(s, ann.entity_id)
	s.run.revival.cure = func(_run: RunState, target: int) -> StringName:
		var mark: StringName = StringName(str(_marks.get(target, "")))
		_marks.erase(target)
		return mark
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	if on_table:
		M.lay(s, bob.entity_id, table)
		s.step(1)
	return [s, ann, bob]


func _offered(s: Scenario, ann: MinerHandle, bob: MinerHandle) -> Array[String]:
	var out: Array[String] = []
	for id: String in s.run.ring.registry.offered(s.run, ann.entity_id, bob.entity_id):
		if id == "cure" or id == "revive":
			out.append(id)
	return out


func test_floor_offers_no_revive() -> void:
	var parts: Array = _setup(1, false)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	assert_eq(_offered(s, ann, bob), ["cure"] as Array[String])


func test_dead_on_a_table_offers_neither() -> void:
	var parts: Array = _setup(2, true)
	var s: Scenario = parts[0]
	var bob: MinerHandle = parts[2]
	var ann: MinerHandle = parts[1]
	s.run.miner_state.kill(bob.entity_id, "test")
	s.step(2)
	assert_eq(_offered(s, ann, bob), [] as Array[String])


func test_infested_on_a_table_revive_only() -> void:
	var parts: Array = _setup(3, true)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	_marks[bob.entity_id] = "eggs"
	assert_eq(_offered(s, ann, bob), ["cure", "revive"] as Array[String], "both offered")
	M.start(s, ann, bob.entity_id, KitUse.Mode.REVIVE, 110)
	s.step(105)
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UPRIGHT, "revived")
	assert_eq(str(_marks.get(bob.entity_id, "")), "eggs", "the mark stays: never both")
	assert_eq(M.kits(s, ann.entity_id), 0, "one kit")


func test_infested_on_a_table_cure_only() -> void:
	var parts: Array = _setup(4, true)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	_marks[bob.entity_id] = "eggs"
	var used: Array = []
	s.run.revival.kit_used.connect(func(_u: int, _t: int, kind: StringName, mark: StringName) -> void: used.append([kind, mark]))
	M.start(s, ann, bob.entity_id, KitUse.Mode.CURE, 110)
	s.step(105)
	assert_false(_marks.has(bob.entity_id), "cured")
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UNCONSCIOUS, "and not revived")
	assert_eq(M.kits(s, ann.entity_id), 0)
	assert_eq(used, [[&"cure", &"eggs"]])


func test_cure_with_nothing_to_cure_spends_nothing() -> void:
	var parts: Array = _setup(5, false)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var a: TimedAction = M.start(s, ann, bob.entity_id, KitUse.Mode.CURE, 110)
	s.step(105)
	assert_true(a.done, "the 5 s completes")
	assert_eq(M.kits(s, ann.entity_id), 1, "nothing spent")
	assert_eq(s.run.revival.uses.size(), 0)


func test_self_cure_from_the_belt() -> void:
	var parts: Array = _setup(6, false)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	_marks[ann.entity_id] = "cough"
	ann.at(s.run.tick).select_slot(0).hold(InputRecord.HOLD_USE, 110)
	s.step(108)
	assert_false(_marks.has(ann.entity_id), "cured herself")
	assert_eq(M.kits(s, ann.entity_id), 0)
