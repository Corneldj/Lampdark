class_name PullReader
extends RefCounted
## DIR-03's Pull, read-only: it steers whom a creature chooses and where it drifts, never what it
## senses. Until DIR-03 exists every miner's Pull is 0.

var _gate: HuntGate


func _init(gate: HuntGate) -> void:
	_gate = gate


func pull_of(miner_entity: int) -> int:
	return int(Variants.number(_gate.pull_of.call(miner_entity)))
