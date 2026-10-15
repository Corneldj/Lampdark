extends "res://tools/bots/soak.gd"
## NET-07's budget soak (FND-04's record nightly slot): five bots on GEN-03's grey box for three
## hours in the scenario kit, each with a lamp that follows it, talking, with 20 falls spread over
## the run (each revived 30 s later). The rolling ring must stay within the design's estimate,
## net.record_buffer_estimate_mb plus 20% (GDD §15.3: "about 25 MB"; compressed, it holds far less),
## and the whole record (ring, pinned windows and the open blocks) within net.record_memory_mb
## throughout. Every fall must pin a window that seals and replays after the ring has rolled past
## it. test_record_budget_soak.gd runs it short on every push.

const MAP: String = "m1_greybox"
const FALLS: int = 20
const REVIVE_S: float = 30.0
const SPAWNS: Array[Vector2i] = [Vector2i(6, 6), Vector2i(13, 6), Vector2i(6, 13), Vector2i(13, 13), Vector2i(9, 9)]
const SAMPLE_TICKS: int = 200

var _lamps: Dictionary = {}
var _stats: Dictionary = {}


func setup(_ctx: Dictionary) -> void:
	profile = {"servers": 1, "bots": 5, "minutes": 180.0, "seed": 7070, "brains": ["wander", "chatter", "wander", "lamp", "follow"],
		"link": "", "capture_keep_s": 10.0}


func scenario_config(_server: int) -> Dictionary:
	return {"fixture": MAP}


func spawn_tile(_scenario: RefCounted, bot: int) -> Vector2i:
	return SPAWNS[bot % SPAWNS.size()]


func prepare(scenario: RefCounted) -> void:
	var run: RunState = scenario.get(&"run")
	var miners: Array = scenario.get(&"miners")
	for raw: Variant in miners:
		var h: RefCounted = raw
		var id: int = int(Variants.number(h.get(&"entity_id")))
		_lamps[id] = run.light.grid.add_point("gauze_lamp", LbLightGrid.COLOUR_AMBER, id, 0, 4.5, 1.0, run.registry.get_entity(id).position, 0)
	for at: Vector2 in [Vector2(10.5, -12.5), Vector2(28.5, -16.5), Vector2(30.5, 9.5), Vector2(4.5, 24.5)]:
		run.light.grid.add_point("gauze_lamp", LbLightGrid.COLOUR_AMBER, 0, 0, 4.5, 1.0, at, 0)
	var total: int = roundi(float(Variants.number(profile["minutes"])) * 60.0 * Tuning.f(&"net.tick_hz"))
	var every: int = maxi(1, floori(total / float(FALLS + 1)))
	var revive_ticks: int = roundi(REVIVE_S * Tuning.f(&"net.tick_hz"))
	var ring_fill: int = run.record.ring_ticks + run.record.block_ticks + run.record.seal_lag_ticks
	_stats = {"falls": 0, "revived": 0, "ring_max": 0, "ring_min_full": -1, "total_max": 0, "samples": 0, "ticks": total,
		"ring_full_from": ring_fill, "fall_ticks": []}
	var down: Dictionary = {}
	scenario.set(&"on_tick", func(sc: RefCounted) -> void:
		var r: RunState = sc.get(&"run")
		for raw_id: Variant in _lamps.keys():
			var e: SimEntity = r.registry.get_entity(int(Variants.number(raw_id)))
			if e != null:
				r.light.grid.update_point(int(Variants.number(_lamps[raw_id])), e.position, 4.5, 1.0)
		var n: int = int(Variants.number(_stats["falls"]))
		if r.tick % every == 0 and n < FALLS:
			var h: RefCounted = miners[n % miners.size()]
			var id: int = int(Variants.number(h.get(&"entity_id")))
			if r.falls.fall_unconscious(r, id, FallCause.Cause.MOTH_SMOTHER):
				_stats["falls"] = n + 1
				Variants.array(_stats["fall_ticks"]).append(r.tick)
				down[id] = r.tick + revive_ticks
		for raw_id: Variant in down.keys():
			if r.tick >= int(Variants.number(down[raw_id])):
				r.miner_state.revive(int(Variants.number(raw_id)), &"test")
				down.erase(raw_id)
				_stats["revived"] = int(Variants.number(_stats["revived"])) + 1
		if r.tick % SAMPLE_TICKS == 0:
			_sample(r))


