#pragma once
// SND-05: a single-producer, single-consumer lock-free ring of samples between the capture
// device's thread and the game thread (and back, for the echo reference). Capacity is a power of
// two. Nothing in it is ever written anywhere: `wipe` zeroes it when the microphone closes.
// Engine-free.

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace lb::core::voice {

template <typename T>
class SpscRing {
public:
	// `capacity` is rounded up to a power of two (at least 2).
	explicit SpscRing(size_t capacity) {
		size_t n = 2;
		while (n < capacity) {
			n <<= 1;
		}
		buf_.assign(n, T{});
		mask_ = n - 1;
	}

	size_t capacity() const { return buf_.size(); }
	size_t size() const { return head_.load(std::memory_order_acquire) - tail_.load(std::memory_order_acquire); }
	size_t space() const { return capacity() - size(); }

	// Producer: writes up to `n` items; returns how many fit (the rest are dropped and counted).
	size_t push(const T *src, size_t n) {
		const size_t head = head_.load(std::memory_order_relaxed);
		const size_t tail = tail_.load(std::memory_order_acquire);
		const size_t room = capacity() - (head - tail);
		const size_t k = std::min(n, room);
		for (size_t i = 0; i < k; i++) {
			buf_[(head + i) & mask_] = src[i];
		}
		head_.store(head + k, std::memory_order_release);
		if (k < n) {
			dropped_.fetch_add(n - k, std::memory_order_relaxed);
		}
		return k;
	}

	// Consumer: reads exactly `n` items, or nothing when fewer are waiting.
	bool pop(T *dst, size_t n) {
		const size_t tail = tail_.load(std::memory_order_relaxed);
		const size_t head = head_.load(std::memory_order_acquire);
		if (head - tail < n) {
			return false;
		}
		for (size_t i = 0; i < n; i++) {
			dst[i] = buf_[(tail + i) & mask_];
		}
		tail_.store(tail + n, std::memory_order_release);
		return true;
	}

	uint64_t dropped() const { return dropped_.load(std::memory_order_relaxed); }

	// Only while neither side runs (the device is closed): empties the ring and zeroes its memory.
	void wipe() {
		std::fill(buf_.begin(), buf_.end(), T{});
		head_.store(0, std::memory_order_relaxed);
		tail_.store(0, std::memory_order_relaxed);
		dropped_.store(0, std::memory_order_relaxed);
	}

	// Only for tests: whether every slot is zero.
	bool all_zero() const {
		return std::all_of(buf_.begin(), buf_.end(), [](const T &v) { return v == T{}; });
	}

private:
	std::vector<T> buf_;
	size_t mask_ = 1;
	std::atomic<size_t> head_{0};
	std::atomic<size_t> tail_{0};
	std::atomic<uint64_t> dropped_{0};
};

} // namespace lb::core::voice
