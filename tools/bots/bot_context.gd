extends RefCounted
## What a bot brain knows and does on one client tick (FND-09). A bot knows only its own
## stream, like a player: the messages the server sent it, never the world.

## The bot's own client tick count and the newest frame tick it has received.
var tick: int = 0
var frame_tick: int = -1
## Messages received since the last tick: {lane, type, bytes}.
var received: Array[Dictionary] = []
## Out: one-shot actions [kind, arg, aim] and voice frames [band, payload_bytes] for this tick.
var actions: Array[Array] = []
var voice: Array[Array] = []


func clear_outputs() -> void:
	actions.clear()
	voice.clear()
