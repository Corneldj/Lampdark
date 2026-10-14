extends RefCounted
## FND-09's accelerated soaks: the same soak and brains inside the scenario kit, one scenario
## per server, stepped as fast as it goes. Brains read their captured stream instead of a
## socket, so QA-03's 3-hour Full run needs no 3 hours of wall time.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")


## Fills `report` (the orchestrator's shape) for `servers` scenarios of `bots` brains each. A
## soak may define scenario_config(server) -> Dictionary (merged into Scenario.create's, e.g. a
## fixture), created(scenario) (before anyone joins), spawn_tile(scenario, bot) -> Vector2i,
## prepare(scenario) (after the bots join) and
## inspect(scenario) -> Dictionary (before it closes; kept as the server's "inspect").
static func run(profile: Dictionary, servers: int, bots: int, ticks: int, out_dir: String, brain_for: Callable, report: Dictionary,
		soak: Object = null) -> void:
	var n: int = 0
	var base_seed: int = int(Variants.number(profile["seed"]))
	for s: int in servers:
		var cfg: Dictionary = {"seed": base_seed + s}
		if soak != null and soak.has_method(&"scenario_config"):
			cfg.merge(Variants.dict(soak.call(&"scenario_config", s)), true)
		var scenario: Scenario = Scenario.create(cfg)
		if soak != null and soak.has_method(&"created"):
			soak.call(&"created", scenario)  # before anyone joins (NET-08's audit attaches here)
		for b: int in bots:
			var spec: String = brain_for.call(n)
			var tile: Vector2i = Vector2i.ZERO
			if soak != null and soak.has_method(&"spawn_tile"):
				tile = soak.call(&"spawn_tile", scenario, b)
			var bot: MinerHandle = scenario.add_bot("bot_%d_%d" % [s, b], tile, spec, base_seed * 100 + n)
			if not str(profile.get("link", "")).is_empty():
				var parts: PackedStringArray = str(profile["link"]).split(",")
				bot.link(parts[0].to_int(), parts[1].to_float())
			n += 1
		if soak != null and soak.has_method(&"prepare"):
			soak.call(&"prepare", scenario)
		scenario.step(ticks)
		var name: String = "server_%d" % s
		var input_log: String = out_dir.path_join(name + ".inputs.jsonl")
		scenario.save_replay(input_log)
		var state: RunState = scenario.run
		var stages: Dictionary = {}
		for stage: int in range(1, StageTable.STAGE_COUNT + 1):
			var key: String = TickTimer.stage_key(stage)
			var summary: Dictionary = state.timer.summary(key)
			stages[StageTable.stage_name(stage)] = {"p50": summary["p50"], "p99": summary["p99"], "max": state.timer.max_usec(key)}
		var tick: Dictionary = state.timer.summary(TickTimer.TICK)
		var stats: Dictionary = {"ticks": state.tick, "tick_usec": {"p50": tick["p50"], "p99": tick["p99"], "max": state.timer.max_usec(TickTimer.TICK)},
			"stages_usec": stages, "inputs": state.inputs.counters(), "input_log": input_log, "final_state_hash": state.state_hash()}
		var server_entry: Dictionary = {"index": s, "stats": stats, "input_log": input_log}
		if soak != null and soak.has_method(&"inspect"):
			server_entry["inspect"] = soak.call(&"inspect", scenario)
		Variants.array(report["servers"]).append(server_entry)
		Variants.array(report["applied_input_logs"]).append(input_log)
		for bot: MinerHandle in scenario.miners:
			var bytes_in: Dictionary = bot.capture.bytes_by_lane()
			var bytes_out: Dictionary = {}
			for lane: Variant in bot.connection.bytes_out.keys():
				bytes_out[Lane.lane_name(int(Variants.number(lane)))] = bot.connection.bytes_out[lane]
			Variants.array(report["bots"]).append({"bot": bot.name, "inputs_sent": bot.inputs_sent,
				"frames_received": bot.connection.frames_received, "bytes_in": bytes_in, "bytes_out": bytes_out})
			Variants.dict(report["bytes_per_client"])[bot.name] = {"in": bytes_in, "out": bytes_out}
		scenario.close()
