class_name Shot
extends RefCounted
## MNR-16 (Gameplay §4.7, §7.6, GDD §15.2): one shot's effects and its trace. A 40 np `shot` event
## at the shooter (SND-02; the Road Graph carries it, and HAZ-03's creak through the same event); a
## `muzzle_flash` light (revolver.flash_peak at revolver.flash_radius) for revolver.flash_duration;
## SND-04's deafen for the shooter and every miner within revolver.deafen_radius, straight-line
## (Proposed); `shot_fired(tile)` for HAZ-04. Then NET-06's rewind traces bodies along the aim out
## to revolver.range, rewound to what the shooter was shown (no defender rule: a shot has no
## wind-up): rock, a closed air door and a shut gate stop it, and the first body on the line takes
## it, seen or not. Server-only: the shooter's client learns nothing of what it hit.

const FLASH_KIND: String = "muzzle_flash"


## Fires from `shooter` (its slot) along `aim` (0-65535), stamped `stamp` (the shown tick):
## {tick, shooter, origin, aim, hit (entity or 0), outcome}.
static func fire(run: RunState, sys: Revolver, shooter: int, slot: int, aim: int, stamp: int) -> Dictionary:
	var me: SimEntity = run.registry.get_entity(shooter)
	var origin: Vector2 = me.position
	var tile: Vector2i = me.tile()
	if run.noise != null:
		run.noise.emit(NoiseTypes.Type.SHOT, tile, {"source": shooter})
	_flash(run, sys, shooter, origin)
	_deafen(run, slot, origin)
	sys.shot_fired.emit(tile)
	var u: PackedFloat64Array = LbDetMath.unit(float(aim & 0xFFFF) / 65536.0)
	var dir: Vector2 = Vector2(u[0], u[1])
	var trace: Dictionary = {}
	if run.rewind != null:
		trace = run.rewind.trace_bodies(origin, dir, Tuning.f(&"revolver.range"), float(stamp), shooter)
	var hit: int = int(Variants.number(trace.get("entity", 0)))
	var row: Dictionary = {"tick": run.tick, "shooter": shooter, "origin": origin, "aim": aim, "hit": hit, "outcome": &"none"}
	if hit != 0:
		row["outcome"] = sys.on_body_hit(run, shooter, hit)
	elif trace.has("wall"):
		row["outcome"] = &"wall"
	return row


static func _flash(run: RunState, sys: Revolver, shooter: int, at: Vector2) -> void:
	if run.light == null:
		return
	var source: int = run.light.grid.add_point(FLASH_KIND, LbLightGrid.COLOUR_WHITE, shooter, LbLightGrid.FLAG_NO_FLAME_STATES,
		Tuning.f(&"revolver.flash_radius"), Tuning.f(&"revolver.flash_peak"), at, 0)
	var ticks: int = maxi(1, roundi(Tuning.f(&"revolver.flash_duration") * Tuning.f(&"net.tick_hz")))
	sys.flashes.append({"source": source, "until": run.tick + ticks})


## SND-04: the shooter, and every miner within revolver.deafen_radius of the shot (straight-line).
static func _deafen(run: RunState, slot: int, at: Vector2) -> void:
	if run.deafen == null or run.movement == null:
		return
	for s: int in run.movement.miner_slots():
		var m: MovementSystem.Miner = run.movement.miner(s)
		if s == slot or Vector2(m.state.x, m.state.y).distance_to(at) <= Tuning.f(&"revolver.deafen_radius") + 1e-9:
			run.deafen.deafen(run, s)
