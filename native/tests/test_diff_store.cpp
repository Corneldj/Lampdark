#include "core/rng/rng.h"
#include "core/world/diff_store.h"

#include <doctest.h>

#include <algorithm>
#include <numeric>
#include <random>

using namespace lb::core::world;

namespace {

std::vector<uint8_t> bytes(std::initializer_list<int> v) {
	std::vector<uint8_t> out;
	for (int b : v) {
		out.push_back(static_cast<uint8_t>(b));
	}
	return out;
}

} // namespace

TEST_CASE("a write replaces the record at its key: the store holds state, not history") {
	DiffStore s;
	s.put({2, -1}, 3, "item:7", 100, bytes({1, 2}));
	s.put({2, -1}, 3, "item:7", 140, bytes({9}));
	REQUIRE(s.record_count() == 1);
	const auto r = s.get({2, -1}, 3, "item:7");
	REQUIRE(r.has_value());
	CHECK(r->tick == 140);
	CHECK(r->payload == bytes({9}));
	CHECK_FALSE(s.get({2, -1}, 4, "item:7").has_value());
	CHECK(s.erase({2, -1}, 3, "item:7"));
	CHECK_FALSE(s.erase({2, -1}, 3, "item:7"));
	CHECK(s.cells().empty());
}

TEST_CASE("records iterate by kind then key, cells row-major") {
	DiffStore s;
	s.put({1, 0}, 5, "b", 1, {});
	s.put({1, 0}, 2, "z", 1, {});
	s.put({1, 0}, 5, "a", 1, {});
	s.put({-3, 2}, 1, "x", 1, {});
	s.put({4, -2}, 1, "x", 1, {});
	const auto r = s.records({1, 0});
	REQUIRE(r.size() == 3);
	CHECK((r[0].first.kind == 2 && r[0].first.key == "z"));
	CHECK((r[1].first.kind == 5 && r[1].first.key == "a"));
	CHECK((r[2].first.kind == 5 && r[2].first.key == "b"));
	const auto cells = s.cells();
	REQUIRE(cells.size() == 3);
	CHECK(cells[0] == Coord{4, -2});
	CHECK(cells[1] == Coord{1, 0});
	CHECK(cells[2] == Coord{-3, 2});
}

TEST_CASE("blood is packed per cell: the latest smear wins and an erase cleans the tile") {
	DiffStore s;
	s.mark_blood({-1, 5}, 3);
	s.mark_blood({-1, 5}, 10);
	s.mark_blood({-20, 5}, -1);
	CHECK(s.blood_at({-1, 5}) == 2);
	CHECK(s.blood_at({-20, 5}) == 7);
	CHECK(s.blood_at({0, 5}) == -1);
	CHECK(s.blood_count() == 2);
	const auto b = s.blood({-1, 0});
	REQUIRE(b.size() == 2);
	CHECK(b[0].first == Coord{-20, 5});
	CHECK(b[1].first == Coord{-1, 5});
	CHECK(s.erase_blood({-1, 5}));
	CHECK_FALSE(s.erase_blood({-1, 5}));
	CHECK(s.erase_blood({-20, 5}));
	CHECK(s.cells().empty());
}

TEST_CASE("run sections hold keyed payloads outside any cell") {
	DiffStore s;
	s.section_put("map_table", "sheet0:2", bytes({4, 4}));
	s.section_put("map_table", "sheet0:1", bytes({3}));
	s.section_put("pocket_books", "m1:0", bytes({1}));
	CHECK(s.section_keys("map_table") == std::vector<std::string>{"sheet0:1", "sheet0:2"});
	CHECK(s.sections() == std::vector<std::string>{"map_table", "pocket_books"});
	CHECK(s.section_get("map_table", "sheet0:2") == bytes({4, 4}));
	CHECK(s.section_bytes("pocket_books") == 2 + 12 + 4 + 2 + 4 + 4 + 1);
	CHECK(s.section_erase("pocket_books", "m1:0"));
	CHECK(s.sections() == std::vector<std::string>{"map_table"});
}

TEST_CASE("the serialised store round-trips byte for byte, whatever order it was written in") {
	struct Op {
		Coord cell;
		uint8_t kind;
		std::string key;
		int64_t tick;
		std::vector<uint8_t> payload;
	};
	std::vector<Op> ops;
	lb::core::Rng rng(77);
	for (int i = 0; i < 400; i++) {
		Op o{{static_cast<int64_t>(rng.next_u64() % 9) - 4, static_cast<int64_t>(rng.next_u64() % 9) - 4},
				static_cast<uint8_t>(rng.next_u64() % 8), "k" + std::to_string(i), static_cast<int64_t>(i * 3), {}};
		for (uint64_t n = rng.next_u64() % 40; n > 0; n--) {
			o.payload.push_back(static_cast<uint8_t>(rng.next_u64()));
		}
		ops.push_back(o);
	}
	std::vector<size_t> order(ops.size());
	std::iota(order.begin(), order.end(), 0);
	std::vector<uint8_t> first;
	for (int pass = 0; pass < 3; pass++) {
		DiffStore s;
		for (size_t i : order) {
			const Op &o = ops[i];
			s.put(o.cell, o.kind, o.key, o.tick, o.payload);
			s.mark_blood(tile_of(o.cell, {static_cast<int64_t>(i % 20), static_cast<int64_t>(i / 20 % 20)}), static_cast<int64_t>(i));
		}
		s.section_put("map_table", "s", bytes({1, 2, 3}));
		const std::vector<uint8_t> out = s.serialise();
		CHECK(out.size() == s.cells_bytes() + 6 + 4 + s.section_bytes("map_table"));
		if (pass == 0) {
			first = out;
		} else {
			CHECK(out == first);
		}
		DiffStore back;
		REQUIRE(back.deserialise(out));
		CHECK(back.serialise() == out);
		CHECK(back == s);
		CHECK(back.digest() == s.digest());
		std::mt19937 shuffle(static_cast<uint32_t>(pass + 1));
		std::shuffle(order.begin(), order.end(), shuffle);
	}
}

TEST_CASE("a malformed buffer is refused and leaves the store empty") {
	DiffStore s;
	s.put({0, 0}, 1, "a", 5, bytes({1, 2, 3}));
	s.mark_blood({3, 3}, 4);
	const std::vector<uint8_t> good = s.serialise();
	for (size_t cut = 0; cut < good.size(); cut++) {
		DiffStore t;
		t.put({9, 9}, 1, "old", 1, {});
		CHECK_FALSE(t.deserialise(std::vector<uint8_t>(good.begin(), good.begin() + static_cast<std::ptrdiff_t>(cut))));
		CHECK(t.cells().empty());
	}
	std::vector<uint8_t> bad_magic = good;
	bad_magic[0] = 'X';
	DiffStore t;
	CHECK_FALSE(t.deserialise(bad_magic));
	std::vector<uint8_t> trailing = good;
	trailing.push_back(0);
	CHECK_FALSE(t.deserialise(trailing));
}

TEST_CASE("a cell fully smeared costs a bitset and a nibble a tile") {
	DiffStore s;
	for (int64_t y = 0; y < CELL_TILES; y++) {
		for (int64_t x = 0; x < CELL_TILES; x++) {
			s.mark_blood({x, y}, x + y);
		}
	}
	CHECK(s.cells_bytes() == 4 + 12 + 2 + 50 + 200);
}
