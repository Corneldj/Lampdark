// GEN-05: edge keys, the hashed socket's symmetry and rates, the opening rule and precedence.

#include "core/rng/rng.h"
#include "layout_fixture.h"

#include <doctest.h>

#include <map>

using namespace layout_fixture;

namespace {

struct Picker {
	lb::core::Rng rng;
	explicit Picker(uint64_t seed) : rng(seed) {}
	int64_t coord() { return static_cast<int64_t>(rng.next_u64() % 4001) - 2000; }
	uint64_t seed() { return rng.next_u64(); }
	Edge side() { return static_cast<Edge>(rng.next_u64() % 4); }
};

} // namespace

TEST_CASE("GEN-05 both neighbours name one edge and read one socket") {
	CHECK(edge_of({3, 4}, Edge::EAST) == edge_of({4, 4}, Edge::WEST));
	CHECK(edge_of({3, 4}, Edge::SOUTH) == edge_of({3, 5}, Edge::NORTH));
	CHECK(edge_of({3, 4}, Edge::EAST) == EdgeKey{3, 4, Axis::EAST});
	CHECK(edge_of({3, 4}, Edge::NORTH) == EdgeKey{3, 3, Axis::SOUTH});
	auto set = template_set();
	Picker pick(11);
	int64_t checked = 0;
	for (int s = 0; s < 1000; s++) {
		Run r = run(pick.seed(), set);
		const DeriveInputs in = r.inputs();
		for (int i = 0; i < 1000; i++) {
			const Coord c{pick.coord(), pick.coord()};
			const Edge e = pick.side();
			const Socket a = derive_socket(in, edge_of(c, e));
			const Socket b = derive_socket(in, edge_of(neighbour(c, e), opposite(e)));
			if (!(a == b)) {
				FAIL("cell (" << c.x << ", " << c.y << ") side " << static_cast<int>(e) << " disagrees with its neighbour");
			}
			checked++;
		}
	}
	CHECK(checked == 1000000);
}

TEST_CASE("GEN-05 the hashed sockets open at 0.6 with uniform offsets and widths") {
	SocketParams p;
	Picker pick(12);
	std::map<int32_t, int64_t> offsets;
	std::map<int32_t, int64_t> widths;
	int64_t open = 0;
	const int64_t n = 1000000;
	for (int64_t i = 0; i < n; i++) {
		const EdgeKey e{pick.coord(), pick.coord(), static_cast<Axis>(pick.rng.next_u64() % 2)};
		const Socket s = hashed_socket(pick.seed(), e, p, p.widths);
		if (s.open) {
			open++;
			offsets[s.offset]++;
			widths[s.width]++;
		}
	}
	const double rate = static_cast<double>(open) / n;
	MESSAGE("open rate ", rate);
	CHECK(rate > 0.595);
	CHECK(rate < 0.605);
	REQUIRE(offsets.size() == 3);
	REQUIRE(widths.size() == 3);
	for (const auto &[o, count] : offsets) {
		CHECK(std::abs(static_cast<double>(count) / open - 1.0 / 3.0) < 0.01 / 3.0);
	}
	for (const auto &[w, count] : widths) {
		CHECK(std::abs(static_cast<double>(count) / open - 1.0 / 3.0) < 0.01 / 3.0);
	}
	CHECK(offsets.count(5) == 1);
	CHECK(offsets.count(10) == 1);
	CHECK(offsets.count(15) == 1);
}

TEST_CASE("GEN-05 the open probability never reshuffles an open edge's offset or width") {
	SocketParams more;
	more.open_ppm = 800000;
	SocketParams fewer;
	fewer.open_ppm = 400000;
	Picker pick(13);
	int64_t both = 0;
	for (int i = 0; i < 100000; i++) {
		const uint64_t seed = pick.seed();
		const EdgeKey e{pick.coord(), pick.coord(), static_cast<Axis>(pick.rng.next_u64() % 2)};
		const Socket a = hashed_socket(seed, e, more, more.widths);
		const Socket b = hashed_socket(seed, e, fewer, fewer.widths);
		if (b.open) {
			REQUIRE(a.open); // opening fewer edges only shuts some
			CHECK(a.offset == b.offset);
			CHECK(a.width == b.width);
			both++;
		}
	}
	CHECK(both > 30000);
}

TEST_CASE("GEN-05 an opening covers o - floor(w / 2) for w tiles") {
	CHECK(opening_first(10, 1) == 10);
	CHECK(opening_first(10, 2) == 9);
	CHECK(opening_first(10, 3) == 9);
	CHECK(opening_first(5, 2) == 4);
	CHECK(opening_first(15, 3) == 14);
}

TEST_CASE("GEN-05 widths are ones both cells allow") {
	SocketParams p;
	CHECK(shared_widths({1, 2, 3}, {2, 3}, p) == std::vector<int32_t>{2, 3});
	CHECK(shared_widths({3, 1}, {1}, p) == std::vector<int32_t>{1});
	CHECK(shared_widths({3}, {1}, p) == std::vector<int32_t>{1}); // none shared: GEN-06 decides; the narrowest until then
	Picker pick(14);
	for (int i = 0; i < 10000; i++) {
		const Socket s = hashed_socket(pick.seed(), EdgeKey{pick.coord(), pick.coord(), Axis::SOUTH}, p, {2, 3});
		if (s.open) {
			CHECK((s.width == 2 || s.width == 3));
		}
	}
}

TEST_CASE("GEN-05 forced sockets beat the hash in precedence order; base camp's gates open, its blind side shut") {
	auto set = template_set();
	for (uint64_t seed = 1; seed <= 2000; seed++) {
		Run r = run(seed * 7919, set);
		const DeriveInputs in = r.inputs();
		const Edge blind = blind_side(r.head.seed);
		const CellSockets s = derive_sockets(in, {0, 0});
		for (int e = 0; e < 4; e++) {
			const bool gate = static_cast<Edge>(e) != blind;
			CHECK(s[static_cast<size_t>(e)].forced);
			CHECK(s[static_cast<size_t>(e)].open == gate);
			if (gate) {
				CHECK(s[static_cast<size_t>(e)].offset == 10);
				CHECK(s[static_cast<size_t>(e)].width == 3);
			}
		}
	}
	Run r = run(99, set);
	const EdgeKey edge{5, 5, Axis::EAST};
	FixedSockets poi; // rule 2 beats rule 3, and both beat the hash
	Socket door;
	door.open = true;
	door.offset = 15;
	door.width = 1;
	poi.set(edge, door);
	FixedSockets main_road;
	Socket road;
	road.open = true;
	road.offset = 10;
	road.width = 3;
	main_road.set(edge, road);
	main_road.set(EdgeKey{6, 5, Axis::EAST}, road);
	DeriveInputs in = r.inputs();
	in.providers = {&poi, &main_road};
	CHECK(derive_socket(in, edge).offset == 15);
	CHECK(derive_socket(in, EdgeKey{6, 5, Axis::EAST}).offset == 10);
	CHECK(derive_socket(in, EdgeKey{6, 5, Axis::EAST}).forced);
	CHECK_FALSE(derive_socket(in, EdgeKey{7, 5, Axis::EAST}).forced);
	r.head.forced.set(edge, Socket{}); // the header's own (base camp's) beat every provider
	CHECK_FALSE(derive_socket(in, edge).open);
}
