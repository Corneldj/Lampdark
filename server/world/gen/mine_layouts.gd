class_name MineLayouts
extends RefCounted
## GEN-05: the run's layout deriver (LbLayouts) set up from data: the template pack the run names
## (data/templates/set.json's current set unless a resumed run names its own, §12.6), the socket
## numbers, GEN-06's biome table and GEN-07's main roads from tuning, and base camp's forced
## sockets (GEN-02). GEN-11 derives cells from it on its workers (cell_data). Server-only: no
## socket, layout, biome or seed reaches a client.

const TEMPLATES: String = "res://data/templates"


## The deriver for a run, or null (with an error) if its template pack cannot be read: the pack
## `set_version` names (a resumed run's), the current set's, or (dev and QA) the file `pack_file`.
static func for_run(run_seed: int, set_version: String = "", pack_file: String = "") -> LbLayouts:
	var version: String = set_version
	if version.is_empty():
		var current: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(TEMPLATES.path_join("set.json"))))
		version = str(current.get("set_version", ""))
	var layouts: LbLayouts = LbLayouts.new()
	var pack_path: String = pack_file if not pack_file.is_empty() else TEMPLATES.path_join("packs/%s.lbtp" % version)
	if (version.is_empty() and pack_file.is_empty()) or not layouts.load_pack(FileAccess.get_file_as_bytes(pack_path)):
		push_error("MineLayouts: no template pack %s" % pack_path)
		return null
	configure(layouts, run_seed)
	return layouts


## Sets a deriver's numbers from tuning (sockets, rerolls, GEN-06's biomes, GEN-12's validator) and
## base camp's gates.
static func configure(layouts: LbLayouts, run_seed: int) -> void:
	layouts.configure(run_seed, {
		"open_probability": Tuning.f(&"mine.edge_open_probability"),
		"offsets": Tuning.list_i(&"mine.socket_offsets_tiles"),
		"widths": Tuning.list_i(&"mine.socket_widths_tiles"),
		"reroll_limit": roundi(Tuning.f(&"mine.validator_max_rerolls")),
		"biomes": biome_table(),
		"main_roads": {
			"spacing": Tuning.i(&"mine.main_road_spacing_cells"),
			"width": roundi(Tuning.f(&"mine.main_road_width_tiles")),
			"offset": roundi(Tuning.f(&"mine.main_road_edge_offset_tiles")),
			"run_min": roundi(Tuning.f(&"mine.main_road_run_min_tiles")),
			"run_max": roundi(Tuning.f(&"mine.main_road_run_max_tiles")),
			"max_ring": Tuning.i(&"mine.main_road_max_ring"),
			"old_fall_probability": Tuning.f(&"mine.old_fall_probability"),
		},
		"poi": poi_params(),
		"place": place_params(),
		"validate": validate_params(run_seed),
	})
	var gates: Dictionary = Basecamp.gate_sockets(run_seed)
	for side: String in Basecamp.SIDES:
		layouts.force_socket(Vector2i.ZERO, side, Variants.dict(gates[side]))


