class_name ShaftRide
extends RefCounted
## LFT-10: the ride up the shaft (Gameplay §3.6). It takes lift.ride_s of progress, counted only
## while the cage moves, up a shaft lift.shaft_depth_m deep: the walls are bare rock below
## lift.shaft_brick_above_m (GEN-02's shaft_lining_at at depth × (1 - progress / ride)), so the
## first half, and brick above. A Tapper's pin trips the governor and stops it in the dark until the
## pin ends; then it goes on. At the top it surfaces.
##
## The ride zone: an off-plane cell (RIDE_CELL) holding a copy of the deck ringed by the shaft's
## walls, joined to nothing (its own Road Graph zone, no emergency light). Its wall ring is a collapse
## alternate, rock standing and brick fallen, swapped when the lining turns. Server-only: progress is
## never sent as a number; riders see only the walls and the cage's look.

## Far off the plane (20,000 tiles out: well inside the wire's and float32's range) and never
## generated. Its tiles are ring 0 (WorldCoords): the shaft over base camp, not the deep mine.
const RIDE_CELL: Vector2i = WorldCoords.RIDE_CELL
## The deck copy's north-west tile within the ride cell, and the wall ring's thickness.
const DECK_AT: Vector2i = Vector2i(8, 7)
const RING: int = 2
const WALL_COLLAPSE: int = 1

var progress_ticks: int = 0
## The pin (a grab id) holding the cage, 0 while it moves.
var stopped_by: int = 0
var departed_at: int = -1
var surfaced_at: int = -1


static func ride_ticks() -> int:
	return roundi(Tuning.f(&"lift.ride_s") * Tuning.f(&"net.tick_hz"))


## How deep the cage is now (m).
func depth_m() -> float:
	return Tuning.f(&"lift.shaft_depth_m") * (1.0 - float(progress_ticks) / float(ride_ticks()))


func is_bare_rock() -> bool:
	return departed_at >= 0 and surfaced_at < 0 and Basecamp.shaft_lining_at(depth_m()) == WorldIds.TileMaterial.ROCK


func is_moving() -> bool:
	return departed_at >= 0 and surfaced_at < 0 and stopped_by == 0


func is_surfaced() -> bool:
	return surfaced_at >= 0


## One tick of the ride: true on the tick it reaches the top.
func step(tick: int) -> bool:
	if not is_moving():
		return false
	progress_ticks += 1
	if progress_ticks >= ride_ticks():
		surfaced_at = tick
		return true
	return false


func stop_for_pin(pin_id: int) -> void:
	if is_moving():
		stopped_by = pin_id


## The pin ended: the cage goes on (another pin's end changes nothing).
func resume(pin_id: int) -> bool:
	if stopped_by != 0 and stopped_by == pin_id:
		stopped_by = 0
		return true
	return false


## The ride cell for a deck `size` tiles: rock but for the deck copy, its wall ring a collapse that
## turns rock to brick. `brick`: already lined (a resume above the lining's change).
static func cell_data(size: Vector2i, brick: bool) -> LbCellData:
	var rows: Array = []
	for y: int in WorldIds.CELL_TILES:
		var row: Array = []
		row.resize(WorldIds.CELL_TILES)
		row.fill("#")
		rows.append(row)
	var zones: Array = []
	for y: int in WorldIds.CELL_TILES:
		var z: Array = []
		z.resize(WorldIds.CELL_TILES)
		z.fill(0)
		zones.append(z)
	var standing: Array = []
	var fallen: Array = []
	for y: int in range(DECK_AT.y - RING, DECK_AT.y + size.y + RING):
		for x: int in range(DECK_AT.x - RING, DECK_AT.x + size.x + RING):
			var on_deck: bool = x >= DECK_AT.x and x < DECK_AT.x + size.x and y >= DECK_AT.y and y < DECK_AT.y + size.y
			if on_deck:
				rows[y][x] = "."
				zones[y][x] = 1
			else:
				standing.append([y * WorldIds.CELL_TILES + x, "#"])
				fallen.append([y * WorldIds.CELL_TILES + x, "B"])
	var tiles: Array = []
	for row: Array in rows:
		tiles.append("".join(PackedStringArray(row)))
	var file: Dictionary = {"format": 1, "cell": [RIDE_CELL.x, RIDE_CELL.y], "tiles": tiles, "zones": zones, "anchors": [],
		"barriers": [], "collapses": [{"id": WALL_COLLAPSE, "standing": standing, "fallen": fallen, "is_fallen": brick}],
		"road_graph": {"zones": [{"id": 1, "kind": "road"}], "portals": []}}
	return CellFile.from_dict(file, "ride")


## The deck copy's north-west corner, world tiles.
static func deck_origin() -> Vector2i:
	return RIDE_CELL * WorldIds.CELL_TILES + DECK_AT


## The rock tiles of the wall ring touching the deck copy (where a Tapper in the shaft waits).
static func wall_faces(size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var o: Vector2i = deck_origin()
	for x: int in size.x:
		out.append(o + Vector2i(x, -1))
		out.append(o + Vector2i(x, size.y))
	for y: int in size.y:
		out.append(o + Vector2i(-1, y))
		out.append(o + Vector2i(size.x, y))
	return out


func save_state() -> Dictionary:
	return {"progress": progress_ticks, "stopped_by": stopped_by, "departed_at": departed_at, "surfaced_at": surfaced_at}


func load_state(state: Dictionary) -> void:
	progress_ticks = int(Variants.number(state.get("progress", 0)))
	stopped_by = int(Variants.number(state.get("stopped_by", 0)))
	departed_at = int(Variants.number(state.get("departed_at", -1)))
	surfaced_at = int(Variants.number(state.get("surfaced_at", -1)))
