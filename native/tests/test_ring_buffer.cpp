// SND-05: the lock-free ring between the capture device's thread and the game's.

#include "doctest.h"

#include <thread>
#include <vector>

#include "core/voice/ring_buffer.h"

using lb::core::voice::SpscRing;

TEST_CASE("SND-05: the ring rounds up to a power of two and keeps order") {
	SpscRing<float> r(1000);
	CHECK(r.capacity() == 1024);
	const float in[5] = {1, 2, 3, 4, 5};
	CHECK(r.push(in, 5) == 5);
	float out[3];
	CHECK(r.pop(out, 3));
	CHECK(out[0] == 1.0f);
	CHECK(out[2] == 3.0f);
	CHECK_FALSE(r.pop(out, 3)); // only 2 waiting: nothing taken
	CHECK(r.size() == 2);
}

TEST_CASE("SND-05: a full ring drops the excess and counts it") {
	SpscRing<float> r(4);
	const float in[6] = {1, 2, 3, 4, 5, 6};
	CHECK(r.push(in, 6) == 4);
	CHECK(r.dropped() == 2);
}

TEST_CASE("SND-05: wipe empties the ring and zeroes every slot") {
	SpscRing<float> r(8);
	const float in[6] = {1, 2, 3, 4, 5, 6};
	r.push(in, 6);
	float out[2];
	r.pop(out, 2);
	CHECK_FALSE(r.all_zero());
	r.wipe();
	CHECK(r.all_zero());
	CHECK(r.size() == 0);
	CHECK(r.dropped() == 0);
}

TEST_CASE("SND-05: one producer and one consumer on two threads lose nothing in order") {
	SpscRing<int> r(256);
	const int total = 200000;
	std::thread producer([&]() {
		int next = 0;
		while (next < total) {
			const int chunk[7] = {next, next + 1, next + 2, next + 3, next + 4, next + 5, next + 6};
			const int k = std::min(7, total - next);
			const size_t pushed = r.push(chunk, static_cast<size_t>(k));
			next += static_cast<int>(pushed);
		}
	});
	int expect = 0;
	bool ordered = true;
	while (expect < total) {
		int v;
		if (r.pop(&v, 1)) {
			ordered = ordered && v == expect;
			expect++;
		}
	}
	producer.join();
	CHECK(ordered);
}
