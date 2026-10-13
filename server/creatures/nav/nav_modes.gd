class_name NavModes
extends RefCounted
## CRT-02's movement modes (LbCreatureNav) and their parameters from tuning. Speeds, targets and
## when to move belong to each creature ticket.

enum Mode { WALKER = 0, CRAWLER = 1, DARK = 2, ROCK = 3 }


## The defaults every query starts from.
static func defaults() -> Dictionary:
	return {
		"dark_threshold": Tuning.f(&"stythe.wall_level"),
		"crawl_open_cost": roundi(Tuning.f(&"creatures.nav_crawl_open_tile_cost")),
		"rock_crosses_floor": Tuning.b(&"creatures.nav_tapper_crosses_floor"),
		"brick_clearance": Tuning.i(&"creatures.nav_tapper_brick_clearance_tiles"),
	}


## The Stythe's threshold: 0.30, or 0.50 for the Thin (CRT-17).
static func dark(thin: bool = false) -> Dictionary:
	return {"dark_threshold": Tuning.f(&"stythe.thin_wall_level" if thin else &"stythe.wall_level")}
