extends RefCounted
## Helpers for VIS-07's tests: a black room, a held feel, and what came back.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")


## Holds interact for `ticks` from now (crouched still unless `gait` says otherwise) and steps on.
static func feel(s: Scenario, h: MinerHandle, ticks: int = 40, walk_deg: float = -1.0) -> void:
	var at: int = s.run.tick
	if walk_deg >= 0.0:
		h.at(at).move(walk_deg, InputRecord.Gait.WALK, ticks)
	h.at(at).hold(InputRecord.HOLD_INTERACT, ticks)
	s.step(ticks + 10)


## The feel answers given to a miner so far (server side).
static func answers(s: Scenario, h: MinerHandle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a: Dictionary in s.run.feel.answers:
		if int(Variants.number(a["miner"])) == h.entity_id and not a.has("bump"):
			out.append(a)
	return out
