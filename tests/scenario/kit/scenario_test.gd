extends GutTest
## The base for scenario tests (FND-09): extends GutTest with the kit's assertions. Scenarios
## made through make() are closed after each test, which hands the wall clock back.
##
##   extends "res://tests/scenario/kit/scenario_test.gd"

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const Capture = preload("res://tests/scenario/kit/capture.gd")
const KitCreature = preload("res://tests/scenario/kit/kit_creature.gd")

var _made: Array[Scenario] = []


func make(cfg: Dictionary = {}) -> Scenario:
	var s: Scenario = Scenario.create(cfg)
	_made.append(s)
	return s


func after_each() -> void:
	for s: Scenario in _made:
		s.close()
	_made.clear()


## predicate(state: Scenario.StateView) -> bool
func assert_state(s: Scenario, predicate: Callable, text: String = "") -> void:
	var holds: bool = predicate.call(s.state)
	assert_true(holds, text if not text.is_empty() else "the authoritative state matches")


## Some message the server sent this client satisfies predicate(message: Dictionary)
## ({tick, usec, lane, type, bytes}).
func assert_stream_has(h: MinerHandle, predicate: Callable, text: String = "") -> void:
	var found: bool = false
	for m: Dictionary in h.capture.messages:
		if predicate.call(m):
			found = true
			break
	assert_true(found, text if not text.is_empty() else "%s's stream has a matching message" % h.name)


## No message the server sent this client satisfies predicate (the negative rules: darkness is
## missing data, illusions reach only their target).
func assert_stream_never(h: MinerHandle, predicate: Callable, text: String = "") -> void:
	var offending: int = -1
	for i: int in h.capture.messages.size():
		if predicate.call(h.capture.messages[i]):
			offending = i
			break
	assert_eq(offending, -1, text if not text.is_empty() else "%s's stream never has a matching message" % h.name)


## A Road Graph event of at least `np` within some ticks. SND-02 logs events; pending until then.
func assert_event(s: Scenario, np: float, within_ticks: int) -> void:
	if s.state.road_graph_events().is_empty():
		pending("assert_event(%.1f np within %d ticks) waits on SND-02's event log" % [np, within_ticks])
		return
	var found: bool = false
	for raw: Variant in s.state.road_graph_events():
		var e: Dictionary = Variants.dict(raw)
		if float(Variants.number(e.get("np", 0.0))) >= np and int(Variants.number(e.get("tick", -1))) >= s.run.tick - within_ticks:
			found = true
	assert_true(found, "a Road Graph event of %.1f np within %d ticks" % [np, within_ticks])


## NET-08's stream audit on one client's capture; pending until it exists.
func assert_audit_clean(h: MinerHandle) -> void:
	pending("assert_audit_clean(%s) waits on NET-08's checker" % h.name)


## Marks a test pending until a ticket lands.
func pending_until(ticket: String, what: String) -> void:
	pending("%s waits on %s" % [what, ticket])
