extends RefCounted
## SND-12's tests: a long road, lamps lit in hand, a signal pressed as the wheel sends it.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


## A road `length` tiles long and 3 wide, 'a' at its west end; `rib_at` (> 0) closes it there.
static func road(length: int = 50, rib_at: int = 0) -> FixtureMap:
	var rows: PackedStringArray = ["#".repeat(length + 2)]
	for y: int in 3:
		var row: String = "#" + ("..a" if y == 1 else "...") + ".".repeat(length - 3) + "#"
		if rib_at > 0:
			row = row.substr(0, 3 + rib_at) + "#" + row.substr(4 + rib_at)
		rows.append(row)
	rows.append("#".repeat(length + 2))
	return FixtureMap.from_ascii(rows)


static func miner(s: Scenario, name: String, tile: Vector2i, facing_deg: float, lit: bool = true) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, tile, {"facing_deg": facing_deg})
	h.brain = null
	h.at(s.run.tick).face(facing_deg)  # a scripted miner faces as its input says
	s.step(1)
	if lit:
		L.lit_in_hand(s, h)
	return h


## Presses a lamp signal as the wheel sends it (the slice's centre, a middle-ring pick).
static func signal_press(s: Scenario, h: MinerHandle, kind: LampSignalKind.Kind) -> void:
	var i: int = LampSignalKind.WHEEL.find(kind)
	var angle: float = fposmod(i * 360.0 / LampSignalKind.WHEEL.size() - 90.0, 360.0)
	h.at(s.run.tick + 1).press(ActionRecord.Kind.LAMP_SIGNAL, Intents.wheel_arg_distance(0.6), angle)


static func tap_press(s: Scenario, h: MinerHandle, at_tick: int = -1) -> void:
	h.at(s.run.tick + 1 if at_tick < 0 else at_tick).press(ActionRecord.Kind.TAP_ROCK, 0, 0.0)
