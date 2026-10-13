class_name Gate
extends RefCounted
## LFT-02: one of base camp's three steel gates (GEN-02's gateways): its state, its two levers,
## the lever actions in flight, its holders and its public auto-close timer. The tiles' GEN-01
## barrier is the truth the world reads; this record is what the diff log keeps. Server-only:
## nothing here is sent; a client sees a gate only as geometry (NET-04, VIS-05).

## One miner's lever action. It keeps its own runner rather than MNR-04's TimedAction: a flip
## turns every other action on the gate into a hold, and a kept hold holds the gate open.
class LeverAction:
	extends RefCounted
	var actor: int = 0
	var lever: Vector2i = Vector2i.ZERO
	var started_tick: int = 0
	var ticks_done: int = 0


var side: String = ""
var tiles: Array[Vector2i] = []
var outward: Vector2i = Vector2i.ZERO
var barrier: int = 0
## "inside" and "outside" -> the lever's tile.
var levers: Dictionary = {}
var open: bool = false
## The tick of the last open flip (the auto-close timer runs from it); -1 while shut.
var opened_tick: int = -1
## The spill's VIS-02 source id while open, else 0.
var spill: int = 0
## The doorway's own light while open (base camp's level over the doorway tiles; the spill runs
## from their outer edge), else 0.
var doorway_light: int = 0
## actor entity -> LeverAction.
var actions: Dictionary = {}
## Miners keeping interact held on a lever after their action ended (finished, jammed or overtaken
## by a flip). They hold the gate while it is open; their hold starts no new action.
var holders: Dictionary = {}


static func from_spec(spec: Dictionary) -> Gate:
	var g: Gate = Gate.new()
	g.side = str(spec["side"])
	for raw: Variant in Variants.array(spec["tiles"]):
		var t: Vector2i = raw
		g.tiles.append(t)
	g.outward = spec["outward"]
	g.barrier = int(Variants.number(spec["barrier"]))
	g.levers = Variants.dict(spec["levers"]).duplicate()
	return g


## The middle doorway tile.
func middle() -> Vector2i:
	return tiles[tiles.size() / 2]


## The clang's origins: the floor either side of the middle doorway tile, so both sides hear the
## steel sheet whether it ends open or shut.
func clang_origins() -> Array[Vector2i]:
	return [middle() - outward, middle() + outward] as Array[Vector2i]


## True if a circle at `p` of radius `r` overlaps any doorway tile.
func overlaps(p: Vector2, r: float) -> bool:
	for t: Vector2i in tiles:
		var nearest: Vector2 = Vector2(clampf(p.x, t.x, t.x + 1.0), clampf(p.y, t.y, t.y + 1.0))
		if p.distance_squared_to(nearest) < r * r:
			return true
	return false


## The lever within `reach` of `p`, nearest first (inside before outside on a tie), or null.
func lever_near(p: Vector2, reach: float) -> Variant:
	var best: Variant = null
	var best_d: float = INF
	for key: String in ["inside", "outside"]:
		if not levers.has(key):
			continue
		var at: Vector2i = levers[key]
		var d: float = p.distance_to(Vector2(at) + Vector2(0.5, 0.5))
		if d <= reach and d < best_d:
			best = at
			best_d = d
	return best


func to_record() -> Dictionary:
	return {"side": side, "open": open, "opened_tick": opened_tick}
