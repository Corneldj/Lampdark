extends GutTest
## Same seed and scripted inputs give the same RunState hash after 6,000 ticks (NET-01).

const Systems = preload("res://tests/support/sim_test_systems.gd")
const TICKS: int = 6000


func before_all() -> void:
	assert_true(Tuning.load_server())


func _inputs() -> Dictionary:
	var inputs: Dictionary = {}
	for t: int in range(0, 6000, 400):
		inputs[t] = [["spawn", t % 37, -(t % 23)], ["spawn", -t % 11, t % 5]]
	for t: int in range(250, 6000, 900):
		inputs[t] = [["despawn", t]]
	return inputs


func _run(seed_value: int) -> String:
	var run: RunState = RunState.create(seed_value, ServerConfig.Mode.FRIENDS, false)
	run.add_system(Systems.ScriptedInputs.new(_inputs()))
	run.add_system(Systems.Wander.new())
	run.add_system(Systems.Litter.new())
	var loop: SimLoop = SimLoop.new(run)
	loop.step(TICKS)
	assert_eq(run.tick, TICKS)
	assert_gt(run.registry.count(), 5, "the scenario keeps a crowd")
	return run.state_hash()


func test_same_seed_same_hash() -> void:
	var first: String = _run(0x5EED)
	var second: String = _run(0x5EED)
	assert_eq(first, second)


func test_different_seed_different_hash() -> void:
	assert_ne(_run(0x5EED), _run(0x5EEE))
