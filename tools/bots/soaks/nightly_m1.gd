extends "res://tools/bots/soak.gd"
## The M1 nightly soak (FND-09, FND-04's nightly slot): 4 servers x 4 bots x 30 minutes, every
## brain, loopback. QA-03 grows it. Ticks must stay inside NET-01's p99 budget.


func setup(_ctx: Dictionary) -> void:
	profile = {"servers": 4, "bots": 4, "minutes": 30.0, "seed": 20260, "brains": ["wander", "chatter", "probe", "follow"], "link": ""}


func verify(report: Dictionary) -> Array[String]:
	var errors: Array[String] = standard_checks(report, roundi(float(Variants.number(profile["minutes"])) * 1200.0))
	var budget_usec: int = roundi(Tuning.f(&"net.tick_budget_ms_p99") * 1000.0) if Tuning.current.has_key(&"net.tick_budget_ms_p99") else 50000
	for raw: Variant in Variants.array(report.get("servers", [])):
		var s: Dictionary = Variants.dict(raw)
		var tick: Dictionary = Variants.dict(Variants.dict(s.get("stats", {})).get("tick_usec", {}))
		if int(Variants.number(tick.get("p99", 0))) > budget_usec:
			errors.append("server %s tick p99 %s us is over the %d us budget" % [s.get("index"), tick.get("p99"), budget_usec])
	return errors
