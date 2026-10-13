class_name FirstLamp
extends RefCounted
## LFT-01: the run's one gauze lamp, Hung on base camp's lamp_hook at run creation (never on a
## resume): a full fill (basecamp.first_lamp_fills), basecamp.first_lamp_notches flint notches,
## wick normal, unlit. The emergency lamps are the only light in the mine at the start, so it is
## no flame yet. It lies as an MNR-04 item (a gauze lamp carrying this state) that any miner may
## pick up; MNR-06 adopts this record as its lamp entity's state.

var entity: int = 0
var fills: int = 1
var notches: int = 3
var wick: int = 1
var lit: bool = false
var hook: Vector2i = Vector2i.ZERO


static func spawn(run: RunState, hook_tile: Vector2i) -> FirstLamp:
	var lamp: FirstLamp = FirstLamp.new()
	lamp.hook = hook_tile
	lamp.fills = Tuning.i(&"basecamp.first_lamp_fills")
	lamp.notches = Tuning.i(&"basecamp.first_lamp_notches")
	var state: Dictionary = {"fills": lamp.fills, "notches": lamp.notches, "wick": lamp.wick, "lit": lamp.lit, "hung": true}
	if run.inventory != null:
		var item: Item = run.inventory.world.make(ItemKinds.Kind.GAUZE_LAMP, 1, state)
		lamp.entity = run.inventory.world.put(run, item, Vector2(hook_tile) + Vector2(0.5, 0.5))
	else:
		lamp.entity = run.registry.create(WorldIds.EntityKind.ITEM, Vector2(hook_tile) + Vector2(0.5, 0.5)).id
	return lamp
