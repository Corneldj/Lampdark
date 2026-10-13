extends GutTest
## Shutting a barrier lengthens a path within the same tick (GEN-01).


class DoorSwitch:
	extends SimSystem
	var mine: Mine
	var shut_at: int

	func _init(m: Mine, at_tick: int) -> void:
		mine = m
		shut_at = at_tick

	func stage() -> int:
		return StageTable.Stage.WORLD

	func order() -> int:
		return 0

	func tick(run: RunState) -> void:
		if run.tick == shut_at:
			mine.native.set_barrier(Vector2i(0, 0), 1, false)


class Prober:
	extends SimSystem
	var mine: Mine
	var distances: Dictionary = {}

	func _init(m: Mine) -> void:
		mine = m

	func stage() -> int:
		return StageTable.Stage.CREATURES

	func order() -> int:
		return 0

	func tick(run: RunState) -> void:
		distances[run.tick] = mine.path_distance(Vector2i(1, 1), Vector2i(18, 1)).distance


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_shutting_the_door_lengthens_the_path_in_the_same_tick() -> void:
	var mine: Mine = Mine.new()
	var cell: LbCellData = CellFile.load_file("res://data/maps/test/cell_0_0.json")
	mine.queue_commit(cell)
	var run: RunState = RunState.create(5, ServerConfig.Mode.FRIENDS, false)
	run.add_system(MineCommitSystem.new(mine))
	run.add_system(DoorSwitch.new(mine, 3))
	var prober: Prober = Prober.new(mine)
	run.add_system(prober)
	mine.native.set_barrier(Vector2i(0, 0), 1, true)  # ignored: the cell is not committed yet
	run.run_tick()
	mine.native.set_barrier(Vector2i(0, 0), 1, true)  # open the door after commit
	for _i: int in 4:
		run.run_tick()
	assert_eq(Variants.number(prober.distances[2]), 17.0, "door open: straight through")
	assert_eq(Variants.number(prober.distances[3]), 25.0, "shut in stage 4, longer in stage 7 of the same tick")
	assert_eq(Variants.number(prober.distances[4]), 25.0)
