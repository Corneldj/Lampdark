// GEN-10's remains (Gameplay §12.5): what a man carried, never a body. Each holds 0-2 items, the
// table's rolls in order (lamp 25%, flare 10%, kit 5%, tool 10%, note 10%) and the first two kept;
// a found lamp lies with 25-75% oil and 0-3 notches; a tool is one of the four.

#include "place_fixture.h"

#include <doctest.h>

#include <map>

using namespace place_fixture;

TEST_CASE("GEN-10 remains carry the table's items, the first two kept") {
	const PlacementParams p;
	World w;
	int64_t remains = 0;
	std::map<std::string, int64_t> held;
	for (uint64_t s = 0; s < 6000; s++) {
		reset(w, lb::core::mix64(s + 0x2E4A), p);
		for (int64_t x = 4; x < 24; x++) {
			const std::vector<Placement> list = place_cell(w, p, {x, 2});
			for (size_t i = 0; i < list.size(); i++) {
				if (list[i].kind != PlacedKind::REMAINS || list[i].source != "remains") {
					continue;
				}
				remains++;
				int64_t carried = 0;
				for (const Placement &it : list) {
					if (it.with != static_cast<int32_t>(i)) {
						continue;
					}
					carried++;
					CHECK(it.kind == PlacedKind::ITEM);
					CHECK(it.tile == list[i].tile);
					std::string name = it.thing;
					if (name == "spanner" || name == "hammer" || name == "crowbar" || name == "wire_cutters") {
						name = "tool";
					}
					held[name]++;
					if (it.thing == "gauze_lamp") {
						CHECK(it.oil_milli >= 250);
						CHECK(it.oil_milli <= 750);
						CHECK(it.notches >= 0);
						CHECK(it.notches <= 3);
					}
				}
				CHECK(carried <= 2);
			}
		}
	}
	// The chance each is kept: its own, while fewer than two earlier rolls came up.
	const std::vector<std::pair<std::string, double>> table{{"gauze_lamp", 0.25}, {"flare", 0.10}, {"healing_kit", 0.05}, {"tool", 0.10}, {"note", 0.10}};
	std::vector<double> none_or_one{1.0, 0.0}; // P(0 earlier), P(1 earlier)
	for (const auto &[name, chance] : table) {
		const double kept = chance * (none_or_one[0] + none_or_one[1]);
		const double rate = static_cast<double>(held[name]) / static_cast<double>(remains);
		INFO(name << ": " << held[name] << " of " << remains << " remains = " << rate << ", expected " << kept);
		CHECK(rate >= 0.9 * kept);
		CHECK(rate <= 1.1 * kept);
		none_or_one = {none_or_one[0] * (1.0 - chance), none_or_one[1] * (1.0 - chance) + none_or_one[0] * chance};
	}
	CHECK(remains > 3000);
}
