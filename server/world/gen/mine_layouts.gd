class_name MineLayouts
extends RefCounted
## GEN-05: the run's layout deriver (LbLayouts) set up from data: the template pack the run names
## (data/templates/set.json's current set unless a resumed run names its own, §12.6), the socket
## numbers from tuning, and base camp's forced sockets (GEN-02). GEN-11 derives cells from it on
## its workers. Server-only.

const TEMPLATES: String = "res://data/templates"
## Every cell's biome until GEN-06 assigns biomes.
const STAND_IN_BIOME: String = "seam"


## The deriver for a run, or null (with an error) if its template pack cannot be read.
static func for_run(run_seed: int, set_version: String = "") -> LbLayouts:
	var version: String = set_version
	if version.is_empty():
		var current: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(TEMPLATES.path_join("set.json"))))
		version = str(current.get("set_version", ""))
	var layouts: LbLayouts = LbLayouts.new()
	var pack_path: String = TEMPLATES.path_join("packs/%s.lbtp" % version)
	if version.is_empty() or not layouts.load_pack(FileAccess.get_file_as_bytes(pack_path)):
		push_error("MineLayouts: no template pack %s" % pack_path)
		return null
	layouts.configure(run_seed, {
		"open_probability": Tuning.f(&"mine.edge_open_probability"),
		"offsets": Tuning.list_i(&"mine.socket_offsets_tiles"),
		"widths": Tuning.list_i(&"mine.socket_widths_tiles"),
		"reroll_limit": roundi(Tuning.f(&"mine.validator_max_rerolls")),
		"biome": STAND_IN_BIOME,
	})
	var gates: Dictionary = Basecamp.gate_sockets(run_seed)
	for side: String in Basecamp.SIDES:
		layouts.force_socket(Vector2i.ZERO, side, Variants.dict(gates[side]))
	return layouts
