extends RefCounted
## NET-12's criterion-4 run, inside FND-09's scenario kit (the accelerated path: the virtual clock,
## the kit's emulated links, clients polled every 10 ms): four probe bots (tools/bots/brains/probe)
## with NET-05's prediction and lit lamps, each turning about every 2 s and changing wick every 5 s,
## in the open room of the two-cell test map (GEN-03's grey box once it lands). The contents are
## six miners without lamps standing 2-4 tiles from the probes (Proposed layout): unlit, so only
## the probes' light shows them; some sit in a probe's margin, some past it, some behind it.
## (Lying items are not entity tokens, and a miner with a lit lamp is always drawn.) Every client
## poll feeds each bot's ClientProbes; the server's ProbeLog gives tick cost and the bandwidth.
## Returns the summary; probe_report.gd writes it out.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")

## The room in the test map's cell (0, 0): the probe bots and the unlit miners around them.
const BOT_TILES: Array[Vector2i] = [Vector2i(5, 13), Vector2i(16, 14), Vector2i(10, 12), Vector2i(11, 15)]
## Some inside a probe's margin at its normal wick (3 tiles: drawn at once), some just past it (3.6
## tiles: inside the wicked-up light only, so the margin's head start decides when they draw).
const CONTENT_TILES: Array[Vector2i] = [Vector2i(8, 13), Vector2i(8, 15), Vector2i(13, 12), Vector2i(7, 14), Vector2i(14, 13),
	Vector2i(13, 14)]


## args: rtt_ms (120), loss (0.02, a fraction), seconds (60), seed (1), plant_margin_delay_ms (0),
## overrides (tuning key -> value, for what-if runs).
static func run(args: Dictionary) -> Dictionary:
	var rtt: int = int(Variants.number(args.get("rtt_ms", 120)))
	var loss: float = float(Variants.number(args.get("loss", 0.02)))
	var seconds: float = float(Variants.number(args.get("seconds", 60.0)))
	var s: Scenario = Scenario.create({"seed": int(Variants.number(args.get("seed", 1))), "fixture": "test", "slots": 12,
		"overrides": Variants.dict(args.get("overrides", {}))})
	var probes: Array[ClientProbes] = []
	var bots: Array[MinerHandle] = []
	for i: int in BOT_TILES.size():
		var h: MinerHandle = s.add_bot("probe_%d" % i, BOT_TILES[i], "probe", 900 + i)
		h.link(rtt, loss * 100.0)
		s.enable_prediction(h)
		var at: Vector2 = s.run.registry.get_entity(h.entity_id).position
		var lamp: GauzeLamp = s.run.lamps.create(s.run, 1.0, 3, true, LampRules.WICK_NORMAL, at)
		s.run.lamps.pick_up(s.run, lamp, h.entity_id)
		bots.append(h)
		probes.append(ClientProbes.new())
	for i: int in CONTENT_TILES.size():
		s.add_miner("contents_%d" % i, CONTENT_TILES[i])
	var delay_ms: float = float(Variants.number(args.get("plant_margin_delay_ms", 0.0)))
	if delay_ms > 0.0:
		s.run.replication.plant_margin_delay(ceili(delay_ms / 50.0))
	var warmup: int = 40
	s.step(warmup)
	var origin_usec: int = Transport.now_usec()
	s.on_poll = func(_sc: Scenario) -> void:
		for i: int in bots.size():
			var h: MinerHandle = bots[i]
			if h.connection == null or h.connection.view == null or h.prediction == null:
				continue
			probes[i].on_frame(Transport.now_usec(), h.connection.view, h.prediction.lamp(), h.prediction.state.facing)
	var bytes_down_start: Array[Dictionary] = []
	var bytes_up_start: Array[Dictionary] = []
	for h: MinerHandle in bots:
		bytes_down_start.append(h.connection.bytes_in.duplicate())
		bytes_up_start.append(h.connection.bytes_out.duplicate())
	s.step(roundi(seconds * 20.0))
	s.on_poll = Callable()
	var elapsed: float = (Transport.now_usec() - origin_usec) / 1000000.0
	var light: Array[float] = []
	var turn: Array[float] = []
	var held_max: int = 0
	var cost: float = 0.0
	var rows: Array[String] = ["bot,kind,ms,at_ms"]
	var per_bot: Array[Dictionary] = []
	for i: int in probes.size():
		var p: ClientProbes = probes[i]
		for smp: Dictionary in p.samples:
			var ms: float = float(Variants.number(smp["ms"]))
			if str(smp["kind"]) == "turn":
				turn.append(ms)
			else:
				light.append(ms)
			rows.append("%d,%s,%.1f,%.1f" % [i, smp["kind"], ms, (int(Variants.number(smp["at_usec"])) - origin_usec) / 1000.0])
		var sm: Dictionary = p.summary()
		held_max = maxi(held_max, int(Variants.number(sm["turn_held_frames_max"])))
		cost = maxf(cost, float(Variants.number(sm["cost_usec_per_frame"])))
		var h: MinerHandle = bots[i]
		per_bot.append({"probes": sm, "down": ProbeLog.kbps(_delta(h.connection.bytes_in, bytes_down_start[i]), elapsed),
			"up": ProbeLog.kbps(_delta(h.connection.bytes_out, bytes_up_start[i]), elapsed)})
	var light_s: Dictionary = ProbeMath.stats(light)
	var turn_s: Dictionary = ProbeMath.stats(turn)
	var light_target: float = Tuning.f(&"net.probe_light_to_contents_p95_ms")
	var turn_target: float = Tuning.f(&"net.probe_about_turn_p95_ms")
	var out: Dictionary = {
		"rtt_ms": rtt, "loss": loss, "seconds": elapsed, "plant_margin_delay_ms": delay_ms,
		"light_to_contents": light_s, "about_turn": turn_s, "about_turn_held_frames_max": held_max,
		"light_pass": ProbeMath.passes(light_s, light_target), "turn_pass": ProbeMath.passes(turn_s, turn_target),
		"held_pass": held_max <= 1, "probe_cost_usec_per_frame_max": cost,
		"tick_cost": ProbeLog.tick_cost(s.run), "bots": per_bot,
		"mouth_to_ear": "not measured: SND-07's voice forwarding carries the probe's marked frame",
		"targets": {"light_p95_ms": light_target, "turn_p95_ms": turn_target, "held_frames": 1},
		"csv": "\n".join(rows) + "\n",
	}
	out["criterion4_pass"] = Variants.flag(out["light_pass"]) and Variants.flag(out["turn_pass"]) and Variants.flag(out["held_pass"])
	s.close()
	return out


