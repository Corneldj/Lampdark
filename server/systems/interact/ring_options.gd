class_name RingOptions
extends RefCounted
## MNR-05: the ring's option registry. Each option names the target life states it is offered on,
## whether it needs both (every participant holding: never with a Hired Hand), a check of what the
## actor carries and the target allows (an option the actor cannot perform is never shown), and the
## timed action it runs. Owners register at startup (MNR-06 douse, MNR-07 share and pass, RSC-01 take
## and lift, RSC-02 cure, HAZ-01 to HAZ-03 free, CRT-09 the silent pull, MNR-14 lay).

class Option:
	extends RefCounted
	var id: String = ""
	var states: Array[int] = []
	var both: bool = false
	## (run, actor, target) -> bool
	var actor_check: Callable = Callable()
	## (run, actor, target) -> TimedAction
	var make: Callable = Callable()


## id -> Option, in registration order through `order`.
var options: Dictionary = {}
var order: Array[String] = []


## `after`: an option id this one is listed right after (the design's order), else last.
func register(id: String, target_states: Array[int], actor_check: Callable, make: Callable, both: bool = false, after: String = "") -> void:
	var o: Option = Option.new()
	o.id = id
	o.states = target_states
	o.actor_check = actor_check
	o.make = make
	o.both = both
	if not options.has(id):
		var at: int = order.find(after) if not after.is_empty() else -1
		if at >= 0:
			order.insert(at + 1, id)
		else:
			order.append(id)
	options[id] = o


## What `actor` is offered on `target` now, in registration order.
func offered(run: RunState, actor: int, target: int) -> Array[String]:
	var out: Array[String] = []
	var life: int = run.miner_state.life(target) if run.miner_state != null and run.miner_state.miner(target) != null \
		else MinerTransitions.Life.UPRIGHT
	var hand_involved: bool = BothHold.involves_hand(run, [actor, target] as Array[int])
	for id: String in order:
		var o: Option = options[id]
		if not o.states.has(life) or (o.both and hand_involved):
			continue
		if o.actor_check.is_valid() and not Variants.flag(o.actor_check.call(run, actor, target)):
			continue
		out.append(id)
	return out
