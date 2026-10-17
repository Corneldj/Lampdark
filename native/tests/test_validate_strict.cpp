// GEN-12: strict mode never yields a rule violation. A fuzz of 1,000,000 cells (LB_STRICT_FUZZ_CELLS
// sets another count) injects failing placements of every kind into GEN-10's own lists across
// rings 0-3, spine cells, gate cells and base camp; what strict mode keeps passes phase 2, is a
// subsequence of what it was given (it never adds one), and keeps what a man carried only with him.

#include "core/rng/rng.h"
#include "validate_fixture.h"

#include <doctest.h>

#include <cstdlib>

using namespace validate_fixture;
using lb::core::world::Coord;

namespace {

bool same_placement(const Placement &a, const Placement &b) {
	return a.kind == b.kind && a.thing == b.thing && a.source == b.source && a.anchor == b.anchor && a.tile == b.tile && a.w == b.w &&
			a.h == b.h && a.count == b.count && a.collapse == b.collapse && a.id == b.id;
}

Placement make_one(PlacedKind kind, Coord tile, int32_t w, int32_t h, const std::string &source, const std::string &thing = "") {
	Placement x;
	x.kind = kind;
	x.tile = tile;
	x.w = w;
	x.h = h;
	x.source = source;
	x.thing = thing;
	return x;
}

// One injected failure for `cell` (a unit: a man and what he carried go together).
std::vector<Placement> failure(lb::core::Rng &r, Coord cell) {
	auto tile = [&](int64_t lo = 0, int64_t hi = 19) { return lb::core::world::tile_of(cell, {*r.range(lo, hi), *r.range(lo, hi)}); };
	switch (*r.range(0, 7)) {
		case 0:
			return {make_one(*r.range(0, 1) == 0 ? PlacedKind::FIREDAMP : PlacedKind::BLACKDAMP, tile(0, 14), static_cast<int32_t>(*r.range(1, 6)),
					static_cast<int32_t>(*r.range(1, 6)), "gas")};
		case 1: {
			static const PlacedKind TRAPS[] = {PlacedKind::MAN_TRAP, PlacedKind::STAPLE_PIT, PlacedKind::SUMP_MUD};
			return {make_one(TRAPS[*r.range(0, 2)], tile(), 1, 1, "trap")};
		}
		case 2:
			return {make_one(PlacedKind::ITEM, tile(), 1, 1, *r.range(0, 1) == 0 ? "poi" : "plan", "fuse")};
		case 3: {
			Placement man = make_one(PlacedKind::REMAINS, tile(), 1, 1, "remains");
			Placement lamp = make_one(PlacedKind::ITEM, man.tile, 1, 1, "remains", "gauze_lamp");
			lamp.with = 0; // the unit's first
			return {man, lamp};
		}
		case 4: {
			// The base cell's alternate (its north road at (10, 5)), or a box anywhere.
			Placement x = make_one(PlacedKind::COLLAPSE, lb::core::world::tile_of(cell, {10, 5}), 1, 1, "collapse");
			x.collapse = 1;
			if (*r.range(0, 2) == 0) {
				x.tile = tile(0, 17);
				x.w = static_cast<int32_t>(*r.range(1, 3));
				x.collapse = 99;
			}
			return {x};
		}
		case 5:
			return {make_one(PlacedKind::AIR_DOOR, lb::core::world::tile_of(cell, {*r.range(0, 8), 9}), 1, 3, "door")};
		case 6:
			return {make_one(PlacedKind::COAT_HEAP, lb::core::world::tile_of(cell, {10, *r.range(3, 7)}), 1, 1, "heap")};
		default:
			return {make_one(PlacedKind::ITEM, lb::core::world::tile_of(cell, {*r.range(8, 12), *r.range(8, 12)}), 1, 1, "loose", "paraffin_can")};
	}
}

// `base` with `units` inserted at random places, every `with` kept pointing at its man.
std::vector<Placement> inject(const std::vector<Placement> &base, const std::vector<std::vector<Placement>> &units, lb::core::Rng &r) {
	std::vector<std::vector<size_t>> at(base.size() + 1);
	for (size_t u = 0; u < units.size(); u++) {
		at[static_cast<size_t>(*r.range(0, static_cast<int64_t>(base.size())))].push_back(u);
	}
	std::vector<Placement> out;
	std::vector<int32_t> moved(base.size(), -1);
	auto put_units = [&](size_t slot) {
		for (size_t u : at[slot]) {
			const int32_t start = static_cast<int32_t>(out.size());
			for (Placement x : units[u]) {
				if (x.with >= 0) {
					x.with += start;
				}
				out.push_back(x);
			}
		}
	};
	for (size_t i = 0; i < base.size(); i++) {
		put_units(i);
		moved[i] = static_cast<int32_t>(out.size());
		out.push_back(base[i]);
	}
	put_units(base.size());
	for (size_t i = 0; i < base.size(); i++) {
		Placement &x = out[static_cast<size_t>(moved[i])];
		if (x.with >= 0) {
			x.with = moved[static_cast<size_t>(x.with)];
		}
	}
	return out;
}

} // namespace

