// GEN-09: what each point of interest holds. Each kind's contents match §12.4's table (and the
// Proposed numbers where it is silent) over many hashes, every line within its kind's slots; found
// lamps hold 25-75% oil and 0-3 notches. The plan's quantities replace the table's where GEN-08
// fixed them, and its parts lie only where it planned them: every planned holding present, no part
// in a drawn point of interest. Dry Stores halves fuel stores' paraffin and lamp cabins' lamp oil,
// One Lamp takes every lamp, Dead Lines every phone. At most one canary a run: in the first
// first-aid station of the canary region GEN-10 names, and none without one.

#include "poi_fixture.h"

#include <doctest.h>

using namespace poi_fixture;

namespace {

const std::set<std::string> PARTS{"magneto", "drive_belt", "brake_shoe", "drum_gear", "rope_clamp"};
const std::set<std::string> TOOLS{"spanner", "hammer", "crowbar", "wire_cutters"};

std::map<std::string, int64_t> counts(const std::vector<Content> &list) {
	std::map<std::string, int64_t> out;
	for (const Content &c : list) {
		out[c.thing]++;
	}
	return out;
}

int64_t tools_in(const std::vector<Content> &list, int32_t line) {
	int64_t n = 0;
	std::set<std::string> seen;
	for (const Content &c : list) {
		if (c.line == line && TOOLS.count(c.thing) != 0) {
			n++;
			CHECK(seen.insert(c.thing).second); // no two alike
		}
	}
	return n;
}

Poi drawn(PoiKind kind, int32_t index) {
	Poi p;
	p.id = PoiId{Coord{3, 1}, index};
	p.kind = kind;
	return p;
}

bool between(int64_t v, int64_t lo, int64_t hi) {
	return v >= lo && v <= hi;
}

} // namespace

TEST_CASE("GEN-09 each kind holds what its table lists") {
	const PoiContentsParams params;
	RunHeader h;
	h.seed = 0xC0A7E;
	int64_t store_tools = 0;
	int64_t carried = 0;
	for (int32_t i = 0; i < 400; i++) {
		for (size_t k = 0; k < static_cast<size_t>(PoiKind::COUNT); k++) {
			const PoiKind kind = static_cast<PoiKind>(k);
			const std::vector<Content> list = poi_contents(h, params, drawn(kind, i), false);
			const std::map<std::string, int64_t> n = counts(list);
			auto at = [&](const std::string &thing) { return n.count(thing) != 0 ? n.at(thing) : 0; };
			for (const Content &c : list) {
				CHECK((c.line == -1 ? c.thing == "phone" : c.line < lines_of(kind)));
				if (c.thing == "gauze_lamp") {
					CHECK(between(c.oil_milli, 250, 750));
					CHECK(between(c.notches, 0, 3));
				}
			}
			CHECK(at("phone") == (phone_of(kind) ? 1 : 0));
			size_t expected_kinds = 0;
			switch (kind) {
				case PoiKind::LAMP_CABIN:
					CHECK(between(at("gauze_lamp"), 2, 4));
					CHECK(between(at("oil_flask"), 1, 2));
					CHECK(at("paraffin_can") == 1);
					expected_kinds = 4;
					break;
				case PoiKind::FITTERS_SHOP:
					CHECK(between(tools_in(list, 0), 1, 2));
					expected_kinds = static_cast<size_t>(tools_in(list, 0)) + 1;
					break;
				case PoiKind::STORES:
					CHECK(between(at("fuse"), 1, 3));
					CHECK(between(at("candle"), 1, 3));
					CHECK(at("paraffin_can") == 1);
					store_tools += tools_in(list, 3);
					expected_kinds = 3 + static_cast<size_t>(tools_in(list, 3));
					break;
				case PoiKind::FUEL_STORE:
					CHECK(between(at("paraffin_can"), 2, 4));
					for (const Content &c : list) {
						CHECK(c.oil_milli == -1); // full cans
					}
					expected_kinds = 1;
					break;
				case PoiKind::ELECTRICIANS_CABIN:
					CHECK(between(at("fuse"), 2, 3));
					CHECK(at("wire_cutters") == 1);
					expected_kinds = 2;
					break;
				case PoiKind::SUBSTATION:
					CHECK(at("fuse") == 1);
					expected_kinds = 2;
					break;
				case PoiKind::HAULAGE_ENGINE_HOUSE:
					CHECK(at("hammer") == 1);
					CHECK(at("tub") == 1);
					expected_kinds = 2;
					break;
				case PoiKind::DEEP_WORKSHOP:
					CHECK(at("spanner") == 1);
					expected_kinds = 1;
					break;
				case PoiKind::FIRST_AID_STATION:
					CHECK(between(at("healing_kit"), 1, 2));
					CHECK(at("stretcher") == 1);
					CHECK(between(at("flare"), 1, 2));
					CHECK(at("canary") == 0);
					expected_kinds = 4;
					break;
				case PoiKind::POWDER_MAGAZINE:
					CHECK(between(at("flare"), 2, 3));
					expected_kinds = 1;
					break;
				case PoiKind::REFUGE: {
					CHECK(between(at("remains"), 2, 4));
					std::map<int32_t, int64_t> held;
					for (const Content &c : list) {
						if (c.thing != "remains") {
							REQUIRE(c.with >= 0);
							CHECK(list[static_cast<size_t>(c.with)].thing == "remains");
							held[c.with]++;
							carried++;
						}
					}
					for (const auto &entry : held) {
						CHECK(entry.second <= 2);
					}
					expected_kinds = n.size();
					break;
				}
				case PoiKind::STABLES:
				case PoiKind::CAPPED_SHAFT:
					CHECK(at("lore") == 1);
					expected_kinds = 1;
					break;
				case PoiKind::HOARD:
					CHECK(at("coats") == 1);
					CHECK(between(at("gauze_lamp"), 2, 4));
					expected_kinds = 2;
					break;
				case PoiKind::LAIR:
					CHECK(between(at("remains"), 2, 4));
					CHECK(between(at("gauze_lamp"), 3, 6));
					CHECK(at("brass_checks") == 1);
					CHECK(between(tools_in(list, 3), 1, 2));
					CHECK(between(at("healing_kit"), 1, 2));
					for (const Content &c : list) {
						CHECK(c.with == -1); // the men laid out carry nothing: their lamps are in the rows
					}
					expected_kinds = 4 + static_cast<size_t>(tools_in(list, 3));
					break;
				default:
					break;
			}
			CHECK(n.size() == expected_kinds);
			for (const auto &entry : n) {
				CHECK(PARTS.count(entry.first) == 0); // no part outside the plan
			}
		}
	}
	// Stores hold a tool 30% of the time; remains carry a few things.
	CHECK(static_cast<double>(store_tools) / 400.0 == doctest::Approx(0.3).epsilon(0.25));
	CHECK(carried > 100);
}

