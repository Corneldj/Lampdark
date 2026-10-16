// GEN-05: derive_layout is pure: const inputs only, the same result with caches on or off, and
// nothing the world holds (loaded cells, the diff log, entities) can reach it.

#include "core/world/mine_map.h"
#include "layout_fixture.h"

#include <doctest.h>

#include <chrono>
#include <type_traits>

using namespace layout_fixture;

// The inputs are const pointers: derive_layout can read the header, the set and the classifier,
// and can write none of them. No world pointer is among them.
static_assert(std::is_same_v<decltype(DeriveInputs::header), const RunHeader *>);
static_assert(std::is_same_v<decltype(DeriveInputs::templates), const TemplateSet *>);
static_assert(std::is_same_v<decltype(DeriveInputs::cells), const CellClassifier *>);

TEST_CASE("GEN-05 the same inputs, the same layout, with caches on or off") {
	auto set = template_set();
	Run r = run(31337, set);
	Deriver cached(r.inputs());
	Deriver plain(r.inputs());
	plain.set_caching(false);
	cached.set_verify(true);
	for (int64_t y = -6; y <= 6; y++) {
		for (int64_t x = -6; x <= 6; x++) {
			const std::optional<Layout> a = cached.derive({x, y}, 0);
			const std::optional<Layout> b = plain.derive({x, y}, 0);
			const std::optional<Layout> c = derive_layout(r.inputs(), {x, y}, 0);
			REQUIRE(a.has_value());
			CHECK(a->digest == b->digest);
			CHECK(a->digest == c->digest);
			CHECK(cached.derive({x, y}, 0)->digest == a->digest); // a cache hit
		}
	}
	CHECK(cached.verify_failures() == 0);
	CHECK(derive_layout(r.inputs(), {0, 0}, 0)->base_camp);
}

TEST_CASE("GEN-05 changing loaded cells, the diff log or entities never changes a derived layout") {
	auto set = template_set();
	Run r = run(4242, set);
	Deriver d(r.inputs());
	std::vector<uint64_t> before;
	MineMap mine; // the world: what derive_layout must never see
	for (int64_t x = 1; x <= 8; x++) {
		const std::optional<Layout> l = d.derive({x, 2}, 0);
		REQUIRE(l.has_value());
		before.push_back(l->digest);
		mine.commit(std::make_unique<Cell>(l->cell));
	}
	// The diff log's kinds of change: tiles changed in place (a loaded cell replaced by an edited
	// copy), collapses fallen; then evict and re-derive.
	for (int64_t x = 1; x <= 8; x++) {
		Cell edited = *mine.cell({x, 2});
		for (Tile &t : edited.tiles) {
			t.material = t.material == static_cast<uint8_t>(TileMaterial::FLOOR) ? static_cast<uint8_t>(TileMaterial::ROCK)
																				 : static_cast<uint8_t>(TileMaterial::FLOOR);
		}
		mine.commit(std::make_unique<Cell>(edited));
		for (const Collapse &c : mine.cell({x, 2})->collapses) {
			mine.set_collapse({x, 2}, c.id, true);
		}
	}
	d.clear_caches();
	for (int64_t x = 1; x <= 8; x++) {
		CHECK(d.derive({x, 2}, 0)->digest == before[static_cast<size_t>(x - 1)]);
	}
}

TEST_CASE("GEN-05 sockets and template choice take under 0.1 ms a cell") {
	auto set = template_set();
	Run r = run(77, set);
	const DeriveInputs in = r.inputs();
	const int64_t n = 10000;
	uint64_t sink = 0;
	const auto start = std::chrono::steady_clock::now();
	for (int64_t i = 0; i < n; i++) {
		const Coord c{i % 100 + 1, i / 100 + 1};
		const CellSockets s = derive_sockets(in, c);
		const Choice choice = choose_template(*set, TemplateKind::BIOME_CELL, "seam", s, r.head.seed, c, 0, 20);
		sink += choice.chosen != nullptr ? choice.chosen->id.size() : 0;
	}
	const double us = std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - start).count() / n;
	const auto full_start = std::chrono::steady_clock::now();
	for (int64_t i = 0; i < 1000; i++) {
		sink += derive_layout(in, {i % 40 + 1, i / 40 + 1}, 0)->digest & 1u;
	}
	const double full_us = std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - full_start).count() / 1000;
	MESSAGE("sockets and choice ", us, " us a cell; the whole layout with its stub fill and zone cut ", full_us, " us (", sink, ")");
	CHECK(us < 100.0);
}
