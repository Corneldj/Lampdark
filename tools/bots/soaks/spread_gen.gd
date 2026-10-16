extends "res://tools/bots/soak.gd"
## GEN-11's spreading soak (nightly): one generated run, five miners walked out from base camp along
## the main roads at run speed in real time, turning at every crossing and back at the Deep, while
## the worker pool generates round them. Judged on GDD §15.9's promises: no cell within sight (2
## cells) of a miner is ever missing, required cells commit within mine.commit_latency_p99_ms at
## p99, the generation stage keeps within mine.commit_budget_ms_per_tick at p99 (NET-12's probe),
## a cell out of reach goes within 10 s, the live cells stay under mine.max_live_cells and within
## net.run_memory_parts_mb's cells share at that cap, and a cell derives within the server budget.
## What a dropped cell leaves behind is reported, not judged: five bots' traffic makes it noisy
## here, and test_cells_give_memory_back judges it alone.
## The walkers are a harness (the server moves them), not players: bots cannot see yet (NET-04's
## client decoder), so their brains idle while the soak steers.
## run_soak.sh spread_gen [--minutes T]   (in-process: the profile asks for accelerated mode)

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const Weigh = preload("res://tests/scenario/gen/cell_weigh.gd")
const TICK_USEC: int = 50000
## Where and how many cells are weighed: a 20x20 block far from base camp.
const MEASURE_CENTRE: Vector2i = Vector2i(0, 40)
const MEASURE_SIDE: int = 20
## Rounds of the weighing (enough to fill the bounded rings first).
const MEASURE_ROUNDS: int = 14
## GEN-11's criterion (Proposed): a cell beyond 6 of every holder goes within 10 s.
const EVICT_WITHIN_S: float = 10.0

var _walkers: Array[Dictionary] = []
var _next_tick_usec: int = 0
var _mem_peak: int = 0
## The run's memory peaks, for the record (Godot's static memory; the resident set where /proc
## gives it). The kit's own logs grow all run (QA-03's note from NET-07), so the cells are weighed
## apart, before the walk.
var _rss_peak: int = 0
var _steps: int = 0
## What a live cell costs, and what dropping one failed to give back, in KiB (_measure_cells);
## unknown where the allocator cannot tell its heap in use.
var _cell_kib: float = 0.0
var _kept_kib: float = 0.0
var _heap_known: bool = false


func setup(_ctx: Dictionary) -> void:
	profile = {"servers": 1, "bots": 5, "minutes": 30.0, "seed": 2611, "brains": ["idle"], "link": "", "accelerated": true,
		"capture_keep_s": 10.0}


func scenario_config(_server: int) -> Dictionary:
	return {"generated": {"pack": Specs.road_pack(), "workers": Tuning.i(&"mine.generation_workers_fleet")}}


func spawn_tile(s: Scenario, _bot: int) -> Vector2i:
	return Basecamp.deck_rect(s.run.header.run_seed).position


## Each miner gets a walker: from base camp's centre out by a gate, along the main roads.
func prepare(s: Scenario) -> void:
	var rng: LbRng = LbRng.from_seed(int(Variants.number(profile["seed"])))
	var gates: Array[Vector2i] = []
	for g: Dictionary in Basecamp.gate_specs(s.run.header.run_seed):
		var out: Vector2i = g["outward"]
		gates.append(out)
	for i: int in s.miners.size():
		var entity: int = s.miners[i].entity_id
		var dir: Vector2i = gates[i % gates.size()]
		_walkers.append({"entity": entity, "pos": Vector2(10.5, 10.5), "dir": dir, "rng": rng})
	_measure_cells(s)
	_next_tick_usec = Time.get_ticks_usec()
	s.on_tick = func(sc: Scenario) -> void: _step(sc)


func _step(s: Scenario) -> void:
	var stride: float = Tuning.f(&"movement.run_speed") / Tuning.f(&"net.tick_hz")
	for w: Dictionary in _walkers:
		var pos: Vector2 = w["pos"]
		var dir: Vector2i = w["dir"]
		var cell: Vector2i = WorldCoords.cell_of(WorldCoords.tile_at(pos))
		var centre: Vector2 = Vector2(cell * 20) + Vector2(10.5, 10.5)
		var ahead: float = (centre - pos).dot(Vector2(dir))
		var road: Dictionary = s.generation.layouts.road_of(cell)
		if ahead > 0.0 and ahead <= stride and (Variants.flag(road.get("crossing", false)) or cell == Vector2i.ZERO):
			# This step passes a crossing's centre (or base camp's): a road on, chosen there.
			var options: Array[Vector2i] = []
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if d != -dir and Variants.flag(s.generation.layouts.road_of(cell + d).get("main_road", false)):
					options.append(d)
			var rng: LbRng = w["rng"]
			dir = options[rng.range(0, options.size() - 1)] if not options.is_empty() else -dir
			pos = centre + Vector2(dir) * (stride - ahead)
		else:
			pos += Vector2(dir) * stride
			var next: Vector2i = WorldCoords.cell_of(WorldCoords.tile_at(pos))
			if next != Vector2i.ZERO and not Variants.flag(s.generation.layouts.road_of(next).get("main_road", false)):
				pos -= Vector2(dir) * stride # the Deep: back the way it came
				dir = -dir
		w["pos"] = pos
		w["dir"] = dir
		var entity: int = w["entity"]
		s.run.movement.place(s.run, entity, pos)
	_mem_peak = maxi(_mem_peak, OS.get_static_memory_usage())
	_steps += 1
	if _steps % 20 == 0:
		_rss_peak = maxi(_rss_peak, _rss())
	# Run speed means real time: one tick each 50 ms of the wall clock.
	_next_tick_usec += TICK_USEC
	var wait: int = _next_tick_usec - Time.get_ticks_usec()
	if wait > 0:
		OS.delay_usec(wait)


