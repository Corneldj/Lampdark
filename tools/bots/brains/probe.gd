extends "res://tools/bots/brain.gd"
## NET-12's probe: an about-turn every 2 s, a lamp-up every 5 s (back down 1 s later) and a
## 0.5 s burst of speech every 3 s, each at a known tick so its arrival can be timed.


func think(ctx: BotContext) -> InputRecord:
	if ctx.tick % 40 == 0:
		held.facing = (held.facing + 32768) & 0xFFFF
	if ctx.tick % 100 == 0:
		held.desired = 2 << 1
	elif ctx.tick % 100 == 20:
		held.desired = 1 << 1
	if ctx.tick % 60 < 10:
		ctx.voice.append([1, VOICE_BYTES_PER_TICK])
	return held
