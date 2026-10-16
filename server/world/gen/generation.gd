class_name Generation
extends SimSystem
## GEN-11 (stage GENERATION, after MineCommitSystem): lazy generation (Gameplay §12.3, GDD §15.9).
## Each tick it finds the window holders (every miner in any state, Hired Hands and bodies among
## them, Bess and every creature) and hands their cells to LbLayouts' window manager, which asks the
## worker pool, nearest first, for every cell within mine.generation_prefetch_radius_cells of one
## (Chebyshev) that is not loaded: the required cells (within mine.generation_radius_cells) and,
## ahead of need, the ring beyond them, which the hysteresis keeps loaded anyway. A tick whose
## holders stand in the cells they stood in costs next to nothing. Finished cells commit nearest
## first: base camp is GEN-02's cell, the gate cells carry their arches (MineLayouts.cell_data), and
## the commit's hooks stitch the Road Graph, light the cell and replay its diff (GEN-13). When the
## holders move, cells farther than mine.eviction_radius_cells from every holder are listed to go
## (base camp and its gate cells never), and over mine.max_live_cells the farthest beyond the
## prefetch ring too; they unload after the commits, the farthest first (CRT-02's keep_loaded may
## refuse). At the cap, a commit first drops the farthest such cell, so the cap holds while
## anything can go (required cells beat it). The whole tick's work, this system's and the stage's queued work alike, keeps within
## mine.commit_budget_ms_per_tick: at least one commit and one unload a tick, then each next one
## only while it fits, priced at the dearest of the last 64 of its kind; the commits leave room
## for the tick's unload and its closing checks, priced the same way. A returning cell is derived
## again, identical. Synchronous mode (scenarios) derives and commits every wanted cell on the
## tick, so tests repeat. Content never depends on threads or timing; only when a cell appears may
## vary. Server-only: nothing here reaches a client (NET-04 sends only seen tiles).

const HOLDERS: Array[int] = [WorldIds.EntityKind.MINER, WorldIds.EntityKind.BESS, WorldIds.EntityKind.MOTH,
	WorldIds.EntityKind.TAPPER, WorldIds.EntityKind.STYTHE]
## How far round a miner a missing cell counts against sight (GDD §15.9: sight reaches 2 cells).
const SIGHT_CELLS: int = 2
## How many of the dearest ticks stats() reports.
const SLOWEST_KEPT: int = 5

var mine: Mine
var layouts: LbLayouts
var run_seed: int = 0
var synchronous: bool = false
## Never evicted: base camp and the cells its gate roads enter.
var pinned: Array[Vector2i] = []

var radius: int = 4
var prefetch_radius: int = 5
var evict_radius: int = 6
var max_live: int = 700
var commit_budget_usec: int = 1000

## Required cells not yet loaded: cell -> the tick they became required (the latency's start).
var _required_since: Dictionary = {}
## Cells no template fits (GEN-12 rerolls them): asked once each time they come into reach.
var _failed: Dictionary = {}
var _gate_cells: Dictionary = {}
## The holders moved since evictions were last worked out.
var _evict_due: bool = true
## Loaded cells to drop, the farthest first, unloaded a few a tick after the commits.
var _to_evict: Array[Vector2i] = []
## Listed cells: cell -> the tick first listed (the eviction's latency runs from then).
var _listed_at: Dictionary = {}
var _tick: int = 0
## What the next commit and unload are expected to cost (microseconds, take and hooks included):
## the dearest of the last few.
var _commit_estimate: int = 0
var _unload_estimate: int = 0
var _commit_costs: Array[int] = []
var _unload_costs: Array[int] = []
## What the tick's closing checks cost (the sight check and the metrics), priced the same way.
var _tail_estimate: int = 0
var _tail_costs: Array[int] = []
## The dearest ticks of this system, for QA-03: {tick, usec, apply_usec, commits, unloads}, dearest first.
var _slowest: Array[Dictionary] = []
## The dearest single commit: {cell, usec}.
var _dearest_commit: Dictionary = {}

