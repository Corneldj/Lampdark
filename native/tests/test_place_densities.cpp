// GEN-10: every density of §12.5's two tables, over 10,000 seeds, lands within 10% (relative) of
// its target in the rings and biomes it applies to: remains, single paraffin cans, pit phones,
// air doors, collapse points, firedamp, blackdamp, man-traps, staple pits, sump mud, coat heaps
// and Tapper-rich rock.

#include "place_fixture.h"

#include <doctest.h>

#include <algorithm>

#include <map>
#include <string>

using namespace place_fixture;

namespace {

struct Tally {
	int64_t hits = 0;
	int64_t of = 0;
	double rate() const { return of > 0 ? static_cast<double>(hits) / static_cast<double>(of) : 0.0; }
};

void near_target(const std::map<std::string, Tally> &t, const std::string &name, double target) {
	const auto it = t.find(name);
	REQUIRE_MESSAGE(it != t.end(), name);
	const Tally &x = it->second;
	INFO(name << ": " << x.hits << " of " << x.of << " = " << x.rate() << ", target " << target);
	CHECK(x.of > 1000);
	CHECK(x.rate() >= 0.9 * target);
	CHECK(x.rate() <= 1.1 * target);
}

} // namespace

TEST_CASE("GEN-10 densities land within 10% of their targets over 10,000 seeds") {
	const PlacementParams p;
	World w;
	std::map<std::string, Tally> t;
	Tally masses;
	for (uint64_t s = 0; s < 10000; s++) {
		const uint64_t seed = lb::core::mix64(s * 31 + 0x91ACE);
		reset(w, seed, p);
		const Homes homes = read_homes(w.head);
		const int64_t row = static_cast<int64_t>(s % 9) - 4;
		for (int64_t x = 4; x < 34; x++) {
			const Coord c{x, row};
			const CellFacts f = w.facts(c);
			const std::vector<Placement> list = place_cell(w, p, c);
			const bool bs = f.biome == "black_seam";
			const bool ow = f.biome == "old_workings";
			auto tally = [&](const std::string &name, bool applies, int64_t hits, int64_t of = 1) {
				if (applies) {
					t[name].hits += hits;
					t[name].of += of;
				}
			};
			int64_t own_phones = 0;
			for (const Placement &ph : of_kind(list, PlacedKind::PHONE)) {
				own_phones += ph.source == "phone" ? 1 : 0;
			}
			tally("remains", f.ring >= 1 && f.ring <= 3, count(list, PlacedKind::REMAINS));
			int64_t cans = 0;
			for (const Placement &it : of_kind(list, PlacedKind::ITEM)) {
				cans += it.thing == "paraffin_can" && it.source == "loose" ? 1 : 0;
			}
			tally("paraffin", f.ring >= 1 && f.ring <= 2, cans);
			tally("phone ring 1-2", f.ring >= 1 && f.ring <= 2, own_phones);
			tally("phone beyond", f.ring >= 3, own_phones);
			const bool off_main = f.main_road || w.main_road({c.x, c.y - 1});
			tally("air door", off_main, count(list, PlacedKind::AIR_DOOR), 1);
			tally("collapse", true, count(list, PlacedKind::COLLAPSE));
			tally("firedamp ring 2", f.ring == 2 && !bs, count(list, PlacedKind::FIREDAMP));
			tally("firedamp beyond", f.ring >= 3 && !bs, count(list, PlacedKind::FIREDAMP));
			tally("firedamp black seam", bs, count(list, PlacedKind::FIREDAMP));
			tally("blackdamp", ow, count(list, PlacedKind::BLACKDAMP));
			tally("man-trap", f.ring >= 2, count(list, PlacedKind::MAN_TRAP));
			tally("staple pit", ow && f.ring >= 2, count(list, PlacedKind::STAPLE_PIT));
			tally("sump mud", f.ring >= 1, count(list, PlacedKind::SUMP_MUD));
			// The chamber's heaps: roost chambers always have them; the rest by distance.
			const TileBox chamber{c.x * 20 + 7, c.y * 20 + 13, 6, 6};
			const bool roost = std::find(homes.roosts.begin(), homes.roosts.end(), chamber) != homes.roosts.end();
			if (!roost) {
				const int64_t dx = 2 * chamber.x + chamber.w - (2 * homes.hoard->x + 1);
				const int64_t dy = 2 * chamber.y + chamber.h - (2 * homes.hoard->y + 1);
				const bool near = dx * dx + dy * dy <= 4 * 80 * 80;
				tally(near ? "heaps near" : "heaps far", true, count(list, PlacedKind::COAT_HEAP) > 0 ? 1 : 0);
			}
		}
		masses.hits += static_cast<int64_t>(rich_rock_masses(w, p, {3, static_cast<int64_t>(s % 5) - 2}).size());
		masses.of += 1;
	}
	near_target(t, "remains", 1.0 / 6.0);
	near_target(t, "paraffin", 1.0 / 8.0);
	near_target(t, "phone ring 1-2", 1.0 / 6.0);
	near_target(t, "phone beyond", 1.0 / 10.0);
	near_target(t, "air door", 1.0 / 3.0);
	near_target(t, "collapse", 1.0 / 2.0);
	near_target(t, "firedamp ring 2", 1.0 / 4.0);
	near_target(t, "firedamp beyond", 1.0 / 2.0);
	near_target(t, "firedamp black seam", 1.0);
	near_target(t, "blackdamp", 1.0 / 3.0);
	near_target(t, "man-trap", 1.0 / 10.0);
	near_target(t, "staple pit", 1.0 / 6.0);
	near_target(t, "sump mud", 1.0 / 5.0);
	near_target(t, "heaps near", 0.5);
	near_target(t, "heaps far", 0.05);
	INFO("rich rock: " << masses.hits << " masses in " << masses.of << " regions");
	CHECK(masses.rate() >= 1.8);
	CHECK(masses.rate() <= 2.2);
}