TEST_CASE("GEN-09 the plan's quantities and parts lie only where it planned them, over 10,000 seeds") {
	const PoiContentsParams params;
	int64_t sites = 0;
	int64_t parts = 0;
	for (uint64_t s = 0; s < 10000; s++) {
		const RunHeader h = plan_fixture::planned(lb::core::mix64(s * 13 + 0xC0A70), static_cast<int32_t>(s % 3));
		REQUIRE(h.plan.error.empty());
		for (size_t i = 0; i < h.plan.sites.size(); i++) {
			const PlannedSite &site = h.plan.sites[i];
			Poi p;
			p.id = PoiId{lb::core::world::region_of_cell(site.door), static_cast<int32_t>(i)};
			p.kind = site.kind;
			p.planned = static_cast<int32_t>(i);
			const std::vector<Content> list = poi_contents(h, params, p, false);
			const std::map<std::string, int64_t> n = counts(list);
			for (const Holding &hold : site.holds) {
				CHECK_MESSAGE((n.count(hold.item) != 0 && n.at(hold.item) == hold.count), poi_kind_name(site.kind), " holds ", hold.item);
				parts += PARTS.count(hold.item);
			}
			for (const auto &[thing, count] : n) {
				if (PARTS.count(thing) != 0) {
					CHECK(site.count_of(thing) == count);
				}
			}
			for (const Content &c : list) {
				CHECK((c.line == -1 || c.line < lines_of(site.kind)));
			}
			sites++;
		}
	}
	MESSAGE(sites, " planned sites, ", parts, " part holdings");
	CHECK(parts > 10000);
	// Drawn points of interest over 200 runs' regions: never a part.
	for (uint64_t s = 0; s < 200; s++) {
		const auto r = run(lb::core::mix64(s + 0xC0A71), static_cast<int32_t>(s % 3));
		for (const Coord &region : regions()) {
			for (const Poi &p : r->pois->region(region)->pois) {
				if (p.planned >= 0) {
					continue;
				}
				for (const Content &c : poi_contents(r->head, params, p, false)) {
					CHECK(PARTS.count(c.thing) == 0);
				}
			}
		}
	}
}

