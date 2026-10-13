class_name TapperPin
extends RefCounted
## CRT-09's pin, through RSC-03's holds: tapper.pin_s of crushing, then the victim falls at the
## wall's foot. A teammate holding interact tapper.silent_pull_s within touch range frees the
## victim (Hurt and rock-touched); speech above a whisper within tapper.pull_spoil_radius_tiles
## during the pull brings a ReStrike tapper.restrike_delay_s after the first spoiling word, and
## the crush resumes where it stopped. A lure 6-10 tiles off drops the victim for the sound; a
## flare on the arm frees them. One pin at a time.

var grab_id: int = -1
var victim: int = 0
## puller entity -> ticks held
var pull: Dictionary = {}
var spoil_tick: int = -1
var restrike_at: int = -1


func reset() -> void:
	grab_id = -1
	victim = 0
	pull.clear()
	spoil_tick = -1
	restrike_at = -1


func start(run: RunState, t: Tapper, miner: int) -> bool:
	var limit: int = roundi(Tuning.f(&"tapper.pin_s") * Tuning.f(&"net.tick_hz"))
	var id: int = run.holds.grab(run, miner, GrabHold.Kind.TAPPER_PIN, t.entity_id, limit)
	if id < 0:
		return false
	reset()
	grab_id = id
	victim = miner
	t.grabbing = miner
	return true


func hold() -> GrabHold:
	return null if grab_id < 0 else _holds.grabs.get(grab_id, null)


var _holds: Holds = null


## Each tick in Pin or in the ReStrike's wait.
func tick(run: RunState, t: Tapper, hunt: TapperHunt, heard: Array[TapperHearing.HeardEvent]) -> void:
	_holds = run.holds
	var g: GrabHold = hold()
	if g == null:
		return
	# Distances are by path from where the victim is held (the face itself is rock).
	var at: Vector2 = run.registry.get_entity(victim).position
	var pin_tile: Vector2i = Vector2i(floori(at.x), floori(at.y))
	if g.state == GrabHold.State.ACTIVE:
		if _flare_on_arm(run, hunt.arm):
			t.system.log.add(run.tick, &"tapper_pin_broken", {"by": "flare"})
			run.holds.end_grab(run, grab_id, GrabHold.Outcome.BROKEN)
			return
		for h: TapperHearing.HeardEvent in heard:
			var lure: Dictionary = TapperStrike.lure(run, t, h, pin_tile)
			if not lure.is_empty():
				t.system.log.add(run.tick, &"tapper_pin_broken", {"by": "lure", "distance": lure["distance"]})
				run.holds.end_grab(run, grab_id, GrabHold.Outcome.BROKEN)
				hunt.lured(run, t, h, int(Variants.number(lure["miner"])))
				return
		if not pull.is_empty():
			for h: TapperHearing.HeardEvent in heard:
				if spoil_tick < 0 and TapperStrike.spoils(run, t, h, pin_tile):
					spoil_tick = run.tick
					restrike_at = run.tick + roundi(Tuning.f(&"tapper.restrike_delay_s") * Tuning.f(&"net.tick_hz"))
					t.system.log.add(run.tick, &"tapper_pull_spoiled", {"restrike_at": restrike_at})
		_advance_pull(run, t, hunt)
	if restrike_at >= 0 and run.tick >= restrike_at:
		restrike_at = -1
		g = hold()
		if g != null and g.state == GrabHold.State.SUSPENDED:
			hunt.restrike(run, t, victim)


## Teammates pulling (RSC-03's SilentPull: Upright, holding interact in touch range of the victim
## as their client showed it). The first to hold tapper.silent_pull_s frees the victim.
func _advance_pull(run: RunState, t: Tapper, hunt: TapperHunt) -> void:
	var need: int = roundi(Tuning.f(&"tapper.silent_pull_s") * Tuning.f(&"net.tick_hz"))
	var still: Dictionary = {}
	for e: int in SilentPull.pullers(run, victim):
		var held: int = int(Variants.number(pull.get(e, 0))) + 1
		still[e] = held
		if held >= need:
			pull.clear()
			if spoil_tick >= 0:
				t.system.log.add(run.tick, &"tapper_pin_pulled", {"spoiled": true})
				run.holds.suspend(run, grab_id)
				hunt.withdraw_arm(run)
				t.grabbing = 0
			else:
				t.system.log.add(run.tick, &"tapper_pin_pulled", {"spoiled": false})
				run.holds.end_grab(run, grab_id, GrabHold.Outcome.BROKEN)
			return
	pull = still


## A flare lighting the arm's tile to 0.30 or more.
static func _flare_on_arm(run: RunState, arm: int) -> bool:
	if arm == 0 or run.light == null or not run.registry.has(arm):
		return false
	var p: Vector2 = run.registry.get_entity(arm).position
	var tile: Vector2i = Vector2i(floori(p.x), floori(p.y))
	var src: Dictionary = run.light.grid.brightest_source(tile)
	return str(src.get("kind", "")) == "flare" and run.light.grid.value(tile) >= roundi(Tuning.f(&"moth.stir_level") * 1000.0)
