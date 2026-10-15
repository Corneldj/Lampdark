extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-13: anything burning in an evicted cell is advanced to the present when the cell comes back.
## A lit lamp left on the floor has lost the oil it would have burned there (its wick, its ring),
## matching a twin that burned in a loaded cell all along, and is Dry if that empties it; a lit
## candle is spent after its 5 minutes, one with time left keeps the rest; a flare burns out.

const W = preload("res://tests/scenario/world/diff_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	WorldCoords.ring_override = -1


func _world(run_seed: int) -> Scenario:
	WorldCoords.ring_override = 2
	var s: Scenario = make({"seed": run_seed, "fixture": W.road()})
	W.miner(s, "ann", Vector2i(3, 1))
	s.step(2)
	return s


func _lamp_at(s: Scenario, tile: Vector2i, oil: float, wick: int) -> GauzeLamp:
	return s.run.lamps.create(s.run, oil, 2, true, wick, Vector2(tile) + Vector2(0.5, 0.5))


func test_a_lit_lamp_burns_while_its_cell_is_gone() -> void:
	var s: Scenario = _world(1311)
	var gone: GauzeLamp = _lamp_at(s, Vector2i(50, 1), 0.8, LampRules.WICK_UP)
	var twin: GauzeLamp = _lamp_at(s, Vector2i(30, 1), 0.8, LampRules.WICK_UP)
	s.step(3)
	assert_true(gone.burning() and twin.burning())
	W.evict(s, W.FAR)
	s.step(1)
	assert_false(s.run.lamps.lamps.has(gone.uid), "its lamp left with the cell")
	s.step(1200)
	W.restore(s, W.FAR)
	s.step(1)
	var back: GauzeLamp = s.run.lamps.lamps.get(gone.uid, null)
	assert_not_null(back, "the lamp is back, same uid")
	assert_true(back.burning(), "still lit")
	var per_tick: float = 1.0 / (Tuning.f(&"lamp.fill_minutes") * 60.0 * Tuning.f(&"net.tick_hz"))
	var rate: float = per_tick * Tuning.f(&"lamp.burn_factor_wick_up") * Tuning.by_ring(&"lamp.seam_drink_by_ring", 2)
	assert_lt(back.oil, 0.8 - rate * 1200.0 + rate * 3.0, "lost about 60 s of wick-up burn at ring 2's drink")
	assert_almost_eq(back.oil, twin.oil, rate * 3.0, "as much as its twin that burned in a loaded cell (%.6f, %.6f)" % [back.oil, twin.oil])


func test_a_lamp_that_runs_out_comes_back_dry() -> void:
	var s: Scenario = _world(1312)
	var gone: GauzeLamp = _lamp_at(s, Vector2i(50, 1), 0.005, LampRules.WICK_NORMAL)
	s.step(2)
	W.evict(s, W.FAR)
	s.step(600)
	W.restore(s, W.FAR)
	s.step(1)
	var back: GauzeLamp = s.run.lamps.lamps.get(gone.uid, null)
	assert_not_null(back)
	assert_eq(back.phase, LampRules.Phase.DRY, "dry, its oil spent while away")
	assert_eq(back.oil, 0.0)
	assert_false(back.burning())


func test_a_shut_out_lamp_does_not_burn() -> void:
	var s: Scenario = _world(1313)
	var l: GauzeLamp = s.run.lamps.create(s.run, 0.5, 2, false, LampRules.WICK_NORMAL, Vector2(50.5, 1.5))
	s.step(2)
	W.evict(s, W.FAR)
	s.step(400)
	W.restore(s, W.FAR)
	s.step(1)
	var back: GauzeLamp = s.run.lamps.lamps.get(l.uid, null)
	assert_eq(back.oil, 0.5, "an Out lamp keeps its oil")
	assert_eq(back.phase, LampRules.Phase.OUT)


func test_a_lit_candle_is_spent_after_five_minutes() -> void:
	var s: Scenario = _world(1314)
	var full: int = roundi(Tuning.f(&"items.candle_burn_time") * Tuning.f(&"net.tick_hz"))
	assert_eq(full, 6000, "5 minutes")
	var spent: int = W.put(s, ItemKinds.Kind.CANDLE, Vector2i(50, 1), {"lit": true, "burn_ticks": full})
	var kept: int = W.put(s, ItemKinds.Kind.CANDLE, Vector2i(52, 1), {"lit": true, "burn_ticks": full + 2000})
	var spent_uid: int = s.run.inventory.world.items[spent].uid
	var kept_uid: int = s.run.inventory.world.items[kept].uid
	s.step(2)
	W.evict(s, W.FAR)
	s.step(full)
	W.restore(s, W.FAR)
	assert_eq(W.entity_of(s, spent_uid), 0, "burnt out while its cell was gone")
	var e: int = W.entity_of(s, kept_uid)
	assert_ne(e, 0, "the longer one still burns")
	var left: int = int(Variants.number(s.run.inventory.world.items[e].state["burn_ticks"]))
	assert_almost_eq(float(left), float(2000 - 3), 4.0, "with the rest of its time")
	assert_true(s.run.diff_log.payload_of(W.FAR, DiffLog.Kind.ITEM, "u%d" % spent_uid).is_empty(), "its record gone too")


func test_a_flare_burns_out() -> void:
	var s: Scenario = _world(1315)
	var full: int = roundi(Tuning.f(&"items.flare_burn_time") * Tuning.f(&"net.tick_hz"))
	var f: int = W.put(s, ItemKinds.Kind.FLARE, Vector2i(50, 1), {"lit": true, "burn_ticks": full})
	var uid: int = s.run.inventory.world.items[f].uid
	s.step(2)
	W.evict(s, W.FAR)
	s.step(full + 10)
	W.restore(s, W.FAR)
	assert_eq(W.entity_of(s, uid), 0, "a flare burns out")
