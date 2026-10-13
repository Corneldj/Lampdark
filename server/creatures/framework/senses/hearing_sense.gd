class_name HearingSense
extends RefCounted
## The Tapper's one sense: the Road Graph (SND-01) as a creature listener, current deliveries
## only. Illusions never reach it (they are client audio, CRT-10). CRT-08 extends it.

var listener_id: int
## [{type, level_np, apparent...}] heard since the last take().
var _heard: Array[Dictionary] = []
var _run: RunState


func _init(run: RunState, id: int) -> void:
	_run = run
	listener_id = id
	if run.noise != null:
		run.noise.creature_hooks.append(_on_delivery)


func listen_at(tile: Vector2i, multiplier: float) -> void:
	if _run.noise != null:
		_run.noise.set_creature_listener(listener_id, tile, multiplier)


func take() -> Array[Dictionary]:
	var out: Array[Dictionary] = _heard
	_heard = []
	return out


func _on_delivery(event: NoiseSystem.Event, delivery: Dictionary) -> void:
	if int(Variants.number(delivery.get("listener", -1))) != listener_id:
		return
	var heard: Dictionary = delivery.duplicate()
	heard["type"] = event.type
	_heard.append(heard)
