extends "res://tools/bots/soak.gd"
## NET-08's per-push audit (FND-04): 60 s of four bots in the scenario kit, walking, turning and
## talking through a lit stand-in mine with a Moth, every record each is sent judged by the stream
## audit. Fails on any violation, or if a rule judged nothing. The stand-in mine gives way to
## GEN-03's grey box (and later a fixed seed) when it lands.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
## Rules a clean run must exercise.
const MUST_JUDGE: Array[String] = ["frame", "tile", "geometry", "entity", "glow", "audio", "voice", "handshake"]

## scenario index -> its audit
var audits: Dictionary = {}
var _made: int = 0


func setup(_ctx: Dictionary) -> void:
	profile = {"servers": 1, "bots": 4, "minutes": 1.0, "seed": 8080, "brains": ["wander", "chatter", "wander", "lamp"], "link": ""}


## Two halls joined by a pillared road, a brick wall with a gap, alcoves: shadows, corners, the margin.
static func mine() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("#".repeat(48))
	for y: int in 14:
		var row: String = "#"
		for x: int in 46:
			var c: String = "."
			if (x % 7 == 3) and (y % 5 == 2):
				c = "#"  # pillars
			if x == 23 and y != 6 and y != 7:
				c = "B"  # a brick wall with a gap
			if y == 0 and x > 30 and x < 36:
				c = "#"
			row += c
		row += "#"
		rows.append(row)
	rows.append("#".repeat(48))
	var row6: String = rows[7]
	rows[7] = row6.substr(0, 1) + "a" + row6.substr(2)
	return FixtureMap.from_ascii(rows)


func scenario_config(_server: int) -> Dictionary:
	return {"fixture": mine()}


func created(scenario: RefCounted) -> void:
	var audit: StreamAudit = StreamAudit.new()
	var run: RunState = scenario.get(&"run")
	var net: ServerNet = scenario.get(&"net")
	audit.attach(run, net)
	audits[_made] = audit
	_made += 1


func spawn_tile(scenario: RefCounted, bot: int) -> Vector2i:
	var fixture: FixtureMap = scenario.get(&"fixture")
	return fixture.spot("a") + Vector2i(2 + bot * 5, 0)


func prepare(scenario: RefCounted) -> void:
	var run: RunState = scenario.get(&"run")
	var fixture: FixtureMap = scenario.get(&"fixture")
	var a: Vector2i = fixture.spot("a")
	for at: Vector2 in [Vector2(6.5, -4.5), Vector2(18.5, 3.5), Vector2(30.5, -3.5), Vector2(40.5, 4.5)]:
		run.light.grid.add_point("gauze_lamp", LbLightGrid.COLOUR_AMBER, 0, 0, 4.5, 1.0, Vector2(a) + at, 0)
	for raw: Variant in scenario.get(&"miners"):
		var h: RefCounted = raw
		var id: int = int(Variants.number(h.get(&"entity_id")))
		run.light.grid.add_point("gauze_lamp", LbLightGrid.COLOUR_AMBER, id, 0, 3.5, 1.0, run.registry.get_entity(id).position, 0)
	scenario.call(&"place_creature", WorldIds.EntityKind.MOTH, a + Vector2i(34, 5))


func inspect(_scenario: RefCounted) -> Dictionary:
	var audit: StreamAudit = audits[_made - 1]
	return audit.report()


func verify(report: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for raw: Variant in Variants.array(report.get("servers", [])):
		var server: Dictionary = Variants.dict(raw)
		var audit: Dictionary = Variants.dict(server.get("inspect", {}))
		var count: int = int(Variants.number(audit.get("violations", -1)))
		if count != 0:
			errors.append("server %s: %d stream audit violations" % [server.get("index"), count])
			for v: Variant in Variants.array(audit.get("first", [])).slice(0, 20):
				var d: Dictionary = Variants.dict(v)
				errors.append("  tick %s client %s %s [%s]: %s (reproduce: seed %s)" % [d.get("tick"), d.get("client"), d.get("record"), d.get("rule"),
					d.get("detail"), profile["seed"]])
		var checked: Dictionary = Variants.dict(audit.get("checked", {}))
		for rule: String in MUST_JUDGE:
			if int(Variants.number(checked.get(rule, 0))) == 0:
				errors.append("server %s: the audit judged no %s records" % [server.get("index"), rule])
	return errors
