class_name ProbeLog
extends RefCounted
## NET-12's server side: tick cost (NET-01's timings) for the whole tick, visibility and the Road
## Graph at p50, p95 and p99, against NET-01's budgets (5 ms, 2 ms, 0.5 ms at p99); and each
## client's bandwidth down and up per lane, voice counted apart, over `seconds`. The criterion-4
## report and the server's exit telemetry read it. Server-only.


static func tick_cost(run: RunState) -> Dictionary:
	var out: Dictionary = {}
	var keys: Dictionary = {"tick": TickTimer.TICK, "visibility": TickTimer.stage_key(StageTable.Stage.VISIBILITY),
		"road_graph": TickTimer.stage_key(StageTable.Stage.ROAD_GRAPH)}
	for name: String in keys:
		var key: String = keys[name]
		out[name] = {"p50_us": run.timer.percentile(key, 50.0), "p95_us": run.timer.percentile(key, 95.0),
			"p99_us": run.timer.percentile(key, 99.0), "max_us": run.timer.max_usec(key)}
	out["budget_p99_us"] = {"tick": 5000, "visibility": 2000, "road_graph": 500}
	return out


## Per lane kbps from a {lane: bytes} count over `seconds`, with voice apart from the rest.
static func kbps(bytes_by_lane: Dictionary, seconds: float) -> Dictionary:
	var game: float = 0.0
	var voice: float = 0.0
	for raw: Variant in bytes_by_lane.keys():
		var bytes: float = float(Variants.number(bytes_by_lane[raw]))
		if int(Variants.number(raw)) == Lane.Id.VOICE:
			voice += bytes
		else:
			game += bytes
	var s: float = maxf(seconds, 1e-6)
	return {"game_kbps": game * 8.0 / 1000.0 / s, "voice_kbps": voice * 8.0 / 1000.0 / s}
