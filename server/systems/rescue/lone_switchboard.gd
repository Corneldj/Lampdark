class_name LoneSwitchboard
extends RefCounted
## RSC-09: the solo and lone-human substitutions (Gameplay §11.11), each registered by the system that
## applies it as a predicate (run, miner) -> bool, so a test can prove every one switches on and off
## with AloneRules.is_alone. Registered here: the self-rescue (RSC-03), the self-revive and the heard
## rule (RSC-09). DIR-03 registers the Pull's x0.5 (pull_half), LFT-04 the solo jobs (solo_jobs),
## HAZ-01 to HAZ-03 the lone struggles and the staple climb, when they land. Server-only.

## name -> Callable(run, miner) -> bool
var substitutions: Dictionary = {}


func register(sub_name: String, fn: Callable) -> void:
	substitutions[sub_name] = fn


## The substitutions in force for `miner` now, by name, sorted.
func active_substitutions(run: RunState, miner: int) -> Array[String]:
	var out: Array[String] = []
	var names: Array = substitutions.keys()
	names.sort()
	for raw: Variant in names:
		var fn: Callable = substitutions[raw]
		if Variants.flag(fn.call(run, miner)):
			out.append(str(raw))
	return out
