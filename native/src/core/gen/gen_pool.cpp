#include "core/gen/gen_pool.h"

#include <algorithm>
#include <chrono>
#include <climits>
#include <cstdlib>
#include <iterator>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#elif defined(__linux__)
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

namespace lb::core::gen {

using lb::core::world::Coord;

int64_t chebyshev(Coord a, Coord b) {
	return std::max(std::abs(a.x - b.x), std::abs(a.y - b.y));
}

int64_t nearest_holder(Coord cell, const std::vector<Coord> &holders) {
	int64_t best = INT64_MAX;
	for (const Coord &h : holders) {
		best = std::min(best, chebyshev(cell, h));
	}
	return best;
}

std::set<Coord> required_cells(const std::vector<Coord> &holders, int32_t radius) {
	std::set<Coord> out;
	for (const Coord &h : holders) {
		for (int64_t y = h.y - radius; y <= h.y + radius; y++) {
			for (int64_t x = h.x - radius; x <= h.x + radius; x++) {
				out.insert(Coord{x, y});
			}
		}
	}
	return out;
}

std::vector<Coord> evictions(const std::vector<Coord> &loaded, const std::vector<Coord> &holders, const std::set<Coord> &pinned,
		const WindowParams &p) {
	std::vector<std::pair<int64_t, Coord>> beyond; // (not `far`: windows.h defines it away)
	std::vector<std::pair<int64_t, Coord>> spare; // outside every required set but within the eviction radius
	for (const Coord &c : loaded) {
		if (pinned.count(c) != 0) {
			continue;
		}
		const int64_t d = nearest_holder(c, holders);
		if (d > p.evict) {
			beyond.emplace_back(d, c);
		} else if (d > p.generate) {
			spare.emplace_back(d, c);
		}
	}
	auto farthest_first = [](const std::pair<int64_t, Coord> &a, const std::pair<int64_t, Coord> &b) {
		return a.first != b.first ? a.first > b.first : a.second < b.second;
	};
	std::sort(beyond.begin(), beyond.end(), farthest_first);
	std::sort(spare.begin(), spare.end(), farthest_first);
	std::vector<Coord> out;
	for (const auto &[d, c] : beyond) {
		out.push_back(c);
	}
	size_t live = loaded.size() - out.size();
	for (const auto &[d, c] : spare) {
		if (live <= p.max_live) {
			break;
		}
		out.push_back(c);
		live--;
	}
	return out;
}

namespace {

// Every cell within `radius` of a holder, sorted and unique.
std::vector<Coord> square_union(const std::vector<Coord> &holders, int32_t radius) {
	std::vector<Coord> out;
	const size_t side = static_cast<size_t>(2 * radius + 1);
	out.reserve(holders.size() * side * side);
	for (const Coord &h : holders) {
		for (int64_t y = h.y - radius; y <= h.y + radius; y++) {
			for (int64_t x = h.x - radius; x <= h.x + radius; x++) {
				out.push_back(Coord{x, y});
			}
		}
	}
	std::sort(out.begin(), out.end());
	out.erase(std::unique(out.begin(), out.end()), out.end());
	return out;
}

// The calling thread below normal priority, where the platform allows (a nice of 10 on Linux).
void lower_this_thread() {
#ifdef _WIN32
	SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
#elif defined(__linux__)
	setpriority(PRIO_PROCESS, static_cast<id_t>(syscall(SYS_gettid)), 10);
#endif
}

std::vector<Coord> minus(const std::vector<Coord> &a, const std::vector<Coord> &b) {
	std::vector<Coord> out;
	std::set_difference(a.begin(), a.end(), b.begin(), b.end(), std::back_inserter(out));
	return out;
}

} // namespace

Window::Window(int32_t required, int32_t prefetch) : required_(required), prefetch_radius_(std::max(required, prefetch)) {}

Window::Change Window::update(std::vector<Coord> holders) {
	std::sort(holders.begin(), holders.end());
	holders.erase(std::unique(holders.begin(), holders.end()), holders.end());
	Change c;
	if (holders == holders_) {
		return c;
	}
	c.moved = true;
	std::vector<Coord> required = square_union(holders, required_);
	std::vector<Coord> prefetch = square_union(holders, prefetch_radius_);
	c.entered = minus(required, required_set_);
	c.left = minus(required_set_, required);
	c.arrived = minus(prefetch, prefetch_);
	c.departed = minus(prefetch_, prefetch);
	holders_ = std::move(holders);
	required_set_ = std::move(required);
	prefetch_ = std::move(prefetch);
	return c;
}

GenPool::GenPool(const Deriver &deriver, int32_t threads, bool background) : deriver_(deriver) {
	for (int32_t i = 0; i < threads; i++) {
		workers_.emplace_back([this, background] { work(background); });
	}
}

GenPool::~GenPool() {
	{
		std::lock_guard<std::mutex> lock(mutex_);
		stopping_ = true;
	}
	wake_.notify_all();
	for (std::thread &t : workers_) {
		t.join();
	}
}

void GenPool::want(Coord cell, int64_t priority) {
	std::lock_guard<std::mutex> lock(mutex_);
	cancelled_.erase(cell);
	if (running_.count(cell) != 0 || done_.count(cell) != 0) {
		return;
	}
	auto it = priority_.find(cell);
	if (it != priority_.end()) {
		if (it->second == priority) {
			return;
		}
		queue_.erase({it->second, cell});
	}
	priority_[cell] = priority;
	queue_.insert({priority, cell});
	wake_.notify_one();
}

void GenPool::unwant(Coord cell) {
	std::lock_guard<std::mutex> lock(mutex_);
	auto it = priority_.find(cell);
	if (it != priority_.end()) {
		queue_.erase({it->second, cell});
		priority_.erase(it);
	}
	if (running_.count(cell) != 0) {
		cancelled_.insert(cell);
	}
	done_.erase(cell);
}

bool GenPool::run_one(std::unique_lock<std::mutex> &lock) {
	if (queue_.empty()) {
		return false;
	}
	const auto [priority, cell] = *queue_.begin();
	queue_.erase(queue_.begin());
	priority_.erase(cell);
	running_[cell] = priority;
	lock.unlock();
	const auto start = std::chrono::steady_clock::now();
	std::optional<Layout> layout = deriver_.derive(cell, 0);
	const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
	lock.lock();
	running_.erase(cell);
	derived_++;
	times_.push_back(ms);
	if (times_.size() > 4096) {
		times_.pop_front();
	}
	if (cancelled_.erase(cell) == 0) {
		done_[cell] = {priority, Result{cell, std::move(layout), ms}};
	}
	return true;
}

void GenPool::work(bool background) {
	if (background) {
		lower_this_thread();
	}
	std::unique_lock<std::mutex> lock(mutex_);
	while (true) {
		wake_.wait(lock, [this] { return stopping_ || !queue_.empty(); });
		if (stopping_) {
			return;
		}
		run_one(lock);
	}
}

std::vector<GenPool::Result> GenPool::take(size_t max) {
	std::unique_lock<std::mutex> lock(mutex_);
	if (workers_.empty()) {
		while (done_.size() < max && run_one(lock)) {
		}
	}
	std::vector<std::pair<int64_t, Coord>> order;
	for (const auto &[cell, entry] : done_) {
		order.emplace_back(entry.first, cell);
	}
	std::sort(order.begin(), order.end());
	std::vector<Result> out;
	for (const auto &[priority, cell] : order) {
		if (out.size() >= max) {
			break;
		}
		auto it = done_.find(cell);
		out.push_back(std::move(it->second.second));
		done_.erase(it);
	}
	return out;
}

size_t GenPool::queued() const {
	std::lock_guard<std::mutex> lock(mutex_);
	return queue_.size();
}

size_t GenPool::running() const {
	std::lock_guard<std::mutex> lock(mutex_);
	return running_.size();
}

size_t GenPool::finished() const {
	std::lock_guard<std::mutex> lock(mutex_);
	return done_.size();
}

double GenPool::percentile_ms(double fraction) const {
	std::vector<double> t;
	{
		std::lock_guard<std::mutex> lock(mutex_);
		t.assign(times_.begin(), times_.end());
	}
	if (t.empty()) {
		return 0.0;
	}
	std::sort(t.begin(), t.end());
	const size_t i = std::min(t.size() - 1, static_cast<size_t>(fraction * static_cast<double>(t.size())));
	return t[i];
}

} // namespace lb::core::gen
