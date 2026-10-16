class_name RelaxRules
extends SimSystem
## DIR-02: inside the relax (Gameplay §10.3). The relax is quiet, never safety.
## - CRT-01's relax provider: in_relax() shuts the hunt gate on hunts creatures *choose* (unless the
##   apex is on: LFT-09's turn toward base camp ignores the relax; the cap still binds). The gate
##   tells each creature when a relax starts and ends; each ends its chosen hunt (a wind-up, grab,
##   frenzy or apex hunt under way goes on) and drifts home by its own movement.
## - The illusion gate: illusions_allowed() is false in every relax, the apex's included; at its
##   start illusions_cut tells CRT-10 to end one playing as a real sound would, and CRT-11's line
##   drops no flap.
## - The seam ticks as it cools: SND-03's seam_cooling bed layer for every miner below (not inside
##   base camp), from the relax's start to its end; the unconscious hear it muffled (RSC-04). It is
##   no Road Graph event, and no creature hears it. A carried canary reads in_relax() to sing (MNR-11).
## - The Fan: rolled at the relax's start (FanRoll), surging its full length however short the relax.
## Senses, memories and the Pull keep counting: nothing here touches them. Stage 16, after the
## Draught (16/25): the relax begins in the Draught's tick, and the seam follows the same tick.
## Server-only: a client hears only the designed consequences, never a phase.

signal illusions_cut()

## The ticking fades in and out over this many seconds.
const SEAM_FADE_S: float = 2.0

var draught: Draught = null
var fan: FanRoll = FanRoll.new()
## Slot -> the seam_cooling layer is playing for that client.
var _seam_on: Dictionary = {}
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.RECORD


func order() -> int:
	return 30 # after the Draught (16/25)


func system_name() -> String:
	return "RelaxRules"


func bind(run: RunState, of_draught: Draught) -> void:
	_run = run
	draught = of_draught
	fan.rng = run.stream(HashDomain.DIRECTOR_FAN_ROLL, PackedInt64Array())
	draught.cycle.relax_begun.connect(_on_relax_begun)
	if run.creatures != null:
		run.creatures.gate.relax_active = in_relax


## CRT-01's relax provider (and MNR-11's canary): true in RELAX only.
func in_relax() -> bool:
	return draught != null and draught.cycle.in_relax()


## CRT-10, CRT-11: no illusion plays in a relax, the apex's included.
func illusions_allowed() -> bool:
	return not in_relax()


func _on_relax_begun(_length: int, ring: int) -> void:
	illusions_cut.emit()
	if _run != null:
		fan.on_relax_begun(_run, ring)


## The seam's ticking follows the relax and each miner in and out of base camp.
func tick(run: RunState) -> void:
	_run = run
	if run.audio == null or run.movement == null:
		return
	var relax: bool = in_relax()
	var slots: Array = run.movement.miner_slots()
	for raw: Variant in slots:
		var slot: int = int(Variants.number(raw))
		var m: MovementSystem.Miner = run.movement.miner(slot)
		var below: bool = m != null and (run.base_camp == null or not run.base_camp.is_inside(m.entity_id))
		var want: bool = relax and below
		if want != Variants.flag(_seam_on.get(slot, false)):
			run.audio.ambient(slot, AmbientMessages.SEAM_COOLING, want, SEAM_FADE_S)
			_seam_on[slot] = want
	for raw: Variant in _seam_on.keys():
		if not slots.has(raw):
			_seam_on.erase(raw) # the client left; a rejoin starts from silence


## NET-09: the Fan's stand-in surge (SND-16 keeps the real one's time).
func save_state() -> Dictionary:
	return {"fan_until": fan.surge_until, "fan_rolls": fan.rolls, "fan_surges": fan.surges}


func load_state(_r: RunState, state: Dictionary) -> void:
	fan.surge_until = int(Variants.number(state.get("fan_until", -1)))
	fan.rolls = int(Variants.number(state.get("fan_rolls", 0)))
	fan.surges = int(Variants.number(state.get("fan_surges", 0)))


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(fan.surge_until)
	writer.put_i64(fan.rolls)
	writer.put_i64(fan.surges)
