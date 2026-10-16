class_name BaseCampState
extends SimSystem
## LFT-01: base camp's state. Who is inside (miners, Hands and Bess, recomputed each tick from
## GEN-02's inside set), whether it is sealed (all three gates shut, read from the gates' tiles),
## the emergency light, the fixtures and the power they wait for. Nothing here makes base camp
## safe: only its brick, its light and its shut gates do, through the systems that read them.
## Server-only: the sealed state, occupancy and power never reach a client.

signal sealed_changed(sealed: bool)
signal entered(entity: int)
signal left(entity: int)

const OCCUPANT_KINDS: Array[WorldIds.EntityKind] = [WorldIds.EntityKind.MINER, WorldIds.EntityKind.BESS]

var seed_value: int = 0
var side: int = -1
var inside_tiles: Dictionary = {}
var gates: Array[Dictionary] = []
## LFT-02's gates (their levers, flips, spill and auto-close).
var gate_system: GateSystem = null
var lights: EmergencyLights = EmergencyLights.new()
var first_lamp: FirstLamp = null
var medbay: Medbay = Medbay.new()
var bench: Bench = Bench.new()
var relighter: Relighter = Relighter.new()
var rack: BatteryRack = BatteryRack.new()
## LFT-05's power_on (an FND-08 console toggle stands in until then). Never in M1.
var powered: bool = false
var occupants: Dictionary = {}
var sealed: bool = false


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 50


func system_name() -> String:
	return "BaseCampState"


## Creates, registers and installs the run's base camp state (GEN-03 and the server's map load
## call it once base camp's cell is committed).
static func attach(run: RunState, run_seed: int, blind_side: int, fresh: bool) -> BaseCampState:
	var state: BaseCampState = BaseCampState.new()
	run.add_system(state)
	state.gate_system = GateSystem.new()
	run.add_system(state.gate_system)
	state.install(run, run_seed, blind_side, fresh)
	run.base_camp = state
	if run.audio != null:
		run.audio.follow_base_camp(run, state)
	return state


## The run-start check (debug and CI builds): inside base camp lie only miners, the first lamp,
## Bess (Night Shift) and the gates' levers. Returns what else it finds.
func run_start_check(run: RunState) -> Array[String]:
	var errors: Array[String] = []
	for id: int in run.registry.ids():
		var e: SimEntity = run.registry.get_entity(id)
		if not inside_tiles.has(Vector2i(floori(e.position.x), floori(e.position.y))):
			continue
		var allowed: bool = e.kind == WorldIds.EntityKind.MINER or e.kind == WorldIds.EntityKind.BESS \
			or e.kind == WorldIds.EntityKind.LEVER or (first_lamp != null and id == first_lamp.entity)
		if not allowed:
			errors.append("%s %d lies inside base camp at %s" % [WorldIds.EntityKind.find_key(e.kind), id, e.position])
	return errors


## Called when base camp's cell is loaded. `fresh`: run creation (the first lamp is hung and every
## gate shut), never a resume (GateSystem.restore() puts the gates back then).
func install(run: RunState, run_seed: int, blind_side: int, fresh: bool) -> void:
	seed_value = run_seed
	side = blind_side
	inside_tiles = Basecamp.inside_tiles(seed_value, side)
	gates = Basecamp.gate_specs(seed_value, side)
	if gate_system != null:
		gate_system.install(run, gates, fresh)
	if run.light != null:
		lights.install(run, inside_tiles)
	medbay.install(seed_value, side)
	bench.install(seed_value, side)
	relighter.install(seed_value, side)
	rack.install(seed_value, side)
	if fresh:
		var hook: Vector2i = Basecamp.fixture(seed_value, "lamp_hook", side)[0]["position"]
		first_lamp = FirstLamp.spawn(run, hook)
	sealed = _all_shut(run)
	if run.crew != null:
		run.crew.is_sealed_inside = func(entity: int) -> bool: return sealed and occupants.has(entity)


func is_inside(entity: int) -> bool:
	return occupants.has(entity)


func is_sealed() -> bool:
	return sealed


## Every flame inside (CRT-06's hatch smothers them; the emergency lamps are not flames).
func flames_inside(run: RunState) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	if run.light == null:
		return out
	for id: int in run.light.grid.flame_sources(Rect2(0, 0, WorldIds.CELL_TILES, WorldIds.CELL_TILES)):
		out.append(id)
	return out


func medbay_tables() -> Array[Vector2i]:
	return medbay.tables


func cupboard() -> Medbay:
	return medbay


func bench_tile() -> Vector2i:
	return bench.tile


func tick(run: RunState) -> void:
	var now: Dictionary = {}
	var ids: Array = Array(run.registry.ids())
	ids.sort()
	for raw: Variant in ids:
		var e: SimEntity = run.registry.get_entity(int(Variants.number(raw)))
		if not OCCUPANT_KINDS.has(e.kind):
			continue
		if inside_tiles.has(Vector2i(floori(e.position.x), floori(e.position.y))):
			now[e.id] = true
	for raw: Variant in ids:
		var id: int = int(Variants.number(raw))
		if now.has(id) and not occupants.has(id):
			entered.emit(id)
		elif occupants.has(id) and not now.has(id):
			left.emit(id)
	occupants = now
	var shut: bool = _all_shut(run)
	if shut != sealed:
		sealed = shut
		sealed_changed.emit(sealed)
	relighter.tick(run)
	rack.tick(powered)


func _all_shut(run: RunState) -> bool:
	if run.mine == null or gates.is_empty():
		return false
	for g: Dictionary in gates:
		var tiles: Array = g["tiles"]
		var t: Vector2i = tiles[0]
		if run.mine.native.effective_material(t) != WorldIds.TileMaterial.STEEL:
			return false
	return true


func write_state(writer: SimStateWriter) -> void:
	writer.put_bool(sealed)
	writer.put_bool(powered)
	writer.put_i64(occupants.size())
	writer.put_i64(medbay.kits)


## NET-09: power, the medbay's kits and tables, the battery rack (gates are GEN-13's records).
func save_state() -> Dictionary:
	return {"powered": powered, "kits": medbay.kits, "tables": medbay.bodies.duplicate(), "rack": rack.slots.duplicate()}


func load_state(_r: RunState, state: Dictionary) -> void:
	powered = Variants.flag(state.get("powered", powered))
	medbay.kits = int(Variants.number(state.get("kits", medbay.kits)))
	medbay.bodies = Variants.dict(state.get("tables", {})).duplicate()
	rack.slots = Variants.dict(state.get("rack", {})).duplicate()