TEST_CASE("GEN-12 strict mode never yields a rule violation (1,000,000 cells with injected failures)") {
	place_fixture::World w;
	place_fixture::reset(w, 5);
	w.spine = [](Coord c) { return c.x == 3 && c.y != 0; };
	w.proto.sockets = base_sockets();
	const PlacementParams pp;
	ValidatorParams vp;
	vp.arch_reach = {8, 8, 8, 8};
	std::vector<Coord> cells;
	for (int64_t y = -7; y <= 7; y++) {
		for (int64_t x = -7; x <= 7; x++) {
			cells.push_back({x, y});
		}
	}
	cells.push_back({12, 3}); // ring 1
	cells.push_back({-14, 9}); // ring 2
	std::vector<PlacementContext> contexts;
	std::vector<std::vector<Placement>> lists;
	for (const Coord &c : cells) {
		contexts.push_back(placement_context(w, pp, vp, c));
		lists.push_back(place_cell(w, pp, c));
		// GEN-10's own lists already pass.
		CHECK_MESSAGE(validate_placement(contexts.back(), lists.back()).ok(), describe(validate_placement(contexts.back(), lists.back())));
	}
	int64_t n = 1000000;
	if (const char *v = std::getenv("LB_STRICT_FUZZ_CELLS")) {
		n = std::max<int64_t>(1, std::atoll(v));
	}
	lb::core::Rng r(0x5791C7ull);
	int64_t injected_failing = 0;
	int64_t dropped_total = 0;
	int64_t bad = 0;
	std::map<Check, int64_t> caught;
	for (int64_t i = 0; i < n; i++) {
		const size_t k = static_cast<size_t>(*r.range(0, static_cast<int64_t>(cells.size()) - 1));
		std::vector<std::vector<Placement>> units;
		const int64_t m = *r.range(1, 4);
		for (int64_t j = 0; j < m; j++) {
			units.push_back(failure(r, cells[k]));
		}
		const std::vector<Placement> given = inject(lists[k], units, r);
		const Verdict before = validate_placement(contexts[k], given);
		if (!before.ok()) {
			injected_failing++;
			caught[before.check]++;
		}
		int32_t dropped = 0;
		const std::vector<Placement> kept = strict_placement(contexts[k], given, &dropped);
		dropped_total += dropped;
		const Verdict after = validate_placement(contexts[k], kept);
		bool ok = after.ok() && static_cast<size_t>(dropped) + kept.size() == given.size();
		// A subsequence of what it was given, each man's things still with him.
		size_t at = 0;
		for (size_t q = 0; q < kept.size() && ok; q++) {
			while (at < given.size() && !same_placement(given[at], kept[q])) {
				at++;
			}
			ok = at < given.size();
			if (ok && kept[q].with >= 0) {
				ok = static_cast<size_t>(kept[q].with) < q && given[at].with >= 0 && same_placement(kept[static_cast<size_t>(kept[q].with)], given[static_cast<size_t>(given[at].with)]);
			}
			at++;
		}
		if (!ok) {
			bad++;
			if (bad <= 3) {
				MESSAGE("cell (" << cells[k].x << ", " << cells[k].y << ") iteration " << i << ": " << describe(after));
			}
		}
	}
	CHECK(bad == 0);
	MESSAGE(n << " cells fuzzed: " << injected_failing << " broke a rule, " << dropped_total << " placements dropped");
	CHECK(injected_failing > n / 5);
	// Every check phase 2 holds was tripped by an injection.
	for (Check c : {Check::NEAR_HOME, Check::GAS, Check::ARCHES, Check::COLLAPSE_SPACING, Check::SPINE_COLLAPSE, Check::CLEAR_GROUND}) {
		CHECK_MESSAGE(caught[c] > 0, check_name(c));
	}
}
