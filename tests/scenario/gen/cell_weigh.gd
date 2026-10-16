extends RefCounted
## GEN-11: weighs live cells. A block of cells is committed with every hook the run has (Road
## Graph, light, vision, air doors, diff replay), then dropped, round after round, with a few ticks
## run before each reading but the full one (whatever the commits queued counts as theirs). The
## dearest round's growth per cell is what a live cell costs (the first also fills the deriver's
## caches). What the last rounds leave behind is what dropping a cell fails to give back: the early
## rounds also fill bounded rings (the diff log's 4,096 replays), so only the last are judged. A
## control (the same ticks with no cell committed, before and after the rounds) is taken off each
## reading, so whatever else grows meanwhile (a soak's bots and logs) is not counted as the cells'.
## Reads the heap in use (LbCoreInfo.heap_in_use, which falls when memory is freed, unlike the
## resident set); where the allocator cannot tell (not glibc), nothing is weighed.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")

## Ticks run before each reading, so queues the commits and unloads left drain.
const SETTLE_TICKS: int = 10


## {known, cells, kib_per_cell, kept_kib_per_cell} for `rounds` rounds of a side x side block at `centre`.
static func weigh(s: Scenario, centre: Vector2i, side: int, rounds: int) -> Dictionary:
	if LbCoreInfo.heap_in_use() < 0:
		return {"known": false}
	var cells: Array[Vector2i] = []
	for y: int in range(centre.y - side / 2, centre.y - side / 2 + side):
		for x: int in range(centre.x - side / 2, centre.x - side / 2 + side):
			cells.append(Vector2i(x, y))
	var grown: int = 0
	var kept: Array[int] = []
	s.step(SETTLE_TICKS)
	var control: float = _control(s)
	for _round: int in rounds:
		var before: int = LbCoreInfo.heap_in_use()
		for c: Vector2i in cells:
			var data: LbCellData = MineLayouts.cell_data(s.generation.layouts, s.run.header.run_seed, c)
			if data != null:
				s.mine.native.commit(data)
		var full: int = LbCoreInfo.heap_in_use()
		for c: Vector2i in cells:
			s.mine.unload_now(c)
		s.step(SETTLE_TICKS)
		grown = maxi(grown, full - before)
		kept.append(LbCoreInfo.heap_in_use() - before)
	control = (control + _control(s)) / 2.0
	# The last two rounds, averaged: the allocator's own noise is of either sign.
	var last: float = (kept[-1] + kept[-2]) / 2.0 if kept.size() >= 2 else float(kept[-1])
	return {"known": true, "cells": cells.size(), "kib_per_cell": maxi(0, grown) / 1024.0 / cells.size(),
		"kept_kib_per_cell": (last - control) / 1024.0 / cells.size(), "control_bytes": control}


## The heap's growth over a round's ticks with no cell committed.
static func _control(s: Scenario) -> float:
	var before: int = LbCoreInfo.heap_in_use()
	s.step(SETTLE_TICKS)
	return float(LbCoreInfo.heap_in_use() - before)
