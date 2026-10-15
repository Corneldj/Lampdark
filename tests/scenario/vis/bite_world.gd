extends RefCounted
## VIS-10's scenarios: a long road, Ann at its west end facing east with her lamp lit, and a Stythe
## stand-in placed in the dark before anyone sees it, then moved to the fringe of her pool (lit
## 0.12-0.30, so seen as a token unless the bite takes it). `active` turns its tell on.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

var s: Scenario = null
var ann: MinerHandle = null
var stythe: int = 0
var active: bool = false
var thin: bool = false


static func road() -> FixtureMap:
	var rows: PackedStringArray = ["#".repeat(34), "#" + ".".repeat(32) + "#", "#" + ".".repeat(32) + "#",
		"#..a" + ".".repeat(29) + "#", "#" + ".".repeat(32) + "#", "#" + ".".repeat(32) + "#", "#".repeat(34)]
	return FixtureMap.from_ascii(rows)


func build(scn: Scenario) -> void:
	s = scn
	# The Stythe is held content (CRT-13/14): a STYTHE entity is all vision needs to see one.
	stythe = s.run.registry.create(WorldIds.EntityKind.STYTHE, Vector2(s.fixture.spot("a") + Vector2i(28, 0)) + Vector2(0.5, 0.5)).id
	s.step(1)
	ann = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	s.step(1)
	L.lit_in_hand(s, ann)
	s.run.vision.bite_sources = func(_r: RunState) -> Array:
		return [{"position": s.run.registry.get_entity(stythe).position, "thin": thin}] if active else []
	s.step(2)


## The first tile east of Ann lit in [lo, hi) (thousandths of the light grid's value, 0-1).
func fringe_tile(lo: float = 0.13, hi: float = 0.27) -> Vector2i:
	var a: Vector2i = s.fixture.spot("a")
	for dx: int in range(1, 30):
		var t: Vector2i = a + Vector2i(dx, 0)
		var v: float = s.run.light.light_at(t)
		if v >= lo and v < hi:
			return t
	return Vector2i(-1, -1)


func put_stythe(tile: Vector2i) -> void:
	s.run.registry.get_entity(stythe).position = Vector2(tile) + Vector2(0.5, 0.5)


func frame_tiles() -> Dictionary:
	var out: Dictionary = {}
	var f: Dictionary = s.run.vision.frame_for(ann.slot)
	var xs: PackedInt32Array = f["tiles"]["x"]
	var ys: PackedInt32Array = f["tiles"]["y"]
	for i: int in xs.size():
		out[Vector2i(xs[i], ys[i])] = true
	return out


func margin_tiles() -> Dictionary:
	var out: Dictionary = {}
	var f: Dictionary = s.run.vision.frame_for(ann.slot)
	var xs: PackedInt32Array = f["margin_tiles"]["x"]
	var ys: PackedInt32Array = f["margin_tiles"]["y"]
	for i: int in xs.size():
		out[Vector2i(xs[i], ys[i])] = true
	return out


func token_count() -> int:
	var f: Dictionary = s.run.vision.frame_for(ann.slot)
	var sizes: PackedByteArray = f["tokens"]["size"]
	var msizes: PackedByteArray = f["margin_tokens"]["size"]
	return sizes.size() + msizes.size()
