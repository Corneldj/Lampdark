class_name MothSleep
extends RefCounted
## CRT-03: the sleeping Moth's senses and clock. Asleep it perceives four things only: light on
## its own body (VIS-02's value at its tile, once a tick), a flare or muzzle flash in its line of
## sight within moth.flash_wake_tiles, a hatch and the engine. The stir clock counts ticks at
## moth.stir_level or more in the last moth.stir_window_s; moth.stir_clock_s of them in all start
## a stir, as does moth.wake_level at any moment. Hunger, or a marked miner near the roost during
## a build, raises it straight to Prowl with no stir and no rustle.

enum Cause { NONE = 0, CLOCK = 1, BRIGHT = 2, FLARE = 3, FLASH = 4, HATCH = 5, ENGINE = 6 }

const FLASH_KINDS: Dictionary = {"flare": Cause.FLARE, "muzzle_flash": Cause.FLASH}

var window: int = 200
var clock_ticks: int = 20
var stir_ticks: int = 30
var settle_ticks: int = 60
var preen_ticks: int = 100
var stir_level: int = 300
var wake_level: int = 600
## The ring of "lit to stir_level" flags, its write position and how many are set.
var ring: PackedByteArray = PackedByteArray()
var at: int = 0
var lit: int = 0
var cause: Cause = Cause.NONE
var cause_position: Vector2 = Vector2.ZERO
var state_until: int = -1
var hunger_at: int = -1
## [kind, position] of flares and flashes added since the last tick.
var pending: Array[Array] = []
var _next_marked_check: int = 0


func _init() -> void:
	var hz: float = Tuning.f(&"net.tick_hz")
	window = roundi(Tuning.f(&"moth.stir_window_s") * hz)
	clock_ticks = roundi(Tuning.f(&"moth.stir_clock_s") * hz)
	stir_ticks = roundi(Tuning.f(&"moth.stir_tell_s") * hz)
	settle_ticks = roundi(Tuning.f(&"moth.settle_s") * hz)
	preen_ticks = roundi(Tuning.f(&"moth.preen_s") * hz)
	stir_level = roundi(Tuning.f(&"moth.stir_level") * 1000.0)
	wake_level = roundi(Tuning.f(&"moth.wake_level") * 1000.0)
	ring.resize(window)


## VIS-02's source_added: a flare or a muzzle flash to judge next tick.
func on_source_added(_id: int, kind: String, position: Vector2) -> void:
	if FLASH_KINDS.has(kind):
		pending.append([kind, position])


## One sample of light on its body; returns the light in thousandths.
func sample(run: RunState, tile: Vector2i) -> int:
	var light: int = run.light.grid.value(tile) if run.light != null else 0
	var flag: int = 1 if light >= stir_level else 0
	lit += flag - ring[at]
	ring[at] = flag
	at = (at + 1) % window
	return light


func clear_clock() -> void:
	ring.fill(0)
	lit = 0


## The strongest trigger this tick, or NONE: a flash or flare in sight, 0.60, then the clock.
func trigger(run: RunState, from: Vector2, light: int) -> Cause:
	var found: Cause = Cause.NONE
	for p: Array in pending:
		var kind: String = p[0]
		var where: Vector2 = p[1]
		if from.distance_to(where) <= Tuning.f(&"moth.flash_wake_tiles") + 1e-9 and line_of_sight(run, from, where):
			found = FLASH_KINDS[kind]
			cause_position = where
	pending.clear()
	if found != Cause.NONE:
		return found
	if light >= wake_level:
		return Cause.BRIGHT
	if lit >= clock_ticks:
		return Cause.CLOCK
	return Cause.NONE


## Whether the stir's end wakes it: always for a flash, a flare, 0.60, a hatch or the engine;
## for the clock, only with stir_level or more still on it.
func wakes_at_end(light: int) -> bool:
	return cause != Cause.CLOCK or light >= stir_level


## Hunger: drawn on falling asleep, uniform over moth.hunger_min_s to _max_s (Restless Moth:
## moth.restless_sleep_min_s to _max_s), from the creature's stream.
func draw_hunger(run: RunState, rng: LbRng, restless: bool) -> void:
	var hz: float = Tuning.f(&"net.tick_hz")
	var lo: int = roundi(Tuning.f(&"moth.restless_sleep_min_s" if restless else &"moth.hunger_min_s") * hz)
	var hi: int = roundi(Tuning.f(&"moth.restless_sleep_max_s" if restless else &"moth.hunger_max_s") * hz)
	hunger_at = run.tick + rng.range(lo, hi)


## Once a second during a build: a miner at Pull pull.threshold_marked or more within
## moth.marked_wake_tiles of the roost (straight line). Never in a relax.
func marked_near(run: RunState, gate: HuntGate, roost: Vector2) -> bool:
	if run.tick < _next_marked_check:
		return false
	_next_marked_check = run.tick + roundi(Tuning.f(&"net.tick_hz"))
	if not Variants.flag(gate.build_active.call()) or Variants.flag(gate.relax_active.call()):
		return false
	var reach: float = Tuning.f(&"moth.marked_wake_tiles")
	for id: int in run.registry.ids():
		var e: SimEntity = run.registry.get_entity(id)
		if e.kind == WorldIds.EntityKind.MINER and e.position.distance_to(roost) <= reach + 1e-9 \
				and Variants.number(gate.pull_of.call(id)) >= Tuning.f(&"pull.threshold_marked"):
			return true
	return false


## Line of sight between two points: no opaque tile strictly between their tiles (DDA walk).
static func line_of_sight(run: RunState, a: Vector2, b: Vector2) -> bool:
	if run.mine == null:
		return true
	var from: Vector2i = Vector2i(floori(a.x), floori(a.y))
	var to: Vector2i = Vector2i(floori(b.x), floori(b.y))
	var steps: int = ceili(a.distance_to(b) * 4.0)
	for i: int in range(1, steps):
		var p: Vector2 = a.lerp(b, float(i) / steps)
		var t: Vector2i = Vector2i(floori(p.x), floori(p.y))
		if t == from or t == to:
			continue
		if run.mine.native.is_opaque(t):
			return false
	return true
