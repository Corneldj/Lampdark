extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-11: a cell dropped gives back what it took. Cells come and go all run (a 30-minute spread
## drops some 20,000), so any hook that keeps a little per cell (the Road Graph's dead slots, the
## diff log's replay list once did) grows without end. 400 cells far from base camp are committed
## with every hook and dropped, round after round; the last rounds must leave next to nothing.
## Live cells must also fit GDD §15.9's 80 MB at mine.max_live_cells.

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const Weigh = preload("res://tests/scenario/gen/cell_weigh.gd")

## What a dropped cell may leave behind (the allocator's noise), in KiB.
const KEPT_KIB_MAX: float = 0.5


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_dropped_cells_give_their_memory_back() -> void:
	var s: Scenario = make({"seed": 2611, "generated": {"pack": Specs.road_pack()}})
	var w: Dictionary = Weigh.weigh(s, Vector2i(0, 40), 20, 14)
	if not Variants.flag(w["known"]):
		pending("the allocator here cannot tell its heap in use (not glibc)")
		return
	gut.p("a live cell %.1f KiB; a dropped one leaves %.2f KiB" % [w["kib_per_cell"], w["kept_kib_per_cell"]])
	assert_lt(float(Variants.number(w["kept_kib_per_cell"])), KEPT_KIB_MAX, "dropping cells gives their memory back")
	var cells_mb: float = float(Variants.number(Tuning.table(&"net.run_memory_parts_mb").get("cells", 80)))
	var at_cap: float = float(Variants.number(w["kib_per_cell"])) * Tuning.i(&"mine.max_live_cells") / 1024.0
	assert_lt(at_cap, cells_mb, "live cells at the cap fit the run's share for cells")