## Metrics for NET-12's probes and the soaks.
var commits: int = 0
var evicted: int = 0
var failures: int = 0
var max_live_seen: int = 0
var missing_sight_ticks: int = 0
## The longest a listed cell waited to go, in ticks (the soak holds it to 10 s).
var evict_latency_max_ticks: int = 0
var _latency_ms: Array[float] = []
var _commit_usec: Array[int] = []


## `background`: the workers run below normal priority (a server on a player's machine: a private
## host or Night Shift, beside the game's own frame).
func _init(server_mine: Mine, deriver: LbLayouts, seed_value: int, sync: bool = false, workers: int = 1,
		background: bool = false) -> void:
	mine = server_mine
	layouts = deriver
	run_seed = seed_value
	synchronous = sync
	radius = Tuning.i(&"mine.generation_radius_cells")
	prefetch_radius = maxi(radius, Tuning.i(&"mine.generation_prefetch_radius_cells"))
	evict_radius = Tuning.i(&"mine.eviction_radius_cells")
	max_live = Tuning.i(&"mine.max_live_cells")
	commit_budget_usec = roundi(Tuning.f(&"mine.commit_budget_ms_per_tick") * 1000.0)
	for cell: Vector2i in MineLayouts.gate_cells(run_seed):
		_gate_cells[cell] = true
		pinned.append(cell)
	pinned.append(Vector2i.ZERO)
	layouts.start_pool(0 if synchronous else maxi(1, workers), background)
	layouts.set_window(radius, prefetch_radius)


func stage() -> int:
	return StageTable.Stage.GENERATION


func order() -> int:
	return 1 # after MineCommitSystem: its unloads land on the next tick


## Run start (GDD §15.9): the windows round base camp and round each of `centres` (GEN-10's homes,
## CRT-01's creature starts), generated and committed at once, before the first tick. GEN-08's
## plan adds its own when it lands.
func start(centres: Array[Vector2i] = []) -> void:
	var at_start: Array[Vector2i] = [Vector2i.ZERO]
	at_start.append_array(centres)
	for cell: Variant in LbLayouts.required_cells(at_start, radius):
		var at: Vector2i = cell
		if mine.native.is_loaded(at) or _failed.has(at):
			continue
		var data: LbCellData = MineLayouts.cell_data(layouts, run_seed, at)
		if data == null:
			_note_failure(at)
			continue
		mine.native.commit(data)
		commits += 1
	max_live_seen = maxi(max_live_seen, mine.native.loaded_count())


func tick(run: RunState) -> void:
	var started: int = Time.get_ticks_usec() # determinism: allow (the budget paces when a cell comes or goes, never what it holds)
	_tick = run.tick
	var holders: Array[Vector2i] = []
	var miners: Array[Vector2i] = []
	for id: int in run.registry.ids():
		var e: SimEntity = run.registry.get_entity(id)
		if e == null or not HOLDERS.has(int(e.kind)):
			continue
		var cell: Vector2i = WorldCoords.cell_of(WorldCoords.tile_at(e.position))
		holders.append(cell)
		if e.kind == WorldIds.EntityKind.MINER:
			miners.append(cell)
	var change: Dictionary = layouts.update_window(holders, mine.native)
	if Variants.flag(change["moved"]):
		var left: Array[Vector2i] = change["left"]
		for cell: Vector2i in left:
			_required_since.erase(cell)
		# Entering the required set: its latency runs from now (none if already loaded).
		var entered: Array[Vector2i] = change["entered"]
		for cell: Vector2i in entered:
			if _failed.has(cell):
				_push_f(_latency_ms, 0.0)
			else:
				_required_since[cell] = run.tick
		for _i: int in int(Variants.number(change["entered_loaded"])):
			_push_f(_latency_ms, 0.0)
		_evict_due = true
	if _evict_due or mine.native.loaded_count() > max_live:
		_evict_due = false
		_list_evictions(layouts.evictions_now(mine.native, pinned, evict_radius, max_live))
	# This stage's queued work (MineCommitSystem) spent part of the budget already; the commits
	# leave room for an unload, if any is due, and for the closing checks.
	var budget: int = commit_budget_usec - mine.last_apply_usec
	var reserve: int = _tail_estimate + (_unload_estimate if not _to_evict.is_empty() else 0)
	var committed: int = _commit(run, started, budget - reserve)
	var unloaded: int = _unload(started, budget - _tail_estimate)
	var tail_started: int = Time.get_ticks_usec() # determinism: allow (as above)
	max_live_seen = maxi(max_live_seen, mine.native.loaded_count())
	# Sight reaches 2 cells: a miner with an unloaded cell that close is the failure the budgets exist to prevent.
	for cell: Vector2i in mine.native.missing_cells(miners, SIGHT_CELLS):
		if not _failed.has(cell):
			missing_sight_ticks += 1
			break
	var ended: int = Time.get_ticks_usec() # determinism: allow (a metric only)
	_tail_estimate = _dearest(_tail_costs, ended - tail_started)
	_note_cost(run.tick, ended - started, committed, unloaded)


