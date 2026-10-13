extends RefCounted
## Helpers for NET-04's scenarios: a lit road with miners, and frame bytes as captured.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


static func road(width: int = 40) -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(width), "#" + ".".repeat(width - 2) + "#",
		"#a" + ".".repeat(width - 3) + "#", "#" + ".".repeat(width - 2) + "#", "#".repeat(width)]))


static func lamp(s: Scenario, at: Vector2, radius: float = 5.5, owner: int = 0) -> int:
	return s.run.light.grid.add_point("gauze_lamp", 1, owner, 0, radius, 1.0, at, 0)


## Frame payloads a client received, in order.
static func frames(capture: RefCounted) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for m: Dictionary in capture.get(&"messages"):
		if int(Variants.number(m["type"])) == Protocol.Msg.FRAME:
			var bytes: PackedByteArray = m["bytes"]
			var payload: PackedByteArray = Protocol.unframe(bytes)["payload"]
			out.append(payload)
	return out
