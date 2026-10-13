class_name CreatureState
extends RefCounted
## CRT-01: one state of a creature, as data. Each creature ticket lists its states and marks
## which fill a place under the cap (DIR-05), which are entered by the creature's own choice
## (blocked by the relax), which play its tell and which can be hit.

var name: StringName = &""
## Active under the cap while in this state (laying, homing and collecting never are).
var fills_cap_place: bool = false
## Entering it begins a hunt by choice: the relax blocks the entry (Gameplay §7.1, §10.3).
var chosen_entry: bool = false
var plays_tell: bool = false
## The revolver can hit the body in this state (the Tapper's arm only in WindUp, Pin, ReStrike).
var hittable: bool = true


static func make(state_name: StringName, opts: Dictionary = {}) -> CreatureState:
	var s: CreatureState = CreatureState.new()
	s.name = state_name
	s.fills_cap_place = Variants.flag(opts.get("fills_cap_place", false))
	s.chosen_entry = Variants.flag(opts.get("chosen_entry", false))
	s.plays_tell = Variants.flag(opts.get("plays_tell", false))
	s.hittable = Variants.flag(opts.get("hittable", true))
	return s