## {commits, evicted, failures, live, max_live, queued, derive_p50_ms, derive_p99_ms,
## commit_latency_p99_ms, commit_usec_p99, commit_usec_max, dearest_commit, evict_latency_max_s,
## missing_sight_ticks, slowest_ticks}
func stats() -> Dictionary:
	var pool: Dictionary = layouts.pool_stats()
	var dearest: int = 0 if _commit_usec.is_empty() else _commit_usec.max()
	return {"commits": commits, "evicted": evicted, "failures": failures, "live": mine.native.loaded_count(),
		"max_live": max_live_seen, "queued": pool["queued"], "derive_p50_ms": pool["p50_ms"], "derive_p99_ms": pool["p99_ms"],
		"commit_latency_p99_ms": _p99f(_latency_ms), "commit_usec_p99": _p99i(_commit_usec), "commit_usec_max": dearest,
		"dearest_commit": _dearest_commit.duplicate(),
		"evict_latency_max_s": evict_latency_max_ticks / Tuning.f(&"net.tick_hz"), "missing_sight_ticks": missing_sight_ticks,
		"slowest_ticks": _slowest.duplicate(true)}


## Finished cells, nearest first: at least one, then while the next fits the budget. Synchronous
## mode commits them all. Returns how many were taken.
func _commit(run: RunState, started: int, budget: int) -> int:
	var committed: int = 0
	while synchronous or committed == 0 or Time.get_ticks_usec() - started + _commit_estimate <= budget: # determinism: allow (as above)
		var began: int = Time.get_ticks_usec() # determinism: allow (as above)
		var took: Array = layouts.take(1)
		if took.is_empty():
			return committed
		committed += 1
		var r: Dictionary = took[0]
		var cell: Vector2i = r["at"]
		if mine.native.is_loaded(cell):
			continue # committed by another way meanwhile
		if not Variants.flag(r.get("ok", false)):
			_note_failure(cell)
			continue
		var data: LbCellData = Basecamp.cell_data(run_seed) if Variants.flag(r["base_camp"]) else r["cell"]
		if _gate_cells.has(cell):
			MineLayouts.arch(data, run_seed, cell)
		if mine.native.loaded_count() >= max_live:
			_make_room()
		var t0: int = Time.get_ticks_usec() # determinism: allow (a metric only)
		mine.native.commit(data)
		var cost: int = Time.get_ticks_usec() - t0 # determinism: allow (a metric only)
		_push_i(_commit_usec, cost)
		if cost > int(Variants.number(_dearest_commit.get("usec", 0))):
			_dearest_commit = {"cell": cell, "usec": cost}
		if _required_since.has(cell):
			_push_f(_latency_ms, (run.tick - int(Variants.number(_required_since[cell]))) * 1000.0 / Tuning.f(&"net.tick_hz"))
			_required_since.erase(cell)
		commits += 1
		_commit_estimate = _dearest(_commit_costs, Time.get_ticks_usec() - began) # determinism: allow (as above)
	return committed


