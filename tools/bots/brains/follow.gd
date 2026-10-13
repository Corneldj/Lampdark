extends "res://tools/bots/brain.gd"
## Follows a miner it can perceive. Like a player it knows only its stream, so it needs NET-04's
## decoder to see anyone; until then it stands still and says so in its stats.


func setup(seed_value: int, brain_args: Dictionary) -> void:
	super(seed_value, brain_args)
	notes.append("follow waits on NET-04's client decoder; standing still")
