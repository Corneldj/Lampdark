class_name StageTable
extends RefCounted
## The fixed per-tick stage order (NET-01, GDD §15.3) and the systems registered into it.
## Every system declares a stage and an order explicitly; a missing or duplicate pair fails
## at start-up, so the order is never incidental.

enum Stage {
	RECEIVE = 1,        ## NET-02: drain the transport; route inputs, acks and control
	INPUTS = 2,         ## NET-03: one input per miner
	MINERS = 3,         ## MNR-*: states, stamina, movement, items, lamp, carries, triggers
	WORLD = 4,          ## LFT, HAZ, GEN-15: gates, doors, lift jobs, phones, traps, hazards
	GENERATION = 5,     ## GEN-11, GEN-13: commit finished cells, replay diffs
	LIGHT_PASS_1 = 6,   ## VIS-02
	CREATURES = 7,      ## CRT-*, NET-06
	PACING = 8,         ## DIR-*
	FALLS = 9,          ## RSC-*
	LIGHT_PASS_2 = 10,  ## VIS-02: regions changed in stages 7-9
	ROAD_GRAPH = 11,    ## SND-01, SND-09
	VISIBILITY = 12,    ## VIS-03, VIS-10, VIS-04: cones, line of sight, seen sets
	DELTAS = 13,        ## NET-04, VIS-07
	ILLUSIONS = 14,     ## CRT-10: audio only, always last before encoding
	SEND = 15,          ## NET-04
	RECORD = 16,        ## NET-07 to NET-10: stream tap, lie log, run record, journal
}

const STAGE_COUNT: int = 16

## stage -> Array[SimSystem] sorted by order
var _by_stage: Dictionary = {}
var _pairs: Dictionary = {}


## Registers a system. Returns an error message, or "" on success.
func register(system: SimSystem) -> String:
	var stage: int = system.stage()
	var order: int = system.order()
	if stage < 1 or stage > STAGE_COUNT:
		return "%s declares no valid stage (got %d)" % [system.system_name(), stage]
	if order < 0:
		return "%s declares no order" % system.system_name()
	var pair: Vector2i = Vector2i(stage, order)
	if _pairs.has(pair):
		return "%s and %s both declare stage %d order %d" % [
			system.system_name(), _system_at(pair).system_name(), stage, order]
	_pairs[pair] = system
	var list: Array[SimSystem] = systems_in(stage)
	list.append(system)
	list.sort_custom(func(a: SimSystem, b: SimSystem) -> bool: return a.order() < b.order())
	_by_stage[stage] = list
	return ""


func systems_in(stage: int) -> Array[SimSystem]:
	var list: Array[SimSystem] = []
	if _by_stage.has(stage):
		list.assign(Variants.array(_by_stage[stage]))
	return list


## Every system in run order.
func all_systems() -> Array[SimSystem]:
	var out: Array[SimSystem] = []
	for stage: int in range(1, STAGE_COUNT + 1):
		out.append_array(systems_in(stage))
	return out


static func stage_name(stage: int) -> String:
	return str(Stage.find_key(stage)).to_lower()


func _system_at(pair: Vector2i) -> SimSystem:
	var system: SimSystem = _pairs[pair]
	return system
