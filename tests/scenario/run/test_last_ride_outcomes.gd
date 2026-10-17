extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-11 (Gameplay §3.9, §3.8, §11.9): the first shift's last ride. Ada Rowe (Lamp 114) lies kept
## beyond a gate; Harry, Ellis, Wilf and Nell board and pull, the hold bell rings 20 s
## for nobody from 1:41:20, the cage leaves at 1:41:40 and reaches the surface at 1:42:20. Harry stood
## in the Third Level at 36:00. The record: Up 4 of 5, Left Below: Ada Rowe, Lamp 114, deepest ring 3,
## 1 h 42 min below; and nothing of it, or of who is below, reaches a client before Lamp Check.

const K = preload("res://tests/unit/lift/cage_world.gd")

## MOD-03's roster, stubbed: miner name -> [name, lamp number].
const ROSTER: Dictionary = {
	"ada": ["Ada Rowe", 114],
	"harry": ["Harry", 108],
	"ellis": ["Ellis", 131],
	"wilf": ["Wilfred Dodd", 207],
	"nell": ["Nell", 162],
}
## 1:41:20 of the run clock, when the bell starts.
const BELL_AT_S: float = 6080.0


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	WorldCoords.ring_override = -1


func test_up_4_of_5_ada_rowe_left_below() -> void:
	var s: Scenario = make({"seed": 11601, "fixture": K.E.T.C.scenario_fixture()})
	K.ready(s)
	var cage: Cage = s.run.cage
	var hz: float = Tuning.f(&"net.tick_hz")
	# The four wait on the deck away from the cord, Ada out beyond a gate.
	var cord: Vector2i = K.cord_tiles(s)[0]
	var spots: Array[Vector2i] = _deck_spots(s)
	assert_true(spots.size() >= 4, "room on the deck for four")
	var names: Array[String] = ["harry", "ellis", "wilf", "nell"]
	var crew: Array[MinerHandle] = []
	for i: int in names.size():
		crew.append(s.add_miner(names[i], spots[i]))
	var ada: MinerHandle = s.add_miner("ada", _beyond_a_gate(s))
	var by_id: Dictionary = {}
	for h: MinerHandle in crew + [ada]:
		by_id[h.entity_id] = ROSTER[h.name]
	s.run.outcomes.identity_of = func(m: int) -> Dictionary:
		var who: Array = by_id[m]
		return {"name": who[0], "lamp_number": who[1]}
	s.step(2)
	s.run.miner_state.fall_unconscious(ada.entity_id, "kept")
	# 36:00, a blue cap on Harry's flame: the Third Level.
	WorldCoords.ring_override = 3
	s.step(2)
	WorldCoords.ring_override = -1
	assert_eq(s.run.outcomes.deepest_ring, 3)
	s.step(2)
	assert_false(s.run.outcomes.ended, "four stand")
	# Four aboard pull the cord, in turn at its tile.
	for h: MinerHandle in crew:
		K.move_to(s, h, cord)
		K.face(s, h, cord)
		s.step(2)
		K.pull(s, h)
		K.move_to(s, h, spots[crew.find(h)])
	assert_eq(cage.state, Cage.State.BELL, "the hold bell, for nobody")
	var rang: int = K.bells(s)[0].tick
	s.run.outcomes.start_tick = rang - roundi(BELL_AT_S * hz)
	var ended: Array[Dictionary] = []
	s.run.outcomes.run_ended.connect(func(rec: Dictionary) -> void: ended.append(rec))
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return s.run.outcomes.ended, K.bell_ticks() + ShaftRide.ride_ticks() + 20))
	assert_eq(ended.size(), 1)
	var rec: Dictionary = ended[0]
	assert_eq(cage.state, Cage.State.SURFACED)
	# The card: Up 4 of 5. Left Below: Ada Rowe, Lamp 114. Deepest: the Third Level. Below 1 h 42 min.
	assert_eq(int(Variants.number(rec["up_count"])), 4, "Up 4")
	assert_eq(int(Variants.number(rec["crew_size"])), 5, "of 5")
	assert_false(Variants.flag(rec["wipe"]))
	var below: Array[String] = []
	for raw: Variant in Variants.array(rec["miners"]):
		var m: Dictionary = Variants.dict(raw)
		if str(m["outcome"]) == "left_below":
			below.append("%s, Lamp %d" % [str(m["name"]), int(Variants.number(m["lamp_number"]))])
		else:
			assert_eq(str(m["outcome"]), "escaped")
		assert_false(Variants.flag(m["dead"]))
	assert_eq(below, ["Ada Rowe, Lamp 114"] as Array[String], "Left Below: Ada Rowe, Lamp 114")
	assert_eq(int(Variants.number(rec["deepest_ring"])), 3, "Deepest: the Third Level")
	var t: float = Variants.number(rec["time_below_s"])
	assert_eq([floori(t / 3600.0), floori(fmod(t, 3600.0) / 60.0)], [1, 42], "Below 1 h 42 min")
	assert_almost_eq(t, (s.run.outcomes.ended_tick - s.run.outcomes.start_tick) / hz, 1e-6, "the run's own clock")
	assert_almost_eq(t, BELL_AT_S + (K.bell_ticks() + ShaftRide.ride_ticks()) / hz, 0.2, "1:42:20 at the surface")
	# Before Lamp Check, no client heard any of it.
	var leaks: Array[String] = []
	for h: MinerHandle in crew + [ada]:
		for msg: Dictionary in h.capture.messages:
			if int(Variants.number(msg["tick"])) >= s.run.outcomes.ended_tick:
				continue
			var bytes: PackedByteArray = msg["bytes"]
			for word: String in ["left_below", "escaped", "up_count", "crew_size", "deepest_ring", "time_below_s", "Ada Rowe"]:
				if _carries(bytes, word):
					leaks.append("%s got '%s' (a %s)" % [h.name, word, Protocol.Msg.find_key(int(Variants.number(msg["type"])))])
	assert_eq(leaks, [] as Array[String], "outcomes and who is below stay on the server")


## Deck tiles out of the cord's reach, farthest first.
func _deck_spots(s: Scenario) -> Array[Vector2i]:
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
func _beyond_a_gate(s: Scenario) -> Vector2i:
	for g: Gate in s.run.base_camp.gate_system.gates:
		if g.levers.has("outside"):
			return g.levers["outside"]
	assert_true(false, "a gate with an outside lever")
	return Vector2i.ZERO


## Whether `bytes` holds `word`'s UTF-8 bytes at a byte boundary.
static func _carries(bytes: PackedByteArray, word: String) -> bool:
	var hay: String = bytes.hex_encode()
	var needle: String = word.to_utf8_buffer().hex_encode()
	var at: int = hay.find(needle)
	while at >= 0:
		if at % 2 == 0:
			return true
		at = hay.find(needle, at + 1)
	return false
