class_name DarkSense
extends RefCounted
## The Stythe's one sense: the grid's dark (VIS-02) and the unheard timer (SND). Current state
## only. The unheard timer's provider arrives with SND's voice ticket; until then nobody is
## unheard. CRT-12 to CRT-14 extend it.

const DARK_BELOW: float = 0.12

## (miner_entity) -> seconds unheard. Default: 0.
var unheard_s: Callable = func(_miner: int) -> float: return 0.0
var _run: RunState


func _init(run: RunState) -> void:
	_run = run


func is_dark(tile: Vector2i) -> bool:
	return _run.light == null or _run.light.light_at(tile) < DARK_BELOW


func seconds_unheard(miner_entity: int) -> float:
	return Variants.number(unheard_s.call(miner_entity))
