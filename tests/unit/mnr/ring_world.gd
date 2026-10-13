extends RefCounted
## Helpers for MNR-05's tests: two miners side by side in a lit room, and the ring's state.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const W = preload("res://tests/unit/mnr/belt_world.gd")


## Ann at spot a facing east, Bob a tile east of her facing west, the room lit.
static func pair(s: Scenario, lit: bool = true) -> Array:
	if lit:
		W.light(s)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(1, 0))
	ann.at(0).face(0.0)
	bob.at(0).face(180.0)
	s.step(4)
	return [ann, bob]


## Ann taps interact (opening the ring on what she faces).
static func tap(s: Scenario, h: MinerHandle) -> void:
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
	s.step(6)


## Picks option `id` from the list `h` was sent, then holds interact for `ticks`.
static func pick_and_hold(s: Scenario, h: MinerHandle, id: String, ticks: int) -> bool:
	var options: Array = Variants.array(h.connection.ring.get("options", []))
	var i: int = options.find(id)
	if i < 0:
		return false
	h.at(s.run.tick).press(ActionRecord.Kind.RING_CHOICE, i)
	s.step(3)
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, ticks)
	s.step(ticks + 4)
	return true