static func _delta(now: Dictionary, before: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in now.keys():
		out[raw] = float(Variants.number(now[raw])) - float(Variants.number(before.get(raw, 0)))
	return out


## The report in Markdown.
static func markdown(r: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Criterion 4 probe report (NET-12)")
	lines.append("")
	lines.append("Link: %d ms round trip, %.1f%% loss each way; %.0f s of four probe bots%s." % [r["rtt_ms"], float(Variants.number(r["loss"])) * 100.0,
		r["seconds"], "; planted %d ms margin delay" % roundi(float(Variants.number(r["plant_margin_delay_ms"]))) if float(Variants.number(r["plant_margin_delay_ms"])) > 0.0 else ""])
	lines.append("")
	lines.append("| Probe | Samples | p50 | p95 | Max | Target | Result |")
	lines.append("|---|---|---|---|---|---|---|")
	for key: String in ["light_to_contents", "about_turn"]:
		var st: Dictionary = r[key]
		var target: float = float(Variants.number(Variants.dict(r["targets"])["light_p95_ms" if key == "light_to_contents" else "turn_p95_ms"]))
		var ok: bool = Variants.flag(r["light_pass" if key == "light_to_contents" else "turn_pass"])
		lines.append("| %s | %d | %.0f ms | %.0f ms | %.0f ms | p95 under %.0f ms | %s |" % [key.replace("_", " "), st["n"], st["p50"], st["p95"], st["max"], target,
			"pass" if ok else "FAIL"])
	lines.append("| about-turn held geometry | | | | %d frames | the next frame | %s |" % [r["about_turn_held_frames_max"], "pass" if Variants.flag(r["held_pass"]) else "FAIL"])
	lines.append("")
	lines.append("**Criterion 4: %s**" % ("PASS" if Variants.flag(r["criterion4_pass"]) else "FAIL"))
	lines.append("")
	var tc: Dictionary = r["tick_cost"]
	lines.append("Tick cost (p50 / p95 / p99, budget at p99): whole tick %s / %s / %s us (5000); visibility %s / %s / %s us (2000); Road Graph %s / %s / %s us (500)." % [
		tc["tick"]["p50_us"], tc["tick"]["p95_us"], tc["tick"]["p99_us"], tc["visibility"]["p50_us"], tc["visibility"]["p95_us"], tc["visibility"]["p99_us"],
		tc["road_graph"]["p50_us"], tc["road_graph"]["p95_us"], tc["road_graph"]["p99_us"]])
	lines.append("")
	for i: int in Variants.array(r["bots"]).size():
		var b: Dictionary = r["bots"][i]
		lines.append("Bot %d: down %.1f kbps (+ voice %.1f), up %.1f kbps (+ voice %.1f)." % [i, b["down"]["game_kbps"], b["down"]["voice_kbps"],
			b["up"]["game_kbps"], b["up"]["voice_kbps"]])
	lines.append("")
	lines.append("Probe cost: %.1f us a frame at most (budget 100 us). Mouth-to-ear: %s." % [r["probe_cost_usec_per_frame_max"], r["mouth_to_ear"]])
	return "\n".join(lines) + "\n"
