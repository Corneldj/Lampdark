class_name StytheDrag
extends RefCounted
## CRT-14 (Gameplay §7.4): the drag. The Stythe hauls its one victim to the lair at
## stythe.drag_speed through the dark, round every light (CRT-02's dark path; with no dark way home
## it holds the victim at the dark tile nearest the lair, still breakable, the 20 s running on). The
## victim rides on it; every tile they cross goes out as `drag_tile_crossed` (CRT-15's trail), and a
## scrape (drag_scrape, stythe.scrape_np) sounds at them every stythe.scrape_interval_s. RSC-03's
## grab keeps them conscious for stythe.drag_conscious_s, their voice muffled to whisper range
## (SND-07's DRAGGED route); then they fall unconscious with a muffled scream and the knocks, and the
## drag goes on. Light of its threshold on it from a teammate (never a Hired Hand's, never the
## victim's own; unheld lamps count, Proposed), or a flare lighting it, breaks the drag: it drops the
## victim and flees. A victim freed before the 20 s is Upright and Hurt (RSC-03); after, they lie
## unconscious where dropped. Server-only.

var victim: int = 0
var grab_id: int = -1
## A drag that follows a Collect fills no cap place (Proposed): it holds no hunt.
var collected: bool = false
var last_tile: Vector2i = Vector2i(2147483647, 0)
var next_scrape: int = -1
## Every drag tile: {tick, tile, dir} (CRT-15 reads `drag_tile_crossed` too).
var tiles: Array[Dictionary] = []


func start(run: RunState, st: StytheCreature, who: int, id: int, from_collect: bool, conscious: bool) -> void:
	victim = who
	grab_id = id
	collected = from_collect
	last_tile = run.registry.get_entity(who).tile()
	next_scrape = run.tick
	st.move.stop()
	var slot: int = StytheEligibility.slot_of(run, who)
	if conscious and slot >= 0 and run.voice != null:
		run.voice.set_route(slot, VoiceRoutes.Route.DRAGGED)
	st.drag_tile_crossed.emit(last_tile, -1)
	tiles.append({"tick": run.tick, "tile": last_tile, "dir": -1})


func tick(run: RunState, st: StytheCreature) -> void:
	if victim == 0 or not run.registry.has(victim):
		drop(run, st, GrabHold.Outcome.ABANDONED)
		st.hunt.begin_check(run, st, "the victim gone")
		return
	var light: Vector2i = breaking_light(run, st)
	if light.x != 2147483647:
		st.hunt.begin_flee(run, st, light, "light on it")
		return
	if st.at_home(run, st.tile(run)):
		# Home before the victim's 20 s are out (CRT-15, Proposed): it holds them in the lair,
		# still breakable, until they fall; then it lays the body.
		if _conscious(run):
			st.move.stop()
			_carry(run, st)
			_scrape(run, st)
			return
		st.reached_lair(run)
		return
	st.move.head_for(run, st, st.lair)
	st.move.tick(run, st, Tuning.f(&"stythe.drag_speed"))
	_carry(run, st)
	_scrape(run, st)


func _scrape(run: RunState, st: StytheCreature) -> void:
	if run.tick >= next_scrape:
		next_scrape = run.tick + maxi(1, roundi(Tuning.f(&"stythe.scrape_interval_s") * Tuning.f(&"net.tick_hz")))
		if run.noise != null:
			run.noise.emit(NoiseTypes.Type.DRAG_SCRAPE, run.registry.get_entity(victim).tile(), {"source": st.entity_id})


## The victim is still awake in RSC-03's grab (its 20 s not yet out).
func _conscious(run: RunState) -> bool:
	if run.holds == null or grab_id < 0 or not run.holds.grabs.has(grab_id):
		return false
	var g: GrabHold = run.holds.grabs[grab_id]
	return g.state == GrabHold.State.ACTIVE


## The victim rides on the Stythe; each new tile is a trail tile with the drag's heading.
func _carry(run: RunState, st: StytheCreature) -> void:
	var at: Vector2 = st.position(run)
	if run.movement != null:
		run.movement.place(run, victim, at)
	else:
		run.registry.move(victim, at)
	var t: Vector2i = run.registry.get_entity(victim).tile()
	if t != last_tile:
		var dir: int = VisionSystem.trail_direction(Vector2(last_tile), Vector2(t))
		last_tile = t
		tiles.append({"tick": run.tick, "tile": t, "dir": dir})
		st.drag_tile_crossed.emit(t, dir)


## The tile of light that breaks the drag, or (huge, 0) if none: a teammate's light of its threshold
## on the Stythe's tile (never a Hired Hand's or the victim's), or a flare lighting it to 0.30.
func breaking_light(run: RunState, st: StytheCreature) -> Vector2i:
	var t: Vector2i = st.tile(run)
	if StytheHunt.others_light(run, t, [victim]) >= st.light_threshold() - 1e-9:
		return t
	if run.flares != null and run.light != null:
		for raw: Variant in run.flares.sources.keys():
			var source: int = int(Variants.number(Variants.dict(run.flares.sources[raw])["source"]))
			var info: Dictionary = run.light.grid.source_info(source)
			var p: Vector2 = info.get("position", Vector2(INF, INF))
			if p.distance_to(st.position(run)) <= float(Variants.number(info.get("radius", 0.0))) and run.light.light_at(t) >= Tuning.f(&"stythe.wall_level") - 1e-9:
				return t
	return Vector2i(2147483647, 0)


## Lets go of the victim: freed before the 20 s they stand Upright and Hurt (RSC-03), after they
## lie unconscious where dropped; their voice back from the drag's whisper while still conscious.
func drop(run: RunState, st: StytheCreature, outcome: GrabHold.Outcome) -> void:
	if victim == 0:
		return
	var who: int = victim
	victim = 0
	if run.holds != null and grab_id >= 0:
		run.holds.end_grab(run, grab_id, outcome)
	grab_id = -1
	st.grabbing = 0
	var slot: int = StytheEligibility.slot_of(run, who)
	if slot >= 0 and run.voice != null and int(Variants.number(run.voice.route_of.get(slot, VoiceRoutes.Route.NORMAL))) == VoiceRoutes.Route.DRAGGED:
		run.voice.set_route(slot, VoiceRoutes.Route.NORMAL)
	if not collected:
		st.system.gate.stand_down(run, st, "the drag ended")
