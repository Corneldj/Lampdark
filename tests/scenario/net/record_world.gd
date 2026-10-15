extends RefCounted
## NET-07's scenarios: miners wandering the test map, each with a lamp that follows them, and each
## client's decoded views and events kept by frame tick as the client itself decoded them.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const SPAWNS: Array[Vector2i] = [Vector2i(2, 1), Vector2i(5, 13), Vector2i(9, 5), Vector2i(3, 9), Vector2i(12, 2)]


## `n` wandering miners with lamps; `link` [rtt_ms, loss_pct] for the first one, if any.
static func crew(s: Scenario, n: int, seed_value: int, link: Array = []) -> Array[MinerHandle]:
	var out: Array[MinerHandle] = []
	var lamps: Array[int] = []
	for i: int in n:
		var h: MinerHandle = s.add_miner("m%d" % i, SPAWNS[i % SPAWNS.size()])
		h.brain = load("res://tools/bots/brain.gd").call(&"create", "wander", seed_value + i)
		var at: Vector2 = s.run.registry.get_entity(h.entity_id).position
		lamps.append(s.run.light.grid.add_point("gauze_lamp", 1, h.entity_id, 0, 5.5, 1.0, at, 0))
		out.append(h)
	if link.size() == 2:
		var rtt: int = link[0]
		var loss: float = link[1]
		out[0].link(rtt, loss)
	s.on_tick = func(sc: Scenario) -> void:
		for i: int in out.size():
			var e: SimEntity = sc.run.registry.get_entity(out[i].entity_id)
			if e != null:
				sc.run.light.grid.update_point(lamps[i], e.position, 5.5, 1.0)
	return out


## frame tick -> [ReceivedView, events], filled as the client decodes each frame.
static func decoded_by_tick(s: Scenario, h: MinerHandle) -> Dictionary:
	var seen: Dictionary = {}
	s.client(h).on_decoded = func(d: FrameDecoder.Decoded) -> void: seen[d.tick] = [d.view, d.events]
	return seen


static func window_of(s: Scenario, kind: RecordWindow.Kind, entity: int) -> RecordWindow:
	for w: RecordWindow in s.run.record.windows:
		if w.kind == kind and w.entity == entity:
			return w
	return null
