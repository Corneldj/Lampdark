#pragma once
// GEN-11: lazy generation. The window sets say which cells a run needs (every cell within the
// generation radius of a holder, Chebyshev) and which it may drop (farther than the eviction
// radius from every holder, never a pinned cell; over the live-cell cap, the farthest outside
// every required set). The pool derives wanted cells on worker threads, nearest first, each cell
// once, cancelling cells no longer wanted; content never depends on threads, timing or order
// (derive_layout is pure). Server-only.

#include "core/gen/derive.h"

#include <condition_variable>
#include <deque>
#include <set>
#include <thread>

namespace lb::core::gen {

struct WindowParams {
	int32_t generate = 4; // mine.generation_radius_cells
	int32_t evict = 6; // mine.eviction_radius_cells
	size_t max_live = 700; // mine.max_live_cells
};

int64_t chebyshev(lb::core::world::Coord a, lb::core::world::Coord b);
// The distance (Chebyshev, in cells) to the nearest holder; INT64_MAX with none.
int64_t nearest_holder(lb::core::world::Coord cell, const std::vector<lb::core::world::Coord> &holders);
// Every cell within `radius` of a holder, sorted.
std::set<lb::core::world::Coord> required_cells(const std::vector<lb::core::world::Coord> &holders, int32_t radius);
// The loaded cells to drop, in order: beyond `evict` of every holder (the farthest first), then,
// while over the cap, the farthest outside every required set. Pinned cells never go.
std::vector<lb::core::world::Coord> evictions(const std::vector<lb::core::world::Coord> &loaded,
		const std::vector<lb::core::world::Coord> &holders, const std::set<lb::core::world::Coord> &pinned, const WindowParams &p);

// The window manager: the required set (every cell within `required` of a holder's cell) and the
// prefetch set (within `prefetch`, holding the required set), kept between updates. An update
// whose holders stand in the cells they stood in reports nothing, so a quiet tick costs next to
// nothing; otherwise it reports what entered and left each set.
class Window {
public:
	struct Change {
		bool moved = false; // the holders' cells differ from the last update's
		std::vector<lb::core::world::Coord> entered; // new to the required set
		std::vector<lb::core::world::Coord> left; // gone from the required set
		std::vector<lb::core::world::Coord> arrived; // new to the prefetch set
		std::vector<lb::core::world::Coord> departed; // gone from the prefetch set
	};

	Window(int32_t required, int32_t prefetch);
	// The holders' cells this tick, in any order, repeats allowed.
	Change update(std::vector<lb::core::world::Coord> holders);
	const std::vector<lb::core::world::Coord> &holders() const { return holders_; } // sorted, unique
	const std::vector<lb::core::world::Coord> &prefetch_cells() const { return prefetch_; } // sorted
	int32_t required_radius() const { return required_; }
	int32_t prefetch_radius() const { return prefetch_radius_; }

private:
	int32_t required_;
	int32_t prefetch_radius_;
	std::vector<lb::core::world::Coord> holders_;
	std::vector<lb::core::world::Coord> required_set_; // sorted
	std::vector<lb::core::world::Coord> prefetch_; // sorted
};

class GenPool {
public:
	struct Result {
		lb::core::world::Coord cell;
		std::optional<Layout> layout;
		double ms = 0.0; // the derive's wall time
	};

	// `threads` 0: synchronous, jobs run on the caller's thread in take(). `background`: the workers
	// run below normal priority (a server on a player's machine, beside the game's own frame).
	GenPool(const Deriver &deriver, int32_t threads, bool background = false);
	~GenPool();
	GenPool(const GenPool &) = delete;
	GenPool &operator=(const GenPool &) = delete;

	// Ask for a cell at `priority` (lower first). Asking again only updates a queued job's priority;
	// a cell running or finished is not derived twice.
	void want(lb::core::world::Coord cell, int64_t priority);
	// Stop wanting a cell: a queued job is dropped, a running or finished one discarded.
	void unwant(lb::core::world::Coord cell);
	// Up to `max` finished results, lowest priority first (synchronous: derived now).
	std::vector<Result> take(size_t max);

	size_t queued() const;
	size_t running() const;
	size_t finished() const;
	uint64_t derived() const { return derived_.load(); }
	// The derive time at `fraction` (0.5, 0.99) over the last 4,096 derives, in ms.
	double percentile_ms(double fraction) const;
	int32_t threads() const { return static_cast<int32_t>(workers_.size()); }

private:
	const Deriver &deriver_;
	mutable std::mutex mutex_;
	std::condition_variable wake_;
	std::set<std::pair<int64_t, lb::core::world::Coord>> queue_; // (priority, cell)
	std::map<lb::core::world::Coord, int64_t> priority_; // queued cells
	std::map<lb::core::world::Coord, int64_t> running_; // cell -> priority
	std::set<lb::core::world::Coord> cancelled_; // running but no longer wanted
	std::map<lb::core::world::Coord, std::pair<int64_t, Result>> done_;
	std::deque<double> times_;
	std::vector<std::thread> workers_;
	bool stopping_ = false;
	std::atomic<uint64_t> derived_{0};

	void work(bool background);
	bool run_one(std::unique_lock<std::mutex> &lock);
};

} // namespace lb::core::gen
