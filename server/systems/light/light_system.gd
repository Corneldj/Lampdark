class_name LightSystem
extends SimSystem
## The light grid's tick glue (VIS-02): pass 1 in stage 6 (after miners and the world, so
## creatures perceive this tick's light), pass 2 in stage 10 (regions changed by creatures,
## pacing and falls). Server-only: the grid and its registry never reach a client, and the
## illusion stage never touches them (tools/build/check_module_deps.sh).

## The second pass, in stage 10.
class SecondPass:
	extends SimSystem
	var light: LightSystem

	func _init(owner_system: LightSystem) -> void:
		light = owner_system

	func stage() -> int:
		return StageTable.Stage.LIGHT_PASS_2

	## After VIS-08's flame states (order 5), whose radius modifiers it lays on the grid.
	func order() -> int:
		return 10

	func system_name() -> String:
		return "light_pass_2"

	func tick(_run: RunState) -> void:
		light.grid.update()


var grid: LbLightGrid = LbLightGrid.new()
var mine: Mine
var tick_hz: float = 20.0
## CRT-04: a caster of the light-seeing creatures' own (no observers, never a miner's seen set).
var _sight: LbVision = null


func _init(server_mine: Mine) -> void:
	mine = server_mine
	grid.attach(mine.native)
	grid.set_params(Tuning.f(&"light.core_fraction"), Tuning.f(&"light.core_value"), Tuning.f(&"light.edge_value"),
		Tuning.f(&"light.cap"), Tuning.i(&"light.value_scale"))
	tick_hz = Tuning.f(&"net.tick_hz")
	mine.native.cell_loaded.connect(grid.on_cell_loaded)
	mine.native.cell_unloading.connect(grid.on_cell_unloading)
	mine.native.tiles_changed.connect(grid.on_tiles_changed)


func stage() -> int:
	return StageTable.Stage.LIGHT_PASS_1


func order() -> int:
	return 0


func system_name() -> String:
	return "light_pass_1"


## Registers both passes into a run.
func register_into(run: RunState) -> void:
	run.add_system(self)
	run.add_system(SecondPass.new(self))


func tick(_run: RunState) -> void:
	grid.begin_tick(tick_hz)
	grid.update()


## Light in [0, 1] at a tile, for GDScript rules that prefer floats.
func light_at(tile: Vector2i) -> float:
	return grid.value(tile) / float(Tuning.i(&"light.value_scale"))


## CRT-04: what a light-seeing creature sees from a tile: tiles in line of sight (no cone) within
## `range`, lit to `min_light` or glowing with egg-glow, without the `excluded` sources; flattened
## [x, y, thousandths, source, colour] per tile (LbVision.lit_in_sight).
func lit_in_sight(from: Vector2i, range: float, min_light: float, excluded: PackedInt64Array) -> PackedInt64Array:
	if _sight == null:
		_sight = LbVision.new()
		_sight.attach(mine.native, grid)
	return _sight.lit_in_sight(from, range, min_light, excluded)

