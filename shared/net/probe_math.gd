class_name ProbeMath
extends RefCounted
## NET-12: the probes' arithmetic, shared by the client probes, the server's probe log and the
## report. Percentiles by nearest rank (the smallest value with at least p% of samples at or below).


static func percentile(values: Array[float], p: float) -> float:
	if values.is_empty():
		return NAN
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var rank: int = clampi(ceili(p / 100.0 * sorted.size()), 1, sorted.size())
	return sorted[rank - 1]


static func stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"n": 0, "p50": NAN, "p95": NAN, "p99": NAN, "max": NAN}
	var top: float = values[0]
	for v: float in values:
		top = maxf(top, v)
	return {"n": values.size(), "p50": percentile(values, 50.0), "p95": percentile(values, 95.0), "p99": percentile(values, 99.0),
		"max": top}


## Pass when there are samples and the p95 is under `target_ms`.
static func passes(s: Dictionary, target_ms: float) -> bool:
	return int(Variants.number(s.get("n", 0))) > 0 and float(Variants.number(s.get("p95", INF))) < target_ms
