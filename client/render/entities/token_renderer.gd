class_name TokenRenderer
extends RefCounted
## VIS-06 (§5.2): a fringe token is one faceless shape per size class, radially symmetric (so no
## facing ever shows), animated from speed alone: the phase advances with distance travelled, so a
## miner and the Stythe at the same speed draw the same frames, and a heap and the sleeping moth
## (both large and motionless) draw identically. A token record carries no kind; this never sees one.

## Radius (tiles) per SeenKind.Size: NONE, MINER, LARGE, LARGE_MOTIONLESS, SMALL.
const RADIUS: Array[float] = [0.0, 0.32, 0.55, 0.55, 0.18]
const FRAMES: int = 4
const POINTS: int = 16
## Animation cycles per tile travelled.
const CYCLES_PER_TILE: float = 1.2

## token -> [last position (Vector2), phase (0-1)]
var _state: Dictionary = {}


## Advances each token's phase by the distance it moved since the last frame; returns token -> frame.
func update(positions: Dictionary) -> Dictionary:
	var frames: Dictionary = {}
	for raw: Variant in positions.keys():
		var p: Vector2 = positions[raw]
		var s: Array = Variants.array(_state.get(raw, [p, 0.0]))
		var last: Vector2 = s[0]
		var phase: float = fposmod(float(Variants.number(s[1])) + last.distance_to(p) * CYCLES_PER_TILE, 1.0)
		_state[raw] = [p, phase]
		frames[raw] = floori(phase * FRAMES) % FRAMES
	for raw: Variant in _state.keys().duplicate():
		if not positions.has(raw):
			_state.erase(raw)
	return frames


## The token's outline (tiles, centred on it) for a size class and frame: a disc that swells and
## settles with the frame, the same in every direction.
static func shape(size_class: int, frame: int) -> PackedVector2Array:
	var r: float = RADIUS[clampi(size_class, 0, RADIUS.size() - 1)] * (1.0 + 0.08 * sin(TAU * float(frame) / FRAMES))
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in POINTS:
		out.append(Vector2.from_angle(TAU * float(i) / POINTS) * r)
	return out
