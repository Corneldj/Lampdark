extends "res://tools/bots/soak.gd"
## NET-08's per-push audit (FND-04): 60 s of four bots in the scenario kit on GEN-03's grey box,
## walking, turning and talking from base camp out through the open gates, with the grey box's Moth,
## Tapper, coat heaps and items placed; every record each is sent is judged by the stream audit.
## Fails on any violation, or if a rule judged nothing.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const MAP: String = "m1_greybox"
## Rules a clean run must exercise.
const MUST_JUDGE: Array[String] = ["frame", "tile", "geometry", "entity", "glow", "audio", "voice", "handshake"]

## scenario index -> its audit
var audits: Dictionary = {}
var _made: int = 0


func setup(_ctx: Dictionary) -> void:
	profile = {"servers": 1, "bots": 4, "minutes": 1.0, "seed": 8080, "brains": ["wander", "chatter", "wander", "lamp"], "link": ""}


func scenario_config(_server: int) -> Dictionary:
	return {"fixture": MAP}


func created(scenario: RefCounted) -> void:
	var audit: StreamAudit = StreamAudit.new()
	var run: RunState = scenario.get(&"run")
	var net: ServerNet = scenario.get(&"net")
	audit.attach(run, net)
	audits[_made] = audit
	_made += 1


## Base camp's floor, spread out (its gates are open: the kit installs no gate system).
func spawn_tile(_scenario: RefCounted, bot: int) -> Vector2i:
	return [Vector2i(6, 6), Vector2i(13, 6), Vector2i(6, 13), Vector2i(13, 13)][bot % 4]


func prepare(scenario: RefCounted) -> void:
	var run: RunState = scenario.get(&"run")
	FixedMapLoader.populate(run, MAP, false)  # the Moth, the Tapper, coat heaps and items
	for raw: Variant in scenario.get(&"miners"):
		var h: RefCounted = raw
		var id: int = int(Variants.number(h.get(&"entity_id")))
		run.light.grid.add_point("gauze_lamp", LbLightGrid.COLOUR_AMBER, id, 0, 4.5, 1.0, run.registry.get_entity(id).position, 0)
	for at: Vector2 in [Vector2(10.5, -12.5), Vector2(28.5, -16.5), Vector2(30.5, 9.5), Vector2(4.5, 24.5)]:
		run.light.grid.add_point("gauze_lamp", LbLightGrid.COLOUR_AMBER, 0, 0, 4.5, 1.0, at, 0)


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