## Listed cells, the farthest first: at least one, then while the next fits the budget.
## Synchronous mode drops them all. Returns how many were tried.
func _unload(started: int, budget: int) -> int:
	var done: int = 0
	while not _to_evict.is_empty() and (synchronous or done == 0 or Time.get_ticks_usec() - started + _unload_estimate <= budget): # determinism: allow (as above)
		var cell: Vector2i = _to_evict.pop_front()
		done += 1
		var t0: int = Time.get_ticks_usec() # determinism: allow (a metric only)
		_drop(cell)
		_unload_estimate = _dearest(_unload_costs, Time.get_ticks_usec() - t0) # determinism: allow (as above)
	return done


## At the cap: drops the farthest cell that may go (beyond 6 of every holder, or beyond the
## prefetch ring), listing them afresh if none is listed. Nothing goes if every live cell is wanted.
func _make_room() -> void:
	if _to_evict.is_empty():
		_list_evictions(layouts.evictions_now(mine.native, pinned, evict_radius, max_live - 1))
	while not _to_evict.is_empty():
		var cell: Vector2i = _to_evict.pop_front()
		if _drop(cell):
			return


## The cells to drop now; a cell listed before keeps its first tick, one no longer listed is forgotten.
func _list_evictions(cells: Array[Vector2i]) -> void:
	_to_evict = cells
	var now: Dictionary = {}
	for cell: Vector2i in cells:
		now[cell] = _listed_at.get(cell, _tick)
	_listed_at = now


## Unloads a listed cell (keep_loaded may refuse): true if it went.
func _drop(cell: Vector2i) -> bool:
	if not mine.unload_now(cell):
		return false
	evicted += 1
	if _listed_at.has(cell):
		evict_latency_max_ticks = maxi(evict_latency_max_ticks, _tick - int(Variants.number(_listed_at[cell])))
		_listed_at.erase(cell)
	return true


func _note_cost(at_tick: int, usec: int, committed: int, unloaded: int) -> void:
	if _slowest.size() >= SLOWEST_KEPT and usec <= int(Variants.number(_slowest[-1]["usec"])):
		return
	_slowest.append({"tick": at_tick, "usec": usec, "apply_usec": mine.last_apply_usec, "commits": committed, "unloads": unloaded})
	var dearer: Callable = func(a: Dictionary, b: Dictionary) -> bool:
		return Variants.number(a["usec"]) > Variants.number(b["usec"])
	_slowest.sort_custom(dearer)
	if _slowest.size() > SLOWEST_KEPT:
		_slowest.pop_back()


func _note_failure(cell: Vector2i) -> void:
	if not _failed.has(cell):
		_failed[cell] = true
		failures += 1
		Log.warn("generation: no template fits cell %s (GEN-12 rerolls)" % cell)


## The dearest of the last 64 costs, `cost` the newest.
static func _dearest(recent: Array[int], cost: int) -> int:
	recent.append(cost)
	if recent.size() > 64:
		recent.pop_front()
	var most: int = recent.max()
	return most


static func _push_f(list: Array[float], v: float) -> void:
	list.append(v)
	if list.size() > 4096:
		list.pop_front()


static func _push_i(list: Array[int], v: int) -> void:
	list.append(v)
	if list.size() > 4096:
		list.pop_front()


static func _p99f(list: Array[float]) -> float:
	if list.is_empty():
		return 0.0
	var s: Array[float] = list.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(s.size() * 0.99))]


static func _p99i(list: Array[int]) -> int:
	if list.is_empty():
		return 0
	var s: Array[int] = list.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(s.size() * 0.99))]