## Memory: the peaks, and what live cells cost, at mine.max_live_cells.
func inspect(s: Scenario) -> Dictionary:
	var out: Dictionary = s.generation.stats()
	out["memory_peak_mb"] = _mem_peak / 1048576.0
	out["rss_peak_mb"] = _rss_peak / 1048576.0
	out["kib_per_live_cell"] = _cell_kib
	out["kib_kept_per_dropped_cell"] = _kept_kib
	out["cells_mb_at_cap"] = _cell_kib * Tuning.i(&"mine.max_live_cells") / 1024.0
	out["memory_measure"] = "heap" if _heap_known else "none"
	return out


## Live cells weighed before the walk, once base camp's window has settled (cell_weigh.gd).
func _measure_cells(s: Scenario) -> void:
	var w: Dictionary = Weigh.weigh(s, MEASURE_CENTRE, MEASURE_SIDE, MEASURE_ROUNDS)
	_heap_known = Variants.flag(w["known"])
	if _heap_known:
		_cell_kib = float(Variants.number(w["kib_per_cell"]))
		_kept_kib = float(Variants.number(w["kept_kib_per_cell"]))
		Log.info("spread_gen: a live cell %.1f KiB; a dropped one leaves %.2f KiB" % [_cell_kib, _kept_kib])


## The resident set in bytes from /proc (Linux); 0 elsewhere.
static func _rss() -> int:
	var f: FileAccess = FileAccess.open("/proc/self/statm", FileAccess.READ)
	if f == null:
		return 0
	var parts: PackedStringArray = f.get_line().split(" ")
	return int(parts[1]) * 4096 if parts.size() > 1 else 0


func verify(report: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	# NET-12's tick-cost probe: the generation stage (commits and unloads) within its budget at p99.
	var budget_us: float = Tuning.f(&"mine.commit_budget_ms_per_tick") * 1000.0
	var stage: Dictionary = Variants.dict(Variants.dict(report.get("tick_cost_usec", {})).get(
		StageTable.stage_name(StageTable.Stage.GENERATION), {}))
	if float(Variants.number(stage.get("p99", 1e9))) > budget_us:
		errors.append("the generation stage took %s us at p99, over %s us" % [stage.get("p99"), budget_us])
	var latency_max: float = Tuning.f(&"mine.commit_latency_p99_ms")
	var derive_max: float = Tuning.f(&"mine.generation_budget_ms_server")
	for raw: Variant in Variants.array(report.get("servers", [])):
		var g: Dictionary = Variants.dict(Variants.dict(raw).get("inspect", {}))
		if int(Variants.number(g.get("missing_sight_ticks", -1))) != 0:
			errors.append("a cell within sight of a miner was missing on %s ticks" % g.get("missing_sight_ticks"))
		if float(Variants.number(g.get("commit_latency_p99_ms", 1e9))) > latency_max:
			errors.append("commit latency p99 %s ms is over %s ms" % [g.get("commit_latency_p99_ms"), latency_max])
		if float(Variants.number(g.get("evict_latency_max_s", 1e9))) > EVICT_WITHIN_S:
			errors.append("a cell beyond reach waited %s s to go, over %s s" % [g.get("evict_latency_max_s"), EVICT_WITHIN_S])
		if int(Variants.number(g.get("max_live", 1 << 30))) > Tuning.i(&"mine.max_live_cells"):
			errors.append("%s live cells, over the cap" % g.get("max_live"))
		if float(Variants.number(g.get("derive_p99_ms", 1e9))) > derive_max:
			errors.append("a cell derives in %s ms at p99, over %s ms" % [g.get("derive_p99_ms"), derive_max])
		if int(Variants.number(g.get("failures", 1))) != 0:
			errors.append("%s cells had no template" % g.get("failures"))
		var cells_mb: float = float(Variants.number(Tuning.table(&"net.run_memory_parts_mb").get("cells", 80)))
		if str(g.get("memory_measure", "")) != "heap":
			errors.append("live cells were not weighed: the allocator cannot tell its heap in use here")
		elif float(Variants.number(g.get("cells_mb_at_cap", 1e9))) > cells_mb:
			errors.append("live cells would take %s MB at the cap, over %s MB" % [g.get("cells_mb_at_cap"), cells_mb])
		if int(Variants.number(g.get("commits", 0))) < 500:
			errors.append("only %s cells committed: the walkers did not spread" % g.get("commits"))
	return errors
