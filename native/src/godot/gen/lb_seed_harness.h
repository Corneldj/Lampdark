#pragma once
// GDScript face of GEN-14's seed harness (harness/harness.h), for tools/seed_harness/run.gd. Dev
// and QA builds only: compiled with LB_DEBUG_TOOLS, never registered in a release library
// (check_debug_tools.sh holds it to that). Each run is an LbLayouts configured, planned, validated
// at run start and given its homes exactly as the server's MineLayouts and RunPlan do it, from the
// dictionaries those build out of tuning; the runs check on worker threads, every core's, and
// gather into one report whose bytes no thread order changes.

#ifdef LB_DEBUG_TOOLS

#include "godot/gen/lb_layouts.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace lb::godot {

class LbSeedHarness : public ::godot::RefCounted {
	GDCLASS(LbSeedHarness, ::godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// `base`: a deriver with the pack loaded (its parsed set is shared). `configure`: MineLayouts'
	// configure dictionary (each run's own arch_reach goes into its validate). `runs`: [{seed,
	// list_kind, jobs, cans, solo, draw, staging, hard_variant, data_version, gates: {side: socket},
	// arch_reach: {side: tiles}}]. `options`: {threads (0: every core), plan_tuning (RunPlan.tuning),
	// params (the harness's numbers), first_seed, last_seed, lists, progress_s}.
	// Returns {json (canonical, no timing), timing_json (with timing), markdown, failed, gates:
	// [{name, failed, detail}], runs, seconds}.
	static ::godot::Dictionary run(const ::godot::Ref<LbLayouts> &base, const ::godot::Dictionary &configure, const ::godot::Array &runs,
			const ::godot::Dictionary &options);
	// One run's repro dump (harness::repro) for `check` ("" every check) and `cell` (a Vector2i, or
	// null).
	static ::godot::String repro(const ::godot::Ref<LbLayouts> &base, const ::godot::Dictionary &configure, const ::godot::Dictionary &run,
			const ::godot::Dictionary &options, const ::godot::String &check, const ::godot::Variant &cell);
};

} // namespace lb::godot

#endif
