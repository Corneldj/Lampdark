// GEN-12: phase 1 never receives a neighbour's data. validate_layout's inputs are a cell's own
// layout and class (its signature says so), and a cell whose every neighbour changes template
// pool derives the same reroll, template and layout.

#include "validate_fixture.h"

#include <doctest.h>

#include <type_traits>

using namespace validate_fixture;
using lb::core::world::Coord;

static_assert(std::is_same_v<decltype(&validate_layout), Verdict (*)(const Layout &, const CellClass &, const ValidatorParams &)>,
		"phase 1 reads a cell's own layout and class alone");

namespace {

// Every cell seam but those round `centre`, which are `around` (the same widths, so no socket moves).
class Swapped final : public CellClassifier {
public:
	Swapped(Coord centre, std::string around) : centre_(centre), around_(std::move(around)) {}
	CellClass classify(Coord c) const override {
		CellClass k;
		k.widths = {1, 2, 3};
		if (c == Coord{0, 0}) {
			k.kind = TemplateKind::BASE_CAMP;
			k.templated = false;
			return k;
		}
		const bool near = std::max(std::abs(c.x - centre_.x), std::abs(c.y - centre_.y)) == 1;
		k.biome = near ? around_ : "seam";
		return k;
	}

private:
	Coord centre_;
	std::string around_;
};

Template in_biome(Template t, const std::string &biome) {
	t.biome = biome;
	return t;
}

std::shared_ptr<TemplateSet> two_biomes() {
	Spec bad = fallback_spec();
	bad.id = "seam_bad";
	bad.kind = TemplateKind::BIOME_CELL;
	bad.rows[1][1] = '.';
	Template seam_bad = make(bad);
	seam_bad.weight = 3.0;
	Spec ow_fallback = fallback_spec();
	ow_fallback.id = "ow_plain";
	std::vector<Template> list{seam_bad, layout_fixture::grid("seam_good", 1.0), make(fallback_spec()),
			in_biome(layout_fixture::grid("ow_grid", 1.0), "old_workings"), in_biome(make(ow_fallback), "old_workings")};
	auto set = std::make_shared<TemplateSet>();
	REQUIRE(set->load(encode_pack("two", list)));
	return set;
}

} // namespace

TEST_CASE("GEN-12 a cell's final layout ignores its neighbours") {
	const std::shared_ptr<TemplateSet> set = two_biomes();
	const ValidatorParams vp;
	int64_t rerolled = 0;
	for (const Coord centre : {Coord{3, 2}, Coord{-4, 5}, Coord{7, -6}, Coord{1, 9}, Coord{-8, -8}}) {
		layout_fixture::Run a = layout_fixture::run(91, set);
		DeriveInputs in_a = a.inputs();
		in_a.validator = &vp;
		const Swapped swapped(centre, "old_workings");
		DeriveInputs in_b = in_a;
		in_b.cells = &swapped;
		const std::optional<Layout> la = derive_final(in_a, centre);
		const std::optional<Layout> lb = derive_final(in_b, centre);
		REQUIRE(la);
		REQUIRE(lb);
		CHECK(la->reroll == lb->reroll);
		CHECK(la->template_id == lb->template_id);
		CHECK(la->digest == lb->digest);
		CHECK(validate_layout(*la, a.cells.classify(centre), vp).ok() == validate_layout(*lb, swapped.classify(centre), vp).ok());
		rerolled += la->reroll > 0 ? 1 : 0;
		// The neighbours themselves did change.
		for (int e = 0; e < 4; e++) {
			const Coord n = neighbour(centre, static_cast<Edge>(e));
			const std::optional<Layout> na = derive_final(in_a, n);
			const std::optional<Layout> nb = derive_final(in_b, n);
			REQUIRE(na);
			REQUIRE(nb);
			CHECK(na->template_id.rfind("ow_", 0) != 0);
			CHECK(nb->template_id.rfind("ow_", 0) == 0);
		}
	}
	MESSAGE(rerolled << " of the 5 cells rerolled");
}
