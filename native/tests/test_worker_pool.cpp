// GEN-11: the worker pool: each cell derived once, cancelled when unwanted, nearest first, and
// the same layouts whatever the number of threads.

#include "core/gen/gen_pool.h"
#include "layout_fixture.h"

#include <doctest.h>

#include <chrono>
#include <thread>

using namespace layout_fixture;

namespace {

std::vector<GenPool::Result> drain(GenPool &pool, size_t want) {
	std::vector<GenPool::Result> out;
	const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(30);
	while (out.size() < want && std::chrono::steady_clock::now() < until) {
		for (GenPool::Result &r : pool.take(64)) {
			out.push_back(std::move(r));
		}
		if (out.size() < want) {
			std::this_thread::sleep_for(std::chrono::milliseconds(1));
		}
	}
	return out;
}

} // namespace

TEST_CASE("GEN-11 a wanted cell is derived once, nearest first, and dropped when unwanted") {
	auto set = template_set();
	Run r = run(5, set);
	Deriver d(r.inputs());
	GenPool pool(d, 0); // synchronous
	pool.want({3, 3}, 5);
	pool.want({3, 3}, 5);
	pool.want({1, 1}, 1);
	pool.want({2, 2}, 9);
	pool.want({2, 2}, 2); // re-prioritised
	CHECK(pool.queued() == 3);
	pool.unwant({3, 3});
	const std::vector<GenPool::Result> one = pool.take(1);
	REQUIRE(one.size() == 1);
	CHECK(one[0].cell == Coord{1, 1});
	const std::vector<GenPool::Result> rest = pool.take(10);
	REQUIRE(rest.size() == 1);
	CHECK(rest[0].cell == Coord{2, 2});
	CHECK(pool.derived() == 2);
	CHECK(pool.take(10).empty());
	pool.want({1, 1}, 1); // taken cells can be asked for again (after eviction)
	CHECK(pool.take(10).size() == 1);
}

TEST_CASE("GEN-11 the same layouts with 0, 1, 2 or 4 workers, at normal or background priority") {
	auto set = template_set();
	Run r = run(11, set);
	std::map<Coord, uint64_t> first;
	for (int32_t threads : {0, 1, 2, 4, -2}) {
		Deriver d(r.inputs());
		GenPool pool(d, std::abs(threads), threads < 0); // -2: two workers below normal priority
		std::vector<Coord> cells;
		for (int64_t y = -7; y <= 7; y++) {
			for (int64_t x = -7; x <= 7; x++) {
				cells.push_back({x, y});
				pool.want({x, y}, std::abs(x) + std::abs(y));
			}
		}
		const std::vector<GenPool::Result> got = drain(pool, cells.size());
		REQUIRE(got.size() == cells.size());
		for (const GenPool::Result &res : got) {
			REQUIRE(res.layout.has_value());
			if (threads == 0) {
				first[res.cell] = res.layout->digest;
			} else {
				CHECK(first[res.cell] == res.layout->digest);
			}
		}
		CHECK(pool.derived() == cells.size());
		CHECK(pool.percentile_ms(0.99) >= pool.percentile_ms(0.5));
	}
}

TEST_CASE("GEN-11 a finished cell no longer wanted is discarded") {
	auto set = template_set();
	Run r = run(12, set);
	Deriver d(r.inputs());
	GenPool pool(d, 2);
	for (int64_t x = 1; x <= 20; x++) {
		pool.want({x, 4}, x);
	}
	const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(30);
	while (pool.finished() < 20 && std::chrono::steady_clock::now() < until) {
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	}
	REQUIRE(pool.finished() == 20);
	pool.unwant({5, 4});
	pool.unwant({6, 4});
	const std::vector<GenPool::Result> got = pool.take(100);
	CHECK(got.size() == 18);
	for (const GenPool::Result &res : got) {
		CHECK(res.cell != Coord{5, 4});
	}
	CHECK(got.front().cell == Coord{1, 4}); // nearest first
}
