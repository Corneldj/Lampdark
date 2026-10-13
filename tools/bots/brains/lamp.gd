extends "res://tools/bots/brain.gd"
## MNR-06's lamp soak brain: a seeded walk that works its lamp. Every 1 to 4 s it may close or open
## the shutter or step the wick; now and then it sets the lamp down and, standing still, picks it
## straight up again, or swaps belt slots (Use on a slot), each a held control for longer than the
## action takes.

var _walk_until: int = 0
var _act_until: int = 0
var _hold_bit: int = 0
var _hold_until: int = 0
## After a set-down: the tick to pick the lamp back up, and to walk on.
var _pick_up_at: int = -1


func think(ctx: BotContext) -> InputRecord:
	if ctx.tick >= _hold_until:
		held.holds &= ~_hold_bit
		_hold_bit = 0
	# Standing still and facing the same way while a control is held or a pick-up waits, so the
	# lamp it set down stays in its cone.
	if _pick_up_at >= 0:
		held.move_dir = InputRecord.NO_DIRECTION
		if ctx.tick >= _pick_up_at:
			_pick_up_at = -1
			_hold(InputRecord.HOLD_INTERACT, ctx.tick + 25)
			_walk_until = ctx.tick + 30
			_act_until = ctx.tick + 30
		return held
	if _hold_bit != 0:
		return held
	if ctx.tick >= _walk_until:
		_walk_until = ctx.tick + rng.range(10, 60)
		if rng.chance_ppm(300000):
			held.move_dir = InputRecord.NO_DIRECTION
		else:
			var heading: float = rng.range(0, 359)
			held.move_dir = direction_byte(heading)
			held.facing = facing_u16(heading)
			held.gait = rng.pick_weighted(PackedInt64Array([3, 6, 1])) as InputRecord.Gait
	if ctx.tick >= _act_until:
		_act_until = ctx.tick + rng.range(20, 80)
		match rng.range(0, 9):
			0, 1, 2:
				held.desired ^= 1
			3, 4:
				held.desired = (held.desired & ~6) | (rng.range(0, 2) << 1)
			5, 6:
				# Opened first: a shuttered lamp lies dark, and only feeling finds it again.
				held.desired &= ~1
				_hold(InputRecord.HOLD_SET_DOWN, ctx.tick + 25)
				_pick_up_at = ctx.tick + 30
			7:
				_hold(InputRecord.HOLD_INTERACT, ctx.tick + 25)
			8:
				held.set_selected_slot(rng.range(0, 3))
				_hold(InputRecord.HOLD_USE, ctx.tick + 6)
	return held


func _hold(bit: int, until: int) -> void:
	held.holds &= ~_hold_bit
	_hold_bit = bit
	_hold_until = until
	held.move_dir = InputRecord.NO_DIRECTION
	held.holds |= bit
