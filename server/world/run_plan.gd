class_name RunPlan
extends RefCounted
## GEN-08: the run's plan (Gameplay §12.3, §12.5; GDD §15.9), fixed before the cold open ends and
## before any cell is derived. From the seed and the repair list (LFT-03) alone, LbLayouts plans a
## banded site for every required point of interest and planned find, a spine of forced-open edges
## from base camp to each, and the revolver and its boxes on spine cells; spine sockets and cells
## then join every derive (no old fall on a spine). The header serialises canonically into
## run.header.plan, which every snapshot keeps (NET-09), so a resumed run keeps its plan byte for
## byte rather than planning again. MOD-03's run setup will call fix() in place of server_main.
## Server-only: no plan, site or spine reaches a client; the Manual names only kinds of place.


## The plan for `run` on `layouts` (configured for its seed): restored from `saved` (a snapshot's
## header bytes) when given, else made. Returns LbLayouts.plan_dict(), {} if it failed.
static func fix(layouts: LbLayouts, run: RunState, saved: PackedByteArray = PackedByteArray()) -> Dictionary:
	if not saved.is_empty():
		if not layouts.load_plan(saved):
			push_error("RunPlan: the saved plan does not fit this run")
			return {}
		run.header.plan = saved
		return layouts.plan_dict()
	var plan: Dictionary = layouts.plan(params(run))
	run.header.plan = layouts.plan_bytes()
	if not Variants.flag(plan.get("ok", false)):
		push_error("RunPlan: %s" % str(plan.get("error", "")))
		return {}
	Log.info("run plan: %d sites, %d spines, the revolver %s, %d boxes" % [Variants.array(plan["sites"]).size(),
		Variants.array(plan["spines"]).size(), "planned" if Variants.flag(plan["revolver"]) else "not planned",
		Variants.array(plan["boxes"]).size()])
	return plan


## LbLayouts.plan's inputs: the list (Night Shift's solo rule), the run conditions MOD-03 will set,
## the data version, and the numbers.
static func params(run: RunState) -> Dictionary:
	var list: RepairList = run.repair.list if run.repair != null else null
	var jobs: PackedStringArray = PackedStringArray()
	if list != null:
		for job: StringName in list.jobs:
			jobs.append(String(job))
	return {
		"list_kind": list.kind if list != null else RepairList.Kind.STANDARD,
		"jobs": jobs,
		"cans": list.cans_required if list != null else RepairList.cans_for(RepairList.Kind.STANDARD),
		"solo": run.header.mode == ServerConfig.Mode.NIGHTSHIFT,
		"draw": PackedStringArray(),
		"staging": "",
		"hard_variant": "",
		"data_version": run.header.tuning_hash,
		"tuning": tuning(),
	}


## GEN-08's numbers from tuning (mine.*): bands by list kind, rings, odds, counts, footprints.
static func tuning() -> Dictionary:
	return {
		"substation": _bands("mine.band_substation"),
		"hoard": _bands("mine.band_hoard"),
		"lair": _bands("mine.band_lair"),
		"parts_rings": _bands("mine.band_parts_rings"),
		"lair_min_bearing_deg": Tuning.f(&"mine.lair_min_bearing_from_hoard_deg"),
		"drum_gear_ring": Tuning.i(&"mine.drum_gear_ring"),
		"tools_ring": Tuning.i(&"mine.band_tools_ring"),
		"paraffin_factor": Tuning.f(&"mine.paraffin_planned_factor"),
		"paraffin_max_ring": Tuning.i(&"mine.paraffin_max_ring"),
		"fuel_cans_min": Tuning.i(&"mine.fuel_store_cans_min"),
		"fuel_cans_max": Tuning.i(&"mine.fuel_store_cans_max"),
		"spare_probability": Tuning.f(&"mine.part_spare_probability"),
		"revolver_probability": Tuning.f(&"mine.revolver_probability"),
		"boxes_min": Tuning.i(&"mine.ammo_boxes_min"),
		"boxes_max": Tuning.i(&"mine.ammo_boxes_max"),
		"max_retries": Tuning.i(&"mine.plan_max_retries"),
		"max_per_region": Tuning.i(&"mine.max_planned_poi_per_region"),
		"footprint_w": Tuning.table(&"mine.poi_footprint_w"),
		"footprint_h": Tuning.table(&"mine.poi_footprint_h"),
		"ring_min": Tuning.table(&"mine.poi_ring_min"),
		"ring_max": Tuning.table(&"mine.poi_ring_max"),
	}


## A band key's three ranges, Short, Standard and Full, as whole [lo, hi] pairs.
static func _bands(prefix: String) -> Array:
	var out: Array = []
	for kind: String in RepairJobs.KIND_NAMES:
		var r: Vector2 = Tuning.range_f(StringName("%s_%s" % [prefix, kind]))
		out.append([roundi(r.x), roundi(r.y)])
	return out
