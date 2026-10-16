class_name MineLayouts
extends RefCounted
## GEN-05: the run's layout deriver (LbLayouts) set up from data: the template pack the run names
## (data/templates/set.json's current set unless a resumed run names its own, §12.6), the socket
## numbers and GEN-06's biome table from tuning, and base camp's forced sockets (GEN-02). GEN-11
## derives cells from it on its workers (cell_data). Server-only: no socket, layout, biome or seed
## reaches a client.

const TEMPLATES: String = "res://data/templates"


## The deriver for a run, or null (with an error) if its template pack cannot be read.
static func for_run(run_seed: int, set_version: String = "") -> LbLayouts:
	var version: String = set_version
	if version.is_empty():
		var current: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(TEMPLATES.path_join("set.json"))))
		version = str(current.get("set_version", ""))
	var layouts: LbLayouts = LbLayouts.new()
	var pack_path: String = TEMPLATES.path_join("packs/%s.lbtp" % version)
	if version.is_empty() or not layouts.load_pack(FileAccess.get_file_as_bytes(pack_path)):
		push_error("MineLayouts: no template pack %s" % pack_path)
		return null
	configure(layouts, run_seed)
	return layouts


## Sets a deriver's numbers from tuning (sockets, rerolls, GEN-06's biomes) and base camp's gates.
static func configure(layouts: LbLayouts, run_seed: int) -> void:
	layouts.configure(run_seed, {
		"open_probability": Tuning.f(&"mine.edge_open_probability"),
		"offsets": Tuning.list_i(&"mine.socket_offsets_tiles"),
		"widths": Tuning.list_i(&"mine.socket_widths_tiles"),
		"reroll_limit": roundi(Tuning.f(&"mine.validator_max_rerolls")),
		"biomes": biome_table(),
	})
	var gates: Dictionary = Basecamp.gate_sockets(run_seed)
	for side: String in Basecamp.SIDES:
		layouts.force_socket(Vector2i.ZERO, side, Variants.dict(gates[side]))


## GEN-06's table from tuning: each ring's weights in their mapping order, each biome's socket
## widths, and the ring starts.
static func biome_table() -> Dictionary:
	var rings: Array = []
	var ring: int = 0
	while Tuning.current.has_key(StringName("mine.biome_weights_ring%d" % ring)):
		var weights: Dictionary = Tuning.table(StringName("mine.biome_weights_ring%d" % ring))
		var pairs: Array = []
		for biome: Variant in weights.keys():
			pairs.append([str(biome), float(Variants.number(weights[biome]))])
		rings.append(pairs)
		ring += 1
	var widths: Dictionary = {}
	var lo: Dictionary = Tuning.table(&"mine.biome_socket_widths_min")
	var hi: Dictionary = Tuning.table(&"mine.biome_socket_widths_max")
	for biome: Variant in lo.keys():
		widths[str(biome)] = [int(Variants.number(lo[biome])), int(Variants.number(hi.get(biome, lo[biome])))]
	return {"rings": rings, "widths": widths, "ring_bounds": Tuning.list_i(&"depth.ring_start_tiles")}


## The cell to commit at `cell`: its layout, with GEN-02's brick arches on the cells base camp's
## gate roads enter (GEN-06), or base camp itself at (0, 0). Null when no template fits (GEN-12
## rerolls).
static func cell_data(layouts: LbLayouts, run_seed: int, cell: Vector2i, reroll: int = 0) -> LbCellData:
	var layout: Dictionary = layouts.derive(cell, reroll)
	if not Variants.flag(layout.get("ok", false)):
		return null
	if Variants.flag(layout["base_camp"]):
		return Basecamp.cell_data(run_seed)
	var data: LbCellData = layout["cell"]
	if gate_cells(run_seed).has(cell):
		arch(data, run_seed, cell)
	return data


## The cells base camp's three gate roads run into.
static func gate_cells(run_seed: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for g: Dictionary in Basecamp.gate_specs(run_seed):
		var outward: Vector2i = g["outward"]
		out.append(outward)
	return out


## GEN-02's arch overlay on a gate cell: the solid tiles beside the gate road's first 10 tiles of
## path turn to brick (zones are unchanged: only rock becomes brick).
static func arch(data: LbCellData, run_seed: int, cell: Vector2i) -> void:
	var rows: PackedStringArray = CellFile.rows_of(data)
	var arched: PackedStringArray = Basecamp.apply_gate_arches(run_seed, cell, rows)
	for y: int in WorldIds.CELL_TILES:
		for x: int in WorldIds.CELL_TILES:
			if arched[y][x] != rows[y][x]:
				var tile: Dictionary = data.get_tile(Vector2i(x, y))
				data.set_tile(Vector2i(x, y), WorldIds.TileMaterial.BRICK, 0, int(Variants.number(tile["zone"])))