func _sample(r: RunState) -> void:
	var ring: int = r.record.ring_bytes()
	var total: int = r.record.memory_bytes()
	_stats["samples"] = int(Variants.number(_stats["samples"])) + 1
	_stats["ring_max"] = maxi(int(Variants.number(_stats["ring_max"])), ring)
	_stats["total_max"] = maxi(int(Variants.number(_stats["total_max"])), total)
	if r.tick >= int(Variants.number(_stats["ring_full_from"])):
		var low: int = int(Variants.number(_stats["ring_min_full"]))
		_stats["ring_min_full"] = ring if low < 0 else mini(low, ring)


func inspect(scenario: RefCounted) -> Dictionary:
	var run: RunState = scenario.get(&"run")
	var r: RunRecord = run.record
	var sealed: int = 0
	var outlived: int = 0
	for w: RecordWindow in r.windows:
		if w.kind != RecordWindow.Kind.FALL:
			continue
		sealed += 1 if w.sealed else 0
		outlived += 1 if w.sealed and not RecordReaders.victim_view(r, w).is_empty() else 0
	var out: Dictionary = _stats.duplicate()
	out["fall_windows"] = r.windows.filter(func(w: RecordWindow) -> bool: return w.kind == RecordWindow.Kind.FALL).size()
	out["fall_windows_sealed"] = sealed
	out["fall_windows_replay"] = outlived
	out["windows_bytes"] = r.windows_bytes()
	out["ring_bytes_end"] = r.ring_bytes()
	out["thinned"] = r.thinning_log.size()
	out["keyframe_misses"] = r.keyframe_misses
	out["late_acks"] = r.late_acks
	out["record_usec"] = run.timer.summary(TickTimer.system_key(r))
	return out


func verify(report: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var mb: float = 1024.0 * 1024.0
	var target: float = Tuning.f(&"net.record_buffer_estimate_mb") * mb
	var budget: float = Tuning.f(&"net.record_memory_mb") * mb
	for raw: Variant in Variants.array(report.get("servers", [])):
		var s: Dictionary = Variants.dict(raw)
		var st: Dictionary = Variants.dict(s.get("inspect", {}))
		var falls: int = int(Variants.number(st.get("falls", 0)))
		if falls != FALLS:
			errors.append("server %s: %d scripted falls, not %d" % [s.get("index"), falls, FALLS])
		if int(Variants.number(st.get("fall_windows_sealed", 0))) != falls or int(Variants.number(st.get("fall_windows_replay", 0))) != falls:
			errors.append("server %s: %s of %d fall windows sealed, %s replay" % [s.get("index"), st.get("fall_windows_sealed"), falls,
				st.get("fall_windows_replay")])
		var total_max: float = float(Variants.number(st.get("total_max", 0)))
		if total_max > budget:
			errors.append("server %s: the record reached %.1f MB, over %.0f MB" % [s.get("index"), total_max / mb, budget / mb])
		var high: float = float(Variants.number(st.get("ring_max", 0)))
		if high > target * 1.2:
			errors.append("server %s: the ring reached %.1f MB, over %.0f MB + 20%%" % [s.get("index"), high / mb, target / mb])
		if int(Variants.number(st.get("keyframe_misses", 0))) > 0:
			errors.append("server %s: %s keyframe views the encoder no longer held" % [s.get("index"), st.get("keyframe_misses")])
	return errors
