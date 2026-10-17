class_name CrewCensus
extends SimSystem
## DIR-05's crew census (CRT-01's CrewCountProvider): the conscious miners in the mine plus half
## a miner per Hired Hand (rounded down), leaving out anyone inside a sealed base camp and an
## absent player's miner waiting there; a lone human counts 1, whatever the Hands. A pure
## function of its inputs, recomputed at the end of every tick (stage 16, after MNR-03 applies
## falls and revives; the creatures read it the next tick at stage 7), with
## crew_count_changed only on a change, which equals recounting on the design's triggers (a
## fall, a coming round, a gate, a Hand). Server-only: never sent to a client.

signal crew_count_changed(old: int, new: int)

enum Lobby { FRIENDS = 0, PUBLIC = 1, SOLO = 2 }

## LFT-01: (entity) -> bool, inside base camp with every gate shut. Default: nobody.
var is_sealed_inside: Callable = func(_entity: int) -> bool: return false
## MOD-08: (entity) -> bool, a Hired Hand (a dropped player's miner included). Default: none.
var is_hand_driven: Callable = func(_entity: int) -> bool: return false
## MOD-08: (entity) -> bool, a Hired Hand's own miner (a dropped player's miner is not one): never
## counted for LFT-11's wipe or crew. Default: none.
var is_hired_hand: Callable = func(_entity: int) -> bool: return false
## NET-11: (entity) -> bool, an absent player's conscious miner waiting in base camp. Default: none.
var is_absent: Callable = func(_entity: int) -> bool: return false
## MOD-03's lobby kind; M1 runs are friends lobbies (Night Shift is solo).
var lobby: Lobby = Lobby.FRIENDS
## Humans at the start of the run: MOD-03's header, sealed when the run is created; for a run whose
## crew joined after it (a dev or fleet server), the most humans seen.
var humans_at_start: int = 0
var count: int = 0
## Per-miner seconds inside a sealed base camp (GDD §15.12), for telemetry.
var sealed_ticks: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.RECORD


func order() -> int:
	return 10


func system_name() -> String:
	return "CrewCensus"


func bind(run: RunState) -> void:
	if run.header.mode == ServerConfig.Mode.NIGHTSHIFT:
		lobby = Lobby.SOLO
	elif run.header.mode == ServerConfig.Mode.PUBLIC:
		lobby = Lobby.PUBLIC


func tick(run: RunState) -> void:
	if run.header.humans_at_start > 0:
		humans_at_start = run.header.humans_at_start
	else:
		humans_at_start = maxi(humans_at_start, humans(run).size())
	for e: int in miners(run):
		if Variants.flag(is_sealed_inside.call(e)):
			sealed_ticks[e] = int(Variants.number(sealed_ticks.get(e, 0))) + 1
	var now: int = compute(run)
	if now != count:
		var old: int = count
		count = now
		crew_count_changed.emit(old, now)


## Every miner entity, ascending.
func miners(run: RunState) -> Array[int]:
	var out: Array[int] = []
	for id: int in run.registry.ids():
		if run.registry.get_entity(id).kind == WorldIds.EntityKind.MINER:
			out.append(id)
	return out


func humans(run: RunState) -> Array[int]:
	var out: Array[int] = []
	for e: int in miners(run):
		if not Variants.flag(is_hand_driven.call(e)):
			out.append(e)
	return out


## Upright, Caught or Grabbed, with any overlay (MNR-03).
static func is_conscious(run: RunState, e: int) -> bool:
	if run.miner_state == null or run.miner_state.miner(e) == null:
		return true
	return run.miner_state.life(e) < MinerTransitions.Life.UNCONSCIOUS


## The crew count now.
func compute(run: RunState) -> int:
	for e: int in humans(run):
		if is_conscious(run, e) and AloneRules.is_lone_human(run, self, e):
			return Tuning.i(&"director.lone_human_crew_count")
	var people: int = 0
	var hands: int = 0
	for e: int in miners(run):
		if not is_conscious(run, e) or Variants.flag(is_sealed_inside.call(e)) or Variants.flag(is_absent.call(e)):
			continue
		if Variants.flag(is_hand_driven.call(e)):
			hands += 1
		else:
			people += 1
	return people + floori(hands * Tuning.f(&"director.hand_crew_weight") + 1e-9)


func sealed_seconds(e: int) -> float:
	return int(Variants.number(sealed_ticks.get(e, 0))) / Tuning.f(&"net.tick_hz")
