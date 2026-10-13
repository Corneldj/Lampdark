class_name Relighter
extends RefCounted
## LFT-01: after Power, relights an Out gauze lamp in basecamp.relighter_s with no notch spent
## (MNR-07's relight, method "relighter"); before Power it refuses. There is no gas in base camp.

var tile: Vector2i = Vector2i.ZERO
## lamp being relit -> [the tick it is done, by whom]
var working: Dictionary = {}


func install(seed_value: int, side: int) -> void:
	tile = Basecamp.fixture(seed_value, "relighter", side)[0]["position"]


## Starts relighting `lamp` (an Out gauze lamp, MNR-06: unlit, with oil). Refused before Power.
func begin(run: RunState, powered: bool, lamp: GauzeLamp, by: int = 0) -> bool:
	if not powered or working.has(lamp) or not Relight.offered(lamp, Relight.RELIGHTER):
		return false
	working[lamp] = [run.tick + roundi(Tuning.f(&"basecamp.relighter_s") * Tuning.f(&"net.tick_hz")), by]
	return true


func tick(run: RunState) -> void:
	for raw: Variant in working.keys():
		var lamp: GauzeLamp = raw
		var job: Array = Variants.array(working[raw])
		if run.tick >= int(Variants.number(job[0])):
			working.erase(raw)
			Relight.relight(run, lamp, Relight.RELIGHTER, int(Variants.number(job[1])))
