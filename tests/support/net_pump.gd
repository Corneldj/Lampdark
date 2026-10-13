extends RefCounted
## Helpers for real-time transport tests: pump everything until a condition holds.


## Calls step() every millisecond until done() is true or timeout_s passes. Returns done().
static func until(step: Callable, done: Callable, timeout_s: float) -> bool:
	var deadline: int = Time.get_ticks_usec() + roundi(timeout_s * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		step.call()
		var finished: bool = done.call()
		if finished:
			return true
		OS.delay_usec(1000)
	var finished_at_end: bool = done.call()
	return finished_at_end