TEST_CASE("GEN-09 Dry Stores, One Lamp and Dead Lines") {
	const PoiContentsParams params;
	RunHeader dry;
	dry.seed = 0xD47;
	dry.draw = {"dry_stores"};
	RunHeader one_lamp = dry;
	one_lamp.draw.clear();
	one_lamp.hard_variant = "one_lamp";
	RunHeader dead = one_lamp;
	dead.hard_variant = "dead_lines";
	for (int32_t i = 0; i < 200; i++) {
		for (const Content &c : poi_contents(dry, params, drawn(PoiKind::FUEL_STORE, i), false)) {
			CHECK(c.oil_milli == 500); // light cans
		}
		for (const Content &c : poi_contents(dry, params, drawn(PoiKind::LAMP_CABIN, i), false)) {
			if (c.thing == "gauze_lamp") {
				CHECK(between(c.oil_milli, 125, 375));
			} else {
				CHECK(c.oil_milli == -1); // its flasks and can are full
			}
		}
		for (const Content &c : poi_contents(dry, params, drawn(PoiKind::HOARD, i), false)) {
			if (c.thing == "gauze_lamp") {
				CHECK(between(c.oil_milli, 250, 750)); // only lamp cabins' lamps run low
			}
		}
		for (size_t k = 0; k < static_cast<size_t>(PoiKind::COUNT); k++) {
			const PoiKind kind = static_cast<PoiKind>(k);
			const std::map<std::string, int64_t> lamp = counts(poi_contents(one_lamp, params, drawn(kind, i), true));
			CHECK(lamp.count("gauze_lamp") == 0);
			CHECK(lamp.count("phone") == (phone_of(kind) ? 1u : 0u));
			const std::map<std::string, int64_t> lines = counts(poi_contents(dead, params, drawn(kind, i), true));
			CHECK(lines.count("phone") == 0);
		}
		const std::map<std::string, int64_t> cabin = counts(poi_contents(one_lamp, params, drawn(PoiKind::LAMP_CABIN, i), false));
		CHECK(between(cabin.at("oil_flask"), 1, 2)); // only flasks and their can
		CHECK(cabin.at("paraffin_can") == 1);
		const std::map<std::string, int64_t> hoard = counts(poi_contents(one_lamp, params, drawn(PoiKind::HOARD, i), false));
		CHECK(hoard.size() == 1); // only coats
	}
}

TEST_CASE("GEN-09 one canary a run at most, in the canary region's first first-aid station") {
	const PoiContentsParams params;
	int64_t runs_with = 0;
	for (uint64_t s = 0; s < 200; s++) {
		const auto r = run(lb::core::mix64(s + 0xCA4A), static_cast<int32_t>(s % 3));
		auto canaries = [&]() {
			int64_t n = 0;
			for (const Coord &region : regions()) {
				for (const Poi &p : r->pois->region(region)->pois) {
					for (const Content &c : poi_contents(r->head, params, p, r->pois->is_canary(p.id))) {
						n += c.thing == "canary" ? 1 : 0;
					}
				}
			}
			return n;
		};
		CHECK(canaries() == 0);
		std::optional<Coord> with;
		for (const Coord &region : regions()) {
			for (const Poi &p : r->pois->region(region)->pois) {
				if (!with && p.kind == PoiKind::FIRST_AID_STATION) {
					with = region;
				}
			}
		}
		if (!with) {
			continue;
		}
		r->head.homes["canary"] = canary_home(*with);
		REQUIRE(canary_region(r->head) == with);
		CHECK(canaries() == 1);
		const Poi *first = nullptr;
		for (const Poi &p : r->pois->region(*with)->pois) {
			if (first == nullptr && p.kind == PoiKind::FIRST_AID_STATION) {
				first = &p;
			}
		}
		REQUIRE(first != nullptr);
		CHECK(r->pois->is_canary(first->id));
		runs_with++;
		// mine.canary_max_per_run 0: none at all.
		PoiParams none;
		none.canary_max = 0;
		const PointsOfInterest off(r->head, shapes_of(r->set), none, r->world());
		CHECK_FALSE(off.is_canary(first->id));
	}
	CHECK(runs_with > 150);
}
