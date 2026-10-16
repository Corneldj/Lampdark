@tool
class_name TemplateStub
extends Node2D
## A stub: an opening on the footprint's outer edge, at `offset` tiles along its edge, up to
## `max_width` tiles wide, its throat `depth` tiles deep (all floor; 0 means the standard depth,
## mine.stub_throat_depth_tiles). The generator narrows the throat to its socket's width or fills
## it with rock as a blind heading (GEN-05). Its position is not read: the fields say where it is,
## and the outline it draws shows it.

static var _standard_depth: int = 0

@export var cell: Vector2i = Vector2i.ZERO:
	set(value):
		cell = value
		queue_redraw()
@export_enum("north", "east", "south", "west") var edge: String = "north":
	set(value):
		edge = value
		queue_redraw()
@export_enum("5:5", "10:10", "15:15") var offset: int = 10:
	set(value):
		offset = value
		queue_redraw()
@export_range(1, 3) var max_width: int = 3:
	set(value):
		max_width = value
		queue_redraw()
@export_range(0, 10) var depth: int = 0:
	set(value):
		depth = value
		queue_redraw()
## A point of interest's door.
@export var door: bool = false


## The standard throat depth from tuning, read once (for drawing; the export reads its own rules).
static func standard_depth() -> int:
	if _standard_depth == 0:
		var tuning: TuningSet = TuningSet.new()
		tuning.load_directory(TuningSet.DATA_DIR)
		_standard_depth = maxi(1, roundi(tuning.f(&"mine.stub_throat_depth_tiles")))
	return _standard_depth


## The throat's footprint tiles at its full width, with `standard` for a depth of 0.
func throat(standard: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var first: int = offset - max_width / 2  # GEN-05's opening rule: 2 wide covers offset - 1 and offset
	var base: Vector2i = cell * WorldIds.CELL_TILES
	var last: int = WorldIds.CELL_TILES - 1
	for d: int in (depth if depth > 0 else standard):
		for i: int in max_width:
			var along: int = first + i
			match edge:
				"north":
					out.append(base + Vector2i(along, d))
				"south":
					out.append(base + Vector2i(along, last - d))
				"west":
					out.append(base + Vector2i(d, along))
				_:
					out.append(base + Vector2i(last - d, along))
	return out


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_set_transform(-position)
	var colour: Color = Color(0.3, 1.0, 0.4, 0.9) if not door else Color(0.4, 0.7, 1.0, 0.9)
	for t: Vector2i in throat(standard_depth()):
		draw_rect(Rect2(Vector2(t * TemplateSource.TILE_PX), Vector2.ONE * TemplateSource.TILE_PX), colour, false, 2.0)
