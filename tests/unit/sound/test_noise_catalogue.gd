extends GutTest
## SND-02's catalogue: every source in Gameplay §6.1's table at its np (and the Proposed sounds the
## jobs need beside it), with an owner, rate, duration, struck flag and source section; the wire ids
## match; silent sources are listed.

## Gameplay §6.1 / A.2: catalogue id -> np.
const TABLE: Dictionary = {
	"reload_click": 8, "lamp_hang_clink": 8,
	"step_walk": 9, "panting": 9, "flint_click": 9, "spanner": 9, "step_stretcher": 9, "step_drum_gear": 9, "drag_scrape": 9,
	"rock_tap": 10, "canary": 10,
	"gasp": 12, "cough": 12, "carry_knock": 12, "step_heavy": 12, "struggle": 12, "moth_laying": 12, "buzzer": 12, "trapped_cry": 12,
	"rail_bang": 14, "tub_rumble": 14, "stone_landing": 14, "gate": 14, "hammer": 14, "phone_crank": 14, "mantrap_snap": 14,
	"flare_strike": 16,
	"step_run": 18,
	"phone_bell": 20, "hold_bell": 20, "engine_crank": 20, "main_switch": 20, "cage_freed": 20, "staple_pit_crash": 20, "brood_burst": 20,
	"engine_running": 24, "bess_whinny": 24,
	"backfire": 30, "roof_fall": 30,
	"shot": 40, "firedamp_blast": 40,
}
## Not in §6.1's table, Proposed: catalogue id -> np (LFT-05's trip lever, the main switch's cue).
const PROPOSED: Dictionary = {"trip_lever": 8}
const VOCAL: Array[String] = ["panting", "gasp", "cough", "trapped_cry", "voice", "callout", "fall_scream"]
## Gameplay §7.3: the Deaf hears these, and not these.
const STRUCK: Array[String] = ["step_walk", "step_run", "flint_click", "lamp_hang_clink", "rock_tap", "rail_bang",
	"stone_landing", "carry_knock", "phone_bell", "hold_bell", "gate", "hammer", "engine_crank", "engine_running",
	"roof_fall", "shot"]
const NOT_STRUCK: Array[String] = ["voice", "callout", "panting", "gasp", "cough"]

var catalogue: NoiseCatalogue


func before_all() -> void:
	assert_true(Tuning.load_server())
	catalogue = NoiseCatalogue.load_default()


func test_every_source_at_its_np() -> void:
	var all: Dictionary = TABLE.duplicate()
	all.merge(PROPOSED)
	for id: String in all.keys():
		var e: NoiseCatalogue.Entry = catalogue.entry(NoiseTypes.from_id(id))
		assert_not_null(e, "%s is catalogued" % id)
		if e != null:
			var np: int = all[id]
			assert_eq(e.np, float(np), "%s at %d np" % [id, np])
	assert_eq(catalogue.entries.size(), TABLE.size() + PROPOSED.size() + 3, "the table and the Proposed sounds, plus voice, callouts and the fall's scream")


func test_every_entry_is_complete() -> void:
	for raw: Variant in catalogue.entries.values():
		var e: NoiseCatalogue.Entry = raw
		assert_false(e.owner.is_empty(), "%s names its owner" % e.id)
		assert_true(e.source.begins_with("Gameplay §"), "%s names its source section" % e.id)
		assert_gt(e.duration_s, 0.0, "%s has a duration" % e.id)
		assert_false(e.caption.is_empty(), "%s has a caption key" % e.id)
		assert_false(e.sample.is_empty(), "%s names a sample" % e.id)
		assert_eq(e.vocal, VOCAL.has(e.id), "%s vocal flag" % e.id)
	assert_eq(catalogue.unclassified, PackedStringArray(), "every kind is classified struck or not struck")


func test_rates_and_durations() -> void:
	var ticks: Dictionary = {"step_walk": 10, "step_run": 10, "step_heavy": 10, "panting": 40, "drag_scrape": 20,
		"struggle": 40, "engine_running": 40, "voice": 5}
	for id: String in ticks.keys():
		var expected: int = ticks[id]
		assert_eq(catalogue.entry(NoiseTypes.from_id(id)).rate_ticks, expected, "%s rate" % id)
	assert_eq(catalogue.entry(NoiseTypes.Type.SHOT).rate_ticks, 0, "a shot is a one-shot")
	assert_eq(catalogue.entry(NoiseTypes.Type.STEP_WALK).duration_s, 0.5, "a periodic event lasts its interval")
	assert_eq(catalogue.entry(NoiseTypes.Type.ENGINE_RUNNING).duration_s, 2.0)
	assert_eq(catalogue.entry(NoiseTypes.Type.PHONE_CRANK).duration_s, 2.0)
	assert_eq(catalogue.entry(NoiseTypes.Type.ENGINE_CRANK).duration_s, 4.0)
	assert_eq(catalogue.entry(NoiseTypes.Type.SHOT).duration_s, 0.5)


func test_struck_follows_the_design() -> void:
	for id: String in STRUCK:
		assert_true(catalogue.entry(NoiseTypes.from_id(id)).struck, "%s is struck" % id)
	for id: String in NOT_STRUCK:
		assert_false(catalogue.entry(NoiseTypes.from_id(id)).struck, "%s is not struck" % id)
	for key: StringName in [&"tapper.deaf_struck_kinds", &"tapper.deaf_not_struck_kinds"]:
		for id: String in Tuning.list_s(key):
			assert_ne(NoiseTypes.from_id(id), NoiseTypes.Type.NONE, "%s in %s is a catalogue id" % [id, key])


func test_wire_ids_match_the_catalogue() -> void:
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(NoiseCatalogue.PATH)))
	var ids: Array = Variants.array(doc["types"]).map(func(t: Variant) -> String: return str(Variants.dict(t)["id"]))
	assert_eq(NoiseTypes.Type.size() - 1, ids.size())
	for i: int in ids.size():
		assert_eq(int(NoiseTypes.from_id(str(ids[i]))), i + 1, "%s keeps wire id %d" % [ids[i], i + 1])
		assert_eq(NoiseTypes.id_of(NoiseTypes.from_id(str(ids[i]))), str(ids[i]))


func test_silent_and_non_events_are_listed() -> void:
	assert_eq(catalogue.silent, PackedStringArray(["crouch_step", "feel", "chalk", "shutter", "wick"]))
	for id: String in ["hatch_tell", "firedamp_hiss", "knocks", "illusions", "cold_open_screams", "creature_tells"]:
		assert_true(catalogue.not_events.has(id), "%s is deliberately not a Road Graph event" % id)
		assert_eq(NoiseTypes.from_id(id), NoiseTypes.Type.NONE, "%s has no emission type" % id)
