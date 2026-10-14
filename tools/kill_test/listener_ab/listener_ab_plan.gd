extends RefCounted
## QA-01 criterion 5's trial plan (Gameplay §6.10): per tester, TRIALS trials of each listener
## condition, the facing-relative ears ("facing") and screen-up ("screen_up"), shuffled together.
## Within each condition half the sounds play north and half south, half a tone and half a footstep.
## Blind: the screen and the moderator see only the codes "A" and "B", whose meaning is drawn per
## tester and kept only in the results file. The same seed always makes the same plan.

const TRIALS: int = 20
const CONDITIONS: Array[String] = ["facing", "screen_up"]
const SOURCES: Array[String] = ["north", "south"]
const SOUNDS: Array[String] = ["tone", "step"]


## {codes: {"A": condition, "B": condition}, trials: [{index, code, condition, source, sound}]}.
static func make(tester_seed: int, trials_per_condition: int = TRIALS) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = tester_seed
	var a_is_facing: bool = rng.randi() % 2 == 0
	var codes: Dictionary = {"A": "facing" if a_is_facing else "screen_up", "B": "screen_up" if a_is_facing else "facing"}
	var trials: Array[Dictionary] = []
	for code: String in ["A", "B"]:
		for i: int in trials_per_condition:
			trials.append({"code": code, "condition": codes[code], "source": SOURCES[i % 2], "sound": SOUNDS[(i / 2) % 2]})
	# Fisher-Yates with the tester's generator.
	for i: int in range(trials.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: Dictionary = trials[i]
		trials[i] = trials[j]
		trials[j] = t
	for i: int in trials.size():
		trials[i]["index"] = i
	return {"codes": codes, "trials": trials}


## What the screen may show for a trial: its number and code, never the condition.
static func shown(trial: Dictionary) -> String:
	return "Trial %d (%s)" % [int(Variants.number(trial["index"])) + 1, str(trial["code"])]