## GEN-09's numbers from tuning: a region's count and the two kinds' rates, footprint tries, each
## kind's rings, the drawn kinds' weights by ring (none in ring 0), the contents tables, found lamps,
## the remains' rolls and Dry Stores.
static func poi_params() -> Dictionary:
	if Tuning.i(&"mine.poi_region_cells") != WorldIds.REGION_CELLS:
		push_error("MineLayouts: mine.poi_region_cells must be FND-07's region size, %d" % WorldIds.REGION_CELLS)
	var weights: Array = [{}]
	var ring: int = 1
	while Tuning.current.has_key(StringName("mine.poi_kind_weights_ring%d" % ring)):
		weights.append(Tuning.table(StringName("mine.poi_kind_weights_ring%d" % ring)))
		ring += 1
	var rings_min: Dictionary = Tuning.table(&"mine.poi_ring_min")
	var contents: Dictionary = {}
	for kind: Variant in rings_min.keys():
		var key: StringName = StringName("mine.poi_contents_%s" % kind)
		if Tuning.current.has_key(key):
			contents[str(kind)] = Tuning.table(key)
	var oil: Vector2 = Tuning.range_f(&"lamp.found_oil_range")
	var notches: Vector2 = Tuning.range_f(&"lamp.found_notches_range")
	return {
		"per_region_min": Tuning.i(&"mine.poi_per_region_min"),
		"per_region_max": Tuning.i(&"mine.poi_per_region_max"),
		"two_probability": Tuning.f(&"mine.poi_two_per_region_probability"),
		"lamp_cabin_regions_per": Tuning.f(&"mine.lamp_cabin_regions_per"),
		"first_aid_regions_per": Tuning.f(&"mine.first_aid_regions_per"),
		"fit_tries": Tuning.i(&"mine.poi_fit_tries"),
		"canary_max_per_run": Tuning.i(&"mine.canary_max_per_run"),
		"min_ring": Tuning.i(&"mine.poi_min_ring"),
		"ring_min": rings_min,
		"ring_max": Tuning.table(&"mine.poi_ring_max"),
		"weights": weights,
		"lair_biome": "old_workings",
		"contents": contents,
		"fuel_cans_min": Tuning.i(&"mine.fuel_store_cans_min"),
		"fuel_cans_max": Tuning.i(&"mine.fuel_store_cans_max"),
		"found_oil": [oil.x, oil.y],
		"found_notches": [notches.x, notches.y],
		"remains_chances": Tuning.table(&"mine.remains_item_chances"),
		"remains_items_max": Tuning.i(&"mine.remains_items_max"),
		"dry_stores_factor": Tuning.f(&"hazards.dry_stores_factor"),
	}


## GEN-10's numbers from tuning (mine.*, traps.*, lamp.*, revolver.*), and DIR-06's staged-run
## tables by stage (the header's staging picks the row).
static func place_params() -> Dictionary:
	var per: Callable = func(key: StringName) -> float: return 1.0 / maxf(1.0, Tuning.f(key))
	var remains_rings: Vector2 = Tuning.range_f(&"mine.remains_rings")
	var oil: Vector2 = Tuning.range_f(&"lamp.found_oil_range")
	var notches: Vector2 = Tuning.range_f(&"lamp.found_notches_range")
	var lamp_per_run: Vector2 = Tuning.range_f(&"mine.electric_lamp_per_run")
	var staged_traps: Array = []
	for v: int in Tuning.list_i(&"modes.staging_no_man_traps_rings_0_1"):
		staged_traps.append(2 if v == 1 else 0)
	return {
		"remains_probability": per.call(&"mine.remains_cells_per"),
		"remains_rings": [remains_rings.x, remains_rings.y],
		"remains_items": Tuning.table(&"mine.remains_item_chances"),
		"remains_items_max": Tuning.i(&"mine.remains_items_max"),
		"found_oil": [oil.x, oil.y],
		"found_notches": [notches.x, notches.y],
		"paraffin_probability": per.call(&"mine.paraffin_single_cells_per"),
		"paraffin_rings": [1, 2],
		"electric_lamp_probability": Tuning.f(&"mine.electric_lamp_probability"),
		"electric_lamp_max": roundi(lamp_per_run.y),
		"electric_lamp_min_ring": Tuning.i(&"mine.electric_lamp_min_ring"),
		"revolver_rounds": Tuning.i(&"revolver.cylinder_rounds"),
		"box_rounds": Tuning.i(&"revolver.box_rounds"),
		"phone_ring12_probability": per.call(&"mine.phone_cells_per_ring12"),
		"phone_beyond_probability": per.call(&"mine.phone_cells_per_beyond"),
		"phones_near_gates": Tuning.i(&"mine.phones_near_gates"),
		"phones_near_gates_path": [Tuning.f(&"mine.phones_near_gates_min_path_tiles"), Tuning.f(&"mine.phones_near_gates_path_tiles")],
		"air_door_probability": Tuning.f(&"mine.air_door_side_passage_probability"),
		"collapse_probability": per.call(&"mine.collapse_cells_per"),
		"collapse_min_from_basecamp": Tuning.f(&"mine.collapse_min_from_basecamp_tiles"),
		"collapse_min_spacing": Tuning.f(&"mine.collapse_min_spacing_tiles"),
		"collapse_min_from_sites": Tuning.f(&"mine.collapse_min_path_from_sites_tiles"),
		"firedamp_ring2_probability": per.call(&"mine.firedamp_cells_per_ring2"),
		"firedamp_beyond_probability": per.call(&"mine.firedamp_cells_per_beyond"),
		"firedamp_black_seam_probability": per.call(&"mine.firedamp_cells_per_black_seam"),
		"blackdamp_probability": per.call(&"mine.blackdamp_old_workings_cells_per"),
		"man_trap_probability": per.call(&"traps.man_trap_cells_per"),
		"man_trap_min_ring": Tuning.i(&"traps.man_trap_min_ring"),
		"staple_pit_probability": per.call(&"mine.staple_pit_old_workings_cells_per"),
		"staple_pit_min_ring": Tuning.i(&"mine.staple_pit_min_ring"),
		"sump_mud_probability": per.call(&"mine.sump_mud_low_road_cells_per"),
		"sump_mud_min_ring": Tuning.i(&"mine.sump_mud_min_ring"),
		"staged_traps_min_ring": staged_traps,
		"staged_roost_min_from_shaft": Tuning.list_i(&"modes.staging_roost_min_tiles"),
		"roosts": [Tuning.i(&"mine.roosts_min"), Tuning.i(&"mine.roosts_max")],
		"roost_max_from_hoard": Tuning.f(&"mine.roost_max_from_hoard_tiles"),
		"coat_heap_near_hoard": Tuning.f(&"mine.coat_heap_near_hoard_tiles"),
		"coat_heap_near_probability": Tuning.f(&"mine.coat_heap_chamber_probability_near"),
		"coat_heap_far_probability": Tuning.f(&"mine.coat_heap_chamber_probability_far"),
		"coat_heaps": [Tuning.i(&"mine.coat_heaps_per_chamber_min"), Tuning.i(&"mine.coat_heaps_per_chamber_max")],
		"rich_rock_per_region": Tuning.i(&"mine.rich_rock_per_region"),
		"rich_rock_min_thickness": roundi(Tuning.f(&"mine.rich_rock_min_thickness_tiles")),
		"landmark_no_repeat_cells": Tuning.i(&"mine.landmark_no_repeat_cells"),
		"landmark_palette": Tuning.i(&"mine.landmark_palette_min"),
		"canary_max": Tuning.i(&"mine.canary_max_per_run"),
	}


