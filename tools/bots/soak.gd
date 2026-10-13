extends RefCounted
## The base of a soak script, tools/bots/soaks/<name>.gd (FND-09). A soak sets its profile in
## setup(), may watch the run in on_tick(), and judges the finished report in verify().

## servers, bots (per server), minutes, seed, brains (cycled over the bots), link ("" or "rtt,loss")
var profile: Dictionary = {"servers": 1, "bots": 2, "minutes": 1.0, "seed": 1, "brains": ["wander"], "link": ""}


func setup(_ctx: Dictionary) -> void:
	pass


## Every 50 ms while the soak runs: ctx holds elapsed_s, servers_running and bots_running.
func on_tick(_ctx: Dictionary) -> void:
	pass


## Returns the reasons the soak failed; empty when it passed.
func verify(_report: Dictionary) -> Array[String]:
	return [] as Array[String]


## The checks every soak wants: no crash, no unscripted disconnect, no input gaps at 0% loss,
## inputs and frames flowing, and every server's final hash recorded.
static func standard_checks(report: Dictionary, expect_ticks: int) -> Array[String]:
	var errors: Array[String] = []
	for raw: Variant in Variants.array(report.get("processes", [])):
		var p: Dictionary = Variants.dict(raw)
		if int(Variants.number(p.get("exit_code", -1))) != 0:
			errors.append("%s exited with %s (%s)" % [p.get("name"), p.get("exit_code"), p.get("ended", "")])
	for raw: Variant in Variants.array(report.get("servers", [])):
		var s: Dictionary = Variants.dict(raw)
		var stats: Dictionary = Variants.dict(s.get("stats", {}))
		if str(stats.get("final_state_hash", "")).is_empty():
			errors.append("server %s wrote no final state hash" % s.get("index"))
		var inputs: Dictionary = Variants.dict(stats.get("inputs", {}))
		for slot: Variant in inputs.keys():
			var c: Dictionary = Variants.dict(inputs[slot])
			if int(Variants.number(c.get("gaps", 0))) > 0 and str(report.get("link", "")).is_empty():
				errors.append("server %s slot %s: %s gaps in its inputs at 0%% loss" % [s.get("index"), slot, c.get("gaps")])
			if int(Variants.number(c.get("real", 0))) < expect_ticks * 0.95:
				errors.append("server %s slot %s: only %s real inputs of about %d" % [s.get("index"), slot, c.get("real"), expect_ticks])
	for raw: Variant in Variants.array(report.get("bots", [])):
		var b: Dictionary = Variants.dict(raw)
		if int(Variants.number(b.get("frames_received", 0))) < expect_ticks * 0.95:
			errors.append("%s received only %s frames" % [b.get("bot"), b.get("frames_received")])
	return errors
