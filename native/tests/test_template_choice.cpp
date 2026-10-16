// GEN-05: template choice: covering, weights, the reroll and the fallback.

#include "layout_fixture.h"

#include <doctest.h>

#include <map>

using namespace layout_fixture;

namespace {

CellSockets shut() {
	return CellSockets{};
}

Socket open(int32_t offset, int32_t width) {
	Socket s;
	s.open = true;
	s.offset = offset;
	s.width = width;
	return s;
}

} // namespace

TEST_CASE("GEN-05 a template covers a socket set when every open socket meets a wide enough stub") {
	const Template base = make(Spec{}); // stubs: west 10 (3), east 10 (3), north 10 (1)
	CellSockets s = shut();
	CHECK(covers(base, s));
	s[static_cast<size_t>(Edge::WEST)] = open(10, 3);
	s[static_cast<size_t>(Edge::NORTH)] = open(10, 1);
	CHECK(covers(base, s));
	s[static_cast<size_t>(Edge::NORTH)] = open(10, 2);
	CHECK_FALSE(covers(base, s)); // the north stub is only 1 wide
	s[static_cast<size_t>(Edge::NORTH)] = open(5, 1);
	CHECK_FALSE(covers(base, s)); // no stub at 5
	s[static_cast<size_t>(Edge::NORTH)] = Socket{};
	s[static_cast<size_t>(Edge::SOUTH)] = open(10, 1);
	CHECK_FALSE(covers(base, s)); // no south stub
}

TEST_CASE("GEN-05 the choice is a weighted hash among covering templates, sorted by id") {
	auto set = template_set();
	CellSockets s = shut();
	s[static_cast<size_t>(Edge::EAST)] = open(15, 2);
	std::map<std::string, int64_t> picks;
	for (int64_t x = 0; x < 20000; x++) {
		const Choice c = choose_template(*set, TemplateKind::BIOME_CELL, "seam", s, 42, {x, 3}, 0, 20);
		REQUIRE(c.chosen != nullptr);
		CHECK_FALSE(c.fallback);
		picks[c.chosen->id]++;
		// The same inputs, the same pick.
		CHECK(choose_template(*set, TemplateKind::BIOME_CELL, "seam", s, 42, {x, 3}, 0, 20).chosen == c.chosen);
	}
	REQUIRE(picks.size() == 2); // the base cell has no east stub at 15: only the grids cover
	const double share_b = static_cast<double>(picks["seam_grid_b"]) / 20000.0;
	MESSAGE("grid_b share ", share_b);
	CHECK(share_b > 0.73);
	CHECK(share_b < 0.77); // weights 1 and 3
	// With only a west opening, the base cell covers too.
	CellSockets west = shut();
	west[static_cast<size_t>(Edge::WEST)] = open(10, 2);
	std::map<std::string, int64_t> three;
	for (int64_t x = 0; x < 5000; x++) {
		three[choose_template(*set, TemplateKind::BIOME_CELL, "seam", west, 42, {x, 4}, 0, 20).chosen->id]++;
	}
	CHECK(three.size() == 3);
}

TEST_CASE("GEN-05 a reroll draws again; no candidate, or the reroll limit, takes the plain fallback") {
	auto set = template_set();
	CellSockets s = shut();
	s[static_cast<size_t>(Edge::NORTH)] = open(5, 3);
	int64_t changed = 0;
	for (int64_t x = 0; x < 200; x++) {
		const Template *first = choose_template(*set, TemplateKind::BIOME_CELL, "seam", s, 7, {x, 0}, 0, 20).chosen;
		const Template *second = choose_template(*set, TemplateKind::BIOME_CELL, "seam", s, 7, {x, 0}, 1, 20).chosen;
		changed += first != second ? 1 : 0;
	}
	CHECK(changed > 40);
	const Choice limit = choose_template(*set, TemplateKind::BIOME_CELL, "seam", s, 7, {1, 1}, 20, 20);
	REQUIRE(limit.chosen != nullptr);
	CHECK(limit.fallback);
	CHECK(limit.chosen->id == "fixture_seam_fallback");
	std::vector<Template> only_base{make(Spec{}), make(fallback_spec())};
	TemplateSet small;
	REQUIRE(small.load(encode_pack("small", only_base)));
	const Choice none = choose_template(small, TemplateKind::BIOME_CELL, "seam", s, 7, {1, 1}, 0, 20);
	REQUIRE(none.chosen != nullptr);
	CHECK(none.fallback);
	CHECK(covers(*none.chosen, s));
	const Choice no_biome = choose_template(small, TemplateKind::BIOME_CELL, "black_seam", s, 7, {1, 1}, 0, 20);
	CHECK(no_biome.chosen == nullptr);
	CHECK_FALSE(no_biome.fallback);
}

TEST_CASE("GEN-05 a set loads from its pack and indexes by kind and biome") {
	auto set = template_set();
	CHECK(set->set_version() == "fixture");
	CHECK(set->templates().size() == 4);
	CHECK(set->of(TemplateKind::BIOME_CELL, "seam").size() == 3);
	CHECK(set->of(TemplateKind::BIOME_CELL, "seam")[0]->id == "fixture_seam_01");
	CHECK(set->of(TemplateKind::FALLBACK, "seam").size() == 1);
	CHECK(set->of(TemplateKind::MAIN_ROAD, "seam").empty());
	TemplateSet bad;
	CHECK_FALSE(bad.load({1, 2, 3}));
	CHECK(bad.templates().empty());
}
