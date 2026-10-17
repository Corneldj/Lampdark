class_name SignalCord
extends RefCounted
## LFT-10: the signal cord's votes (Gameplay §3.6, §13.9, §13.10). A conscious miner aboard pulls
## with one interact on the cord; the vote stands while they stay aboard and conscious (Proposed). A
## pull before the run-up ends is not stored. Hired Hands never pull or count; the unconscious and the
## dead never count. The cage leaves when the pullers aboard number more than half of the run's
## conscious miners: floor(N / 2) + 1, recounted every tick. In a public run, once the engine has run
## lift.cord_public_after_s, N is the conscious miners aboard instead. Server-only: no count, no
## threshold and no timer is ever sent; the bell is the only signal.

## miner -> the tick they pulled.
var votes: Dictionary = {}


## Whether an entity's centre lies on the deck.
static func aboard(run: RunState, entity: int, deck: Rect2i) -> bool:
	var e: SimEntity = run.registry.get_entity(entity)
	return e != null and deck.has_point(Vector2i(floori(e.position.x), floori(e.position.y)))


static func conscious(run: RunState, miner: int) -> bool:
	return run.miner_state == null or run.miner_state.miner(miner) == null or run.miner_state.life(miner) < MinerTransitions.Life.UNCONSCIOUS


## The miners who count: conscious, and no Hand (`only_aboard`: those on the deck).
static func counted(run: RunState, deck: Rect2i, only_aboard: bool) -> Array[int]:
	var out: Array[int] = []
	for id: int in run.registry.ids():
		var e: SimEntity = run.registry.get_entity(id)
		if e == null or e.kind != WorldIds.EntityKind.MINER or ToolsParts.is_hand(run, id) or not conscious(run, id):
			continue
		if only_aboard and not aboard(run, id, deck):
			continue
		out.append(id)
	return out


## N: the run's conscious miners, or (public, after lift.cord_public_after_s of running) those aboard.
static func electorate(run: RunState, deck: Rect2i) -> int:
	var public: bool = run.header.mode == ServerConfig.Mode.PUBLIC
	var late: bool = run.engine != null and run.engine.running_s(run) >= Tuning.f(&"lift.cord_public_after_s") - 1e-9
	return counted(run, deck, public and late).size()


static func required(run: RunState, deck: Rect2i) -> int:
	return electorate(run, deck) / 2 + 1


## Why `miner` may not pull now, or "" (the pull counts).
func why_not(run: RunState, miner: int, deck: Rect2i) -> String:
	if ToolsParts.is_hand(run, miner):
		return "a Hand"
	if not conscious(run, miner):
		return "unconscious"
	if not aboard(run, miner, deck):
		return "not aboard"
	if run.engine == null or not run.engine.run_up_complete(run):
		return "run-up"
	return ""


func pull(run: RunState, miner: int) -> void:
	if not votes.has(miner):
		votes[miner] = run.tick


## Votes stand only while their miner stays aboard and conscious.
func prune(run: RunState, deck: Rect2i) -> void:
	for raw: Variant in votes.keys():
		var m: int = int(Variants.number(raw))
		if not run.registry.has(m) or not aboard(run, m, deck) or not conscious(run, m) or ToolsParts.is_hand(run, m):
			votes.erase(raw)


## The standing pullers, and whether they make the majority.
func pullers() -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in votes.keys():
		out.append(int(Variants.number(raw)))
	out.sort()
	return out


func majority(run: RunState, deck: Rect2i) -> bool:
	return not votes.is_empty() and votes.size() >= required(run, deck)


func clear() -> void:
	votes.clear()


func save_state() -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in votes.keys():
		out[str(raw)] = votes[raw]
	return out


func load_state(state: Dictionary) -> void:
	votes.clear()
	for raw: Variant in state.keys():
		votes[int(str(raw))] = int(Variants.number(state[raw]))
