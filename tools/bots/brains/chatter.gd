extends "res://tools/bots/brain.gd"
## Talks in bursts at a duty cycle (args "arg" = duty from 0 to 1, default 0.3): band-only voice
## frames with an Opus-sized dummy payload, no microphone. SND-07 defines real voice frames.

var _talking_until: int = -1
var _quiet_until: int = 0
var _band: int = 1


func think(ctx: BotContext) -> InputRecord:
	var duty: float = clampf(str(args.get("arg", "0.3")).to_float(), 0.0, 1.0)
	if ctx.tick >= _talking_until and ctx.tick >= _quiet_until:
		var burst: int = rng.range(20, 60)
		_talking_until = ctx.tick + burst
		_quiet_until = _talking_until + (roundi(burst * (1.0 - duty) / maxf(duty, 0.01)) if duty < 1.0 else 0)
		_band = rng.range(0, 2)
	if ctx.tick < _talking_until:
		ctx.voice.append([_band, VOICE_BYTES_PER_TICK])
	return held
