class_name CreatureTables
extends RefCounted
## CRT-01's per-ring and crew-size tables (Gameplay §7.1), read from tuning. A creature uses the
## ring of the tile it stands on; crew-size lookups clamp the crew count to 1-5, so 0 reads as 1.
## Speeds, reaches, tells and wind-ups never change with depth: only these do.

const TALK_NP: float = 12.0


static func ring(r: int) -> int:
	return clampi(r, 0, 4)


static func crew(count: int) -> int:
	return clampi(count, 1, 5)


static func moth_sight_tiles(r: int) -> float:
	return Tuning.by_ring(&"moth.sight_tiles_by_ring", ring(r))


## A flare and a lamp signal are seen this far at every depth.
static func moth_flare_sight_tiles() -> float:
	return Tuning.f(&"moth.flare_sight_tiles")


static func moth_signal_sight_tiles() -> float:
	return Tuning.f(&"moth.signal_sight_tiles")


static func moth_frenzy_s(r: int) -> float:
	return Tuning.by_ring(&"moth.frenzy_s_by_ring", ring(r))


static func tapper_hearing_mult(r: int) -> float:
	return Tuning.by_ring(&"tapper.hearing_mult_by_ring", ring(r))


## The Tapper hears a sound of `np` within (np - 4) x the ring's multiplier, in tiles.
static func tapper_hearing_tiles(r: int, np: float) -> float:
	return maxf(np - 4.0, 0.0) * tapper_hearing_mult(r)


## Talk (12 np): 6.4, 8, 9.6, 11.2, 12.8 tiles by ring.
static func tapper_talk_hearing_tiles(r: int) -> float:
	return tapper_hearing_tiles(r, TALK_NP)


static func stythe_senses_tiles(r: int, in_territory: bool = false) -> float:
	if in_territory:
		return Tuning.f(&"stythe.territory_senses_tiles")
	return Tuning.by_ring(&"stythe.senses_tiles_by_ring", ring(r))


## The unheard mark: one number shared with the voice timer (SND), 60 s, 45 s from ring 2.
static func stythe_unheard_mark_s(r: int) -> float:
	if ring(r) >= Tuning.i(&"voice.unheard_mark_deep_ring"):
		return Tuning.f(&"voice.unheard_mark_deep_s")
	return Tuning.f(&"voice.unheard_mark_s")


static func search_time_s(r: int) -> float:
	return Tuning.by_ring(&"creatures.search_time_s_by_ring", ring(r))


static func moth_memory_lights(count: int) -> int:
	return roundi(Tuning.by_crew(&"moth.memory_lights_by_crew", crew(count)))


static func tapper_heat_window_s(count: int) -> float:
	return Tuning.by_crew(&"tapper.heat_window_s_by_crew", crew(count))


static func tapper_listen_pause_s(count: int) -> float:
	return Tuning.by_crew(&"tapper.listen_pause_s_by_crew", crew(count))


static func stythe_memory_places(count: int) -> int:
	return roundi(Tuning.by_crew(&"stythe.memory_places_by_crew", crew(count)))


static func stythe_snuff_interval_s(count: int, in_territory: bool = false) -> float:
	if in_territory:
		return Tuning.f(&"stythe.snuff_interval_territory_s")
	return Tuning.by_crew(&"stythe.snuff_interval_s_by_crew", crew(count))
