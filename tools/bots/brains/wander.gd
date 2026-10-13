extends "res://tools/bots/brain.gd"
## A seeded walk: a new heading and gait every 0.5 to 3 s, sometimes a pause, facing where it goes.

var _until: int = 0


func think(ctx: BotContext) -> InputRecord:
	if ctx.tick >= _until:
		_until = ctx.tick + rng.range(10, 60)
		if rng.chance_ppm(200000):
			held.move_dir = InputRecord.NO_DIRECTION
		else:
			var heading: float = rng.range(0, 359)
			held.move_dir = direction_byte(heading)
			held.facing = facing_u16(heading)
			held.gait = rng.pick_weighted(PackedInt64Array([2, 6, 2])) as InputRecord.Gait
	return held
