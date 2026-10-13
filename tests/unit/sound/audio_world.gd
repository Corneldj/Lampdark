extends RefCounted
## SND-03 test helpers: a hall with two miners, every audio record the server hands NET-04 captured.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


static func hall(w: int = 30) -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(w + 2)])
	for _y: int in 5:
		rows.append("#" + ".".repeat(w) + "#")
	rows.append("#".repeat(w + 2))
	return FixtureMap.from_ascii(rows)


## Captures (slot, record) pairs alongside NET-04's sink; returns the list it fills.
static func capture(s: Scenario) -> Array[Array]:
	var got: Array[Array] = []
	var forward: Callable = s.run.audio.sink
	s.run.audio.sink = func(slot: int, r: AudioRecord) -> void:
		got.append([slot, r])
		if forward.is_valid():
			forward.call(slot, r)
	return got
