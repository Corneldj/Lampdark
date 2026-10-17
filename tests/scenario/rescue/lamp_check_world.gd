extends RefCounted
## Helpers for RSC-06's scenarios: §3.9's last ride to the surface (Harry, Ellis, Wilf and Nell up;
## Ada Rowe, Lamp 114, dragged down and kept beyond a gate), a crew wiped below, and what each
## client was sent of Lamp Check.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const K = preload("res://tests/unit/lift/cage_world.gd")
const D = preload("res://tests/scenario/director/draught_world.gd")

## MOD-03's roster, stubbed: miner name -> [name, lamp number].
const ROSTER: Dictionary = {
	"ada": ["Ada Rowe", 114],
	"harry": ["Harry", 108],
	"ellis": ["Ellis", 131],
	"wilf": ["Wilfred Dodd", 207],
	"nell": ["Nell", 162],
	"ann": ["Ann Coxon", 301],
	"bob": ["Bob Tait", 302],
	"cid": ["Cid Laws", 303],
	"dot": ["Dot Raine", 304],
}
## 1:41:20 of the run clock, when the bell starts.
const BELL_AT_S: float = 6080.0


## The first shift to its surface: [the four who came up, Ada]. Lamp Check opens there.
## `during_bell` (scenario, the four) runs once they have pulled, before the cage goes.
static func first_shift(s: Scenario, during_bell: Callable = Callable()) -> Array:
	K.ready(s)
	var cord: Vector2i = K.cord_tiles(s)[0]
	var spots: Array[Vector2i] = deck_spots(s)
	var names: Array[String] = ["harry", "ellis", "wilf", "nell"]
	var crew: Array[MinerHandle] = []
	for i: int in names.size():
		crew.append(s.add_miner(names[i], spots[i]))
	var ada: MinerHandle = s.add_miner("ada", beyond_a_gate(s))
	name_them(s, crew + [ada])
	s.step(2)
	s.run.falls.fall_unconscious(s.run, ada.entity_id, FallCause.Cause.DRAG)
	WorldCoords.ring_override = 3
	s.step(2)
	WorldCoords.ring_override = -1
	for h: MinerHandle in crew:
		K.move_to(s, h, cord)
		K.face(s, h, cord)
		s.step(2)
		K.pull(s, h)
		K.move_to(s, h, spots[crew.find(h)])
	var rang: int = K.bells(s)[0].tick
	s.run.outcomes.start_tick = rang - roundi(BELL_AT_S * Tuning.f(&"net.tick_hz"))
	if during_bell.is_valid():
		during_bell.call(s, crew)
	s.run_until(func(sc: Scenario) -> bool: return sc.run.outcomes.ended, K.bell_ticks() + ShaftRide.ride_ticks() + 20)
	return [crew, ada]


## A crew of `names` in a hall, every one knocked down: the wipe.
static func wiped(s: Scenario, names: Array[String]) -> Array[MinerHandle]:
	var spots: Array[String] = ["a", "b", "c", "d", "e", "f"]
	var crew: Array[MinerHandle] = []
	for i: int in names.size():
		crew.append(s.add_miner(names[i], s.fixture.spot(spots[i])))
	name_them(s, crew)
	s.step(2)
	for h: MinerHandle in crew:
		s.run.falls.fall_unconscious(s.run, h.entity_id, FallCause.Cause.ROOF_FALL)
		s.step(2)
	return crew


static func hall() -> FixtureMap:
	return D.hall()


static func name_them(s: Scenario, handles: Array) -> void:
	var by_id: Dictionary = {}
	for raw: Variant in handles:
		var h: MinerHandle = raw
		by_id[h.entity_id] = ROSTER[h.name]
	s.run.outcomes.identity_of = func(m: int) -> Dictionary:
		var who: Array = Variants.array(by_id.get(m, ["", 0]))
		return {"name": who[0], "lamp_number": who[1]}


## Deck tiles out of the cord's reach, farthest first.
static func deck_spots(s: Scenario) -> Array[Vector2i]:
	var near: Array[Vector2i] = K.cord_tiles(s)
	var deck: Rect2i = s.run.cage.deck
	var cord: Vector2 = s.run.cage.cord_point
	var out: Array[Vector2i] = []
	for y: int in range(deck.position.y, deck.end.y):
		for x: int in range(deck.position.x, deck.end.x):
			if not near.has(Vector2i(x, y)) and s.run.mine.native.is_walkable(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) + Vector2(0.5, 0.5)).distance_to(cord) > (Vector2(b) + Vector2(0.5, 0.5)).distance_to(cord))
	return out


## The tile by a gate's outside lever: out in the mine.
static func beyond_a_gate(s: Scenario) -> Vector2i:
	for g: Gate in s.run.base_camp.gate_system.gates:
		if g.levers.has("outside"):
			return g.levers["outside"]
	return Vector2i.ZERO


## Every LAMP_CHECK message a client received, decoded, in order.
static func received(h: MinerHandle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in h.capture.messages:
		if int(Variants.number(m["type"])) != Protocol.Msg.LAMP_CHECK:
			continue
		var raw: PackedByteArray = m["bytes"]
		var payload: PackedByteArray = Protocol.unframe(raw)["payload"]
		var d: Dictionary = LampCheckWire.read(payload)
		d["tick"] = m["tick"]
		out.append(d)
	return out


## The client's Lamp Check messages of one kind (OPEN or END).
static func of_kind(h: MinerHandle, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in received(h):
		if str(d.get("kind", "")) == kind:
			out.append(d)
	return out


## A player presses Ready.
static func press_ready(h: MinerHandle) -> void:
	h.connection.send(Lane.Id.CONTROL, LampCheckWire.ready(), Protocol.Msg.LAMP_CHECK)