## GEN-12's numbers: GEN-04's limits the cell checks share with the template validator (roads,
## chambers, the Tapper's reach, the lair's kind), the placement retries, a spine's replans, and how
## far each of base camp's arches runs into the cell beyond its gate (GEN-02).
static func validate_params(run_seed: int) -> Dictionary:
	return {
		"rules": {
			"road_width_min": roundi(Tuning.f(&"mine.road_width_min_tiles")),
			"road_width_max": roundi(Tuning.f(&"mine.road_width_max_tiles")),
			"chamber_min": roundi(Tuning.f(&"mine.chamber_min_tiles")),
			"chamber_max": roundi(Tuning.f(&"mine.chamber_max_tiles")),
			"chamber_forbidden_width": roundi(Tuning.f(&"mine.chamber_forbidden_width_tiles")),
			"tapper_reach_milli": roundi(Tuning.f(&"tapper.reach_tiles") * 1000.0),
			"lair_kind": "lair",
		},
		"max_retries": roundi(Tuning.f(&"mine.placement_max_retries")),
		"max_replans": roundi(Tuning.f(&"mine.validator_max_rerolls")),
		"arch_reach": Basecamp.arch_reach(run_seed),
	}


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


## The cell to commit at `cell`: its final layout (GEN-12: the reroll the validator accepted, or
## the biome's plain fallback), with GEN-02's brick arches on the cells base camp's gate roads enter
## (GEN-06), or base camp itself at (0, 0). Null when no template and no fallback fits.
static func cell_data(layouts: LbLayouts, run_seed: int, cell: Vector2i) -> LbCellData:
	var layout: Dictionary = layouts.derive_final(cell)
	if not Variants.flag(layout.get("ok", false)):
		return null
	if Variants.flag(layout["base_camp"]):
		return Basecamp.cell_data(run_seed)
	var data: LbCellData = layout["cell"]
	dress(layouts, cell, data)
	if gate_cells(run_seed).has(cell):
		arch(data, run_seed, cell)
	return data


## GEN-10's geometry before commit: the cell's air doors and sump mud (LbLayouts.dress).
static func dress(layouts: LbLayouts, cell: Vector2i, data: LbCellData) -> void:
	if cell != Vector2i.ZERO and data != null:
		layouts.dress(cell, data)


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
